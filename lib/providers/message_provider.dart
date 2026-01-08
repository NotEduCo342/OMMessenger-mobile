import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/conversation.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/connectivity_service.dart';
import '../database/database.dart' hide Message, Conversation;

class MessageProvider with ChangeNotifier {
  final WebSocketService _wsService = WebSocketService();
  final ApiService _apiService = ApiService();
  final AppDatabase _database = AppDatabase();
  late final OfflineQueueService _queueService;
  final ConnectivityService _connectivityService = ConnectivityService();
  final _uuid = const Uuid();
  
  StreamSubscription? _connectivitySubscription;

  final Map<int, List<Message>> _messagesByUser = {};
  final Map<int, Conversation> _conversations = {};
  final Map<String, Message> _pendingMessages = {};
  final Map<int, bool> _typingUsers = {};
  final Map<int, int?> _messageCursors = {}; // Track pagination cursor per user
  final Map<int, bool> _hasMoreMessages = {}; // Track if more messages exist
  final Set<int> _userFetchInFlight = {};

  bool _isInitialized = false;
  User? _currentUser;
  bool _isOnline = true;
  int _pendingQueueCount = 0;

  List<Conversation> get conversations => _conversations.values.toList()
    ..sort((a, b) {
      final aTime = a.lastActivity ?? DateTime(1970);
      final bTime = b.lastActivity ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

  ConnectionStatus get connectionStatus => _wsService.status;
  Stream<ConnectionStatus> get connectionStream => _wsService.statusStream;
  int? get pingMs => _wsService.pingMs;
  Stream<int?> get pingMsStream => _wsService.pingMsStream;
  bool get isOnline => _isOnline;
  int get pendingQueueCount => _pendingQueueCount;
  int? get currentUserId => _currentUser?.id;
  bool hasMoreMessages(int userId) => _hasMoreMessages[userId] ?? true;

  List<Message> getMessages(int userId) {
    return _messagesByUser[userId] ?? [];
  }

  bool _isPlaceholderUser(User user) {
    return user.username.startsWith('User ') || user.fullName.startsWith('User ');
  }

  Future<void> _ensurePeerProfile(int userId) async {
    if (_userFetchInFlight.contains(userId)) return;
    _userFetchInFlight.add(userId);

    try {
      final response = await _apiService.get('/users/$userId');
      if (response is Map && response['user'] != null) {
        final fetched = User.fromJson(Map<String, dynamic>.from(response['user']));
        await upsertConversationPeer(fetched);
      }
    } catch (_) {
      // Best-effort: don't spam UI or fail message flow.
    } finally {
      _userFetchInFlight.remove(userId);
    }
  }

  bool isTyping(int userId) => _typingUsers[userId] ?? false;

  Future<void> handleAppResumed() async {
    // When the app resumes after screen-off/background, timers/reconnects may
    // have been paused. Force a reconnect attempt and refresh connectivity.
    try {
      _connectivityService.refresh();
      _isOnline = _connectivityService.isOnline;

      if (_isOnline) {
        await _wsService.connect();
        _wsService.requestPing();
      }
    } catch (_) {
      // Best-effort.
    } finally {
      notifyListeners();
    }
  }

  Future<void> upsertConversationPeer(User otherUser) async {
    final existing = _conversations[otherUser.id];
    final updated = Conversation(
      otherUser: otherUser,
      lastMessage: existing?.lastMessage,
      unreadCount: existing?.unreadCount ?? 0,
      lastActivity: existing?.lastActivity,
    );
    _conversations[otherUser.id] = updated;

    await _database.upsertConversation(ConversationsCompanion.insert(
      otherUserId: Value(otherUser.id),
      otherUsername: otherUser.username,
      otherFullName: otherUser.fullName,
      otherAvatar: Value(otherUser.avatar),
      otherIsOnline: Value(otherUser.isOnline),
      lastMessageContent: Value(existing?.lastMessage?.content),
      lastMessageTime: Value(existing?.lastMessage?.createdAt),
      updatedAt: DateTime.now(),
    ));

    notifyListeners();
  }

  Future<void> initialize(User currentUser) async {
    if (_isInitialized) return;
    
    _currentUser = currentUser;
    _isInitialized = true;

    // Initialize queue service
    _queueService = OfflineQueueService(
      database: _database,
      connectivityService: _connectivityService,
      onMessageReady: _sendQueuedMessage,
    );

    // Start connectivity monitoring
    _connectivityService.refresh();
    _isOnline = _connectivityService.isOnline;
    _connectivitySubscription = _connectivityService.statusStream.listen((status) {
      final wasOnline = _isOnline;
      _isOnline = status == NetworkStatus.online;
      
      if (!wasOnline && _isOnline) {
        // Just came back online
        _queueService.setOnline(true);
        _wsService.connect();
      } else if (wasOnline && !_isOnline) {
        // Just went offline
        _queueService.setOnline(false);
      }
      
      notifyListeners();
    });

    // Load conversations from database first so UI isn't empty while we connect.
    await _loadConversations();

    // Listen to WebSocket messages
    _wsService.messageStream.listen(_handleWebSocketMessage);

    // Connect WebSocket (don't block initial UI)
    Future.microtask(() async {
      try {
        await _wsService.connect();
      } catch (_) {
        // best-effort
      }
    });

    // Best-effort: refresh conversations from server.
    // This repopulates the local DB after reinstall/uninstall.
    try {
      await refreshConversations();
    } catch (_) {
      // Non-fatal.
    }

    // Update pending queue count
    _updateQueueCount();

    notifyListeners();
  }

  Future<void> _loadConversations() async {
    try {
      // Load conversations from local database
      final convos = await _database.getAllConversations();
      
      for (final convo in convos) {
        _conversations[convo.otherUserId] = Conversation(
          otherUser: User(
            id: convo.otherUserId,
            username: convo.otherUsername,
            email: '',
            fullName: convo.otherFullName,
            avatar: convo.otherAvatar,
            isOnline: convo.otherIsOnline,
          ),
          lastMessage: convo.lastMessageContent != null
              ? (() {
                  final createdAtUtc = (convo.lastMessageTime ?? DateTime.now()).toUtc();
                  return Message(
                  id: 0,
                  clientId: '',
                  senderId: convo.otherUserId,
                  sender: null,
                  recipientId: _currentUser?.id,
                  groupId: null,
                  content: convo.lastMessageContent!,
                  messageType: 'text',
                  status: 'delivered',
                  isDelivered: true,
                  isRead: true,
                  createdAt: createdAtUtc,
                  createdAtUnix: createdAtUtc.millisecondsSinceEpoch ~/ 1000,
                );
                })()
              : null,
          unreadCount: convo.unreadCount,
          lastActivity: convo.lastMessageTime,
        );
      }
      
      notifyListeners();
    } catch (e) {
      print('Error loading conversations: $e');
    }
  }

  /// Refresh conversations from API
  Future<void> refreshConversations() async {
    if (!_isOnline) {
      print('Cannot refresh conversations: offline');
      return;
    }

    try {
      await _syncConversationsFromServer();
      // Reload from DB to ensure UI stays consistent with persisted state.
      await _loadConversations();
    } catch (e) {
      print('Error refreshing conversations: $e');
      rethrow;
    }
  }

  Future<void> _syncConversationsFromServer() async {
    const limit = 100;
    String? cursorCreatedAt;
    int? cursorMessageId;

    // Cap pages to prevent infinite loops if server misbehaves.
    for (var page = 0; page < 20; page++) {
      var endpoint = '/conversations?limit=$limit';
      if (cursorCreatedAt != null && cursorMessageId != null) {
        endpoint += '&cursor_created_at=${Uri.encodeComponent(cursorCreatedAt)}'
            '&cursor_message_id=$cursorMessageId';
      }

      final response = await _apiService.get(endpoint);
      if (response is! Map) return;

      final items = response['conversations'];
      if (items is! List) return;

      for (final item in items) {
        if (item is! Map) continue;

        final peerJson = item['peer'];
        if (peerJson is! Map) continue;

        final peer = User.fromJson(Map<String, dynamic>.from(peerJson));
        final unreadCount = (item['unread_count'] is int) ? item['unread_count'] as int : 0;

        Message? lastMessage;
        final lastMessageJson = item['last_message'];
        if (lastMessageJson is Map) {
          lastMessage = Message.fromJson(Map<String, dynamic>.from(lastMessageJson));
        }

        DateTime? lastActivity;
        final lastActivityStr = item['last_activity'];
        if (lastActivityStr is String) {
          try {
            lastActivity = DateTime.parse(lastActivityStr);
          } catch (_) {
            lastActivity = null;
          }
        }
        lastActivity ??= lastMessage?.createdAt;

        _conversations[peer.id] = Conversation(
          otherUser: peer,
          lastMessage: lastMessage,
          unreadCount: unreadCount,
          lastActivity: lastActivity,
        );

        await _database.upsertConversation(ConversationsCompanion.insert(
          otherUserId: Value(peer.id),
          otherUsername: peer.username,
          otherFullName: peer.fullName,
          otherAvatar: Value(peer.avatar),
          otherIsOnline: Value(peer.isOnline),
          lastMessageContent: Value(lastMessage?.content),
          lastMessageTime: Value(lastMessage?.createdAt),
          unreadCount: Value(unreadCount),
          updatedAt: DateTime.now(),
        ));
      }

      final nextCreatedAt = response['next_cursor_created_at'];
      final nextMessageId = response['next_cursor_message_id'];

      if (nextCreatedAt is String && (nextMessageId is int || nextMessageId is num)) {
        cursorCreatedAt = nextCreatedAt;
        cursorMessageId = (nextMessageId as num).toInt();
        continue;
      }

      break;
    }

    notifyListeners();
  }

  Future<void> loadMessages(int userId, {int limit = 20, bool loadMore = false}) async {
    try {
      // Determine cursor for pagination
      int? cursor;
      if (loadMore) {
        cursor = _messageCursors[userId];
        if (cursor == null || !(_hasMoreMessages[userId] ?? true)) {
          print('No more messages to load for user $userId');
          return; // No more messages or already at end
        }
      }

      // First, load from local database
      if (!loadMore) {
        final localMessages = await _database.getMessagesForUser(
          userId,
          limit: limit,
        );
        
        if (localMessages.isNotEmpty) {
          final msgs = localMessages
            .map((dbMsg) => Message(
                    id: dbMsg.serverId ?? dbMsg.id,
                    clientId: dbMsg.clientId,
                    senderId: dbMsg.senderId,
                    sender: null,
                    recipientId: dbMsg.recipientId,
                    groupId: dbMsg.groupId,
                    content: dbMsg.content,
                    messageType: dbMsg.messageType,
                    status: dbMsg.status,
                    isDelivered: dbMsg.isDelivered,
                    isRead: dbMsg.isRead,
                    createdAt: (dbMsg.createdAtUnix != null)
                        ? DateTime.fromMillisecondsSinceEpoch(
                            dbMsg.createdAtUnix! * 1000,
                            isUtc: true,
                          )
                        : (dbMsg.createdAt.isUtc ? dbMsg.createdAt : dbMsg.createdAt.toUtc()),
                    createdAtUnix: dbMsg.createdAtUnix ??
                        (dbMsg.createdAt.isUtc
                            ? (dbMsg.createdAt.millisecondsSinceEpoch ~/ 1000)
                            : (dbMsg.createdAt.toUtc().millisecondsSinceEpoch ~/ 1000)),
                  ))
              .toList();
          // ChatScreen uses ListView(reverse:true). For that, our in-memory list
          // must be newest-first so the newest message (index 0) renders at bottom.
          _sortConversationMessages(msgs);
          _messagesByUser[userId] = msgs;

          // Cursor should point to the oldest server-backed message we have loaded.
          final oldestServerBacked = msgs.lastWhere(
            (m) => m.id > 0,
            orElse: () => msgs.last,
          );
          _messageCursors[userId] = oldestServerBacked.id > 0 ? oldestServerBacked.id : null;
          
          notifyListeners();
        }
      }

      // Then fetch from API if online
      if (!_isOnline) return;

      final endpoint = cursor != null
          ? '/messages?recipient_id=$userId&limit=$limit&cursor=$cursor'
          : '/messages?recipient_id=$userId&limit=$limit';
      
      final response = await _apiService.get(endpoint);
      final messages = (response['messages'] as List)
          .map((json) => Message.fromJson(json))
          .toList();

      // Check if more messages exist (backend returns newest-first)
      final hasMore = messages.length == limit;
      _hasMoreMessages[userId] = hasMore;

      if (messages.isNotEmpty) {
        // Backend provides next_cursor (oldest message ID in this page)
        final nextCursor = response['next_cursor'];
        if (nextCursor is int && nextCursor > 0) {
          _messageCursors[userId] = nextCursor;
        } else {
          _messageCursors[userId] = messages.last.id;
        }

        // Save to database
        for (final msg in messages) {
          await _database.insertMessage(MessagesCompanion.insert(
            clientId: msg.clientId ?? _uuid.v4(),
            serverId: Value(msg.id),
            senderId: msg.senderId,
            recipientId: Value(msg.recipientId),
            groupId: Value(msg.groupId),
            content: msg.content,
            messageType: Value(msg.messageType),
            status: Value(msg.status),
            isDelivered: Value(msg.isDelivered),
            isRead: Value(msg.isRead),
            createdAt: msg.createdAt,
            createdAtUnix: Value(msg.createdAtUnix),
            updatedAt: msg.createdAt,
            isSentByMe: msg.senderId == _currentUser?.id,
          ));
        }

        if (loadMore) {
          // Load-more returns older messages. With newest-first ordering, append older
          // items to the end of the list.
          final list = _messagesByUser.putIfAbsent(userId, () => []);
          final existingIds = list.map((m) => m.id).toSet();
          final newMessages = messages.where((m) => !existingIds.contains(m.id)).toList();
          list.addAll(newMessages);
          _sortConversationMessages(list);
        } else {
          // Replace with newest-first list from backend, but preserve any pending
          // optimistic messages already shown.
          final existing = _messagesByUser[userId] ?? const <Message>[];
          final pending = existing.where((m) => _isPendingMessage(m)).toList();

          final merged = <Message>[];
          merged.addAll(pending);
          merged.addAll(messages);
          // Deduplicate by id/clientId.
          final seenIds = <int>{};
          final seenClientIds = <String>{};
          final deduped = <Message>[];
          for (final m in merged) {
            final cid = m.clientId;
            if (m.id > 0 && seenIds.contains(m.id)) continue;
            if (cid != null && cid.isNotEmpty && seenClientIds.contains(cid)) continue;
            if (m.id > 0) seenIds.add(m.id);
            if (cid != null && cid.isNotEmpty) seenClientIds.add(cid);
            deduped.add(m);
          }

          _sortConversationMessages(deduped);
          _messagesByUser[userId] = deduped;
          _updateConversation(userId, deduped);

          // If we still only have placeholder peer data, try to hydrate from message senders.
          final conv = _conversations[userId];
          if (conv != null && _isPlaceholderUser(conv.otherUser)) {
            final peerMsg = messages.cast<Message?>().firstWhere(
                  (m) => m != null && m.senderId == userId && m.sender != null,
                  orElse: () => null,
                );
            final peer = peerMsg?.sender;
            if (peer != null) {
              await upsertConversationPeer(peer);
            } else {
              await _ensurePeerProfile(userId);
            }
          }
        }
      } else if (!loadMore) {
        // No messages from API but might have local ones
        _hasMoreMessages[userId] = false;
      }

      notifyListeners();
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  /// Called when a conversation screen is opened.
  /// Clears unread count locally immediately and asks the server to mark the DM as read.
  Future<void> openConversation(int userId) async {
    // Local: clear unread count for snappy UI.
    final existing = _conversations[userId];
    if (existing != null && existing.unreadCount != 0) {
      _conversations[userId] = existing.copyWith(unreadCount: 0);
      await _database.clearUnreadCount(userId);
      notifyListeners();
    }

    // Server: mark all messages from this peer to me as read.
    // Best-effort; if it fails we'll still have local UI cleared, but on next
    // login the server will re-send unread_count unless this succeeds.
    try {
      await _apiService.post('/conversations/$userId/read', {});
    } catch (_) {
      // best-effort
    }
  }

  void sendMessage(int recipientId, String content) async {
    if (_currentUser == null) return;

    final clientId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final nowUnix = now.millisecondsSinceEpoch ~/ 1000;

    // Create optimistic message
    final message = Message(
      id: 0, // Temporary ID
      clientId: clientId,
      senderId: _currentUser!.id,
      sender: _currentUser,
      recipientId: recipientId,
      groupId: null,
      content: content,
      messageType: 'text',
      status: 'pending',
      isDelivered: false,
      isRead: false,
      createdAt: now,
      createdAtUnix: nowUnix,
    );

    // Save to database immediately
    await _database.insertMessage(MessagesCompanion.insert(
      clientId: clientId,
      senderId: _currentUser!.id,
      recipientId: Value(recipientId),
      content: content,
      messageType: const Value('text'),
      status: const Value('pending'),
      createdAt: now,
      createdAtUnix: Value(nowUnix),
      updatedAt: now,
      isSentByMe: true,
    ));

    // Add to message list (ChatScreen reverse:true expects newest-first)
    final messageList = _messagesByUser.putIfAbsent(recipientId, () => []);
    // Deduplicate by client_id
    messageList.removeWhere((m) => m.clientId == clientId);
    // Pending outgoing should appear as the newest message.
    messageList.insert(0, message);
    _sortConversationMessages(messageList);
    _pendingMessages[clientId] = message;

    // Update conversation
    _updateConversationWithMessage(recipientId, message);
    notifyListeners();

    // Always add to offline queue for retry logic
    await _queueService.enqueueMessage(
      clientId: clientId,
      recipientId: recipientId,
      content: content,
    );
    await _updateQueueCount();

    // Best-effort immediate send (queue will retry if this fails).
    if (_isOnline) {
      try {
        await _sendQueuedMessage(clientId, recipientId, content);
      } catch (_) {
        // Ignore: queued retry will handle it.
      }
    }
  }

  void _handleWebSocketMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    switch (type) {
      case 'ack':
        _handleAck(data);
        break;
      case 'message':
        _handleIncomingMessage(data);
        break;
      case 'typing':
        _handleTyping(data);
        break;
      case 'batch':
        _handleBatchMessages(data);
        break;
      case 'pong':
        // Pong received - connection healthy
        break;
      case 'error':
        _handleError(data);
        break;
      default:
        print('Unknown message type: $type');
    }
  }

  void _handleError(Map<String, dynamic> data) {
    final code = data['code'] as String?;
    final message = (data['error'] as String?) ?? (data['message'] as String?);
    final details = data['details'] as String?;
    print('⚠️ Server error: $code - $message ${details != null ? '($details)' : ''}');
  }

  void _handleAck(Map<String, dynamic> data) async {
    // Extract from payload wrapper if present
    final ackData = data['payload'] as Map<String, dynamic>? ?? data;
    
    final clientId = ackData['client_id'] as String?;
    final serverId = ackData['server_id'] as int?;
    final status = ackData['status'] as String?;
    final createdAtUnixRaw = ackData['created_at_unix'];
    final createdAtUnix = (createdAtUnixRaw is int || createdAtUnixRaw is num)
      ? (createdAtUnixRaw as num).toInt()
      : null;

    if (clientId == null || serverId == null) {
      return;
    }

    // Always update database first
    try {
      await _database.updateMessageWithServerInfo(
        clientId,
        serverId,
        status ?? 'sent',
        createdAtUnix: createdAtUnix,
      );
    } catch (e) {
      print('Error updating message in DB: $e');
    }
    
    // Remove from offline queue
    try {
      await _queueService.markMessageSent(clientId);
      await _updateQueueCount();
    } catch (e) {
      print('Error removing from queue: $e');
    }

    final pendingMessage = _pendingMessages[clientId];
    if (pendingMessage != null) {

      final createdAtUtc = createdAtUnix != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtUnix * 1000, isUtc: true)
          : pendingMessage.createdAt;
      final finalCreatedAtUnix = createdAtUnix ?? pendingMessage.createdAtUnix;

      // Update message with server ID
      final updatedMessage = Message(
        id: serverId,
        clientId: clientId,
        senderId: pendingMessage.senderId,
        sender: pendingMessage.sender,
        recipientId: pendingMessage.recipientId,
        groupId: pendingMessage.groupId,
        content: pendingMessage.content,
        messageType: pendingMessage.messageType,
        status: status ?? 'sent',
        isDelivered: status == 'delivered',
        isRead: status == 'read',
        createdAt: createdAtUtc,
        createdAtUnix: finalCreatedAtUnix,
      );

      // Replace in message list and re-sort by ID
      final userId = pendingMessage.recipientId!;
      final messages = _messagesByUser[userId];
      if (messages != null) {
        final index = messages.indexWhere((m) => m.clientId == clientId);
        if (index != -1) {
          messages[index] = updatedMessage;
          _sortConversationMessages(messages);
        }
      }

      _pendingMessages.remove(clientId);
      print('✅ Message ACK received: $clientId -> $serverId ($status)');
      notifyListeners();
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> data) async {
    // Extract from payload wrapper if present
    final messageData = data['message'] as Map<String, dynamic>? ?? data['payload'] as Map<String, dynamic>?;
    if (messageData == null) {
      print('⚠️ No message data in incoming message');
      return;
    }

    print('📥 Incoming message: ${messageData['id']}');

    final message = Message.fromJson(messageData);
    final otherUserId = message.senderId;

    // Persist peer profile ASAP to avoid placeholders.
    if (message.sender != null) {
      await upsertConversationPeer(message.sender!);
    } else {
      // If sender profile isn't included, hydrate via API.
      await _ensurePeerProfile(otherUserId);
    }

    // Save to database
    await _database.insertMessage(MessagesCompanion.insert(
      clientId: message.clientId ?? _uuid.v4(),
      serverId: Value(message.id),
      senderId: message.senderId,
      recipientId: Value(message.recipientId),
      groupId: Value(message.groupId),
      content: message.content,
      messageType: Value(message.messageType),
      status: const Value('delivered'),
      isDelivered: const Value(true),
      createdAt: message.createdAt,
      createdAtUnix: Value(message.createdAtUnix),
      updatedAt: message.createdAt,
      isSentByMe: false,
    ));

    // Update conversation in database
    await _database.upsertConversation(ConversationsCompanion.insert(
      otherUserId: Value(otherUserId),
      otherUsername: message.sender?.username ?? 'User $otherUserId',
      otherFullName: message.sender?.fullName ?? 'User $otherUserId',
      otherAvatar: const Value(''),
      otherIsOnline: const Value(false),
      lastMessageContent: Value(message.content),
      lastMessageTime: Value(message.createdAt),
      updatedAt: message.createdAt,
    ));

    // Add to message list (keep newest-first)
    final list = _messagesByUser.putIfAbsent(otherUserId, () => []);
    // Remove duplicate if exists
    list.removeWhere((m) => m.id == message.id || (m.clientId != null && m.clientId == message.clientId));
    list.add(message);
    _sortConversationMessages(list);
    _updateConversationWithMessage(otherUserId, message);
    notifyListeners();

    // Send delivery acknowledgment
    _wsService.send({
      'type': 'ack',
      'server_id': message.id,
      'status': 'delivered',
    });
  }

  void _handleTyping(Map<String, dynamic> data) {
    // Extract from payload wrapper if present
    final typingData = data['payload'] as Map<String, dynamic>? ?? data;
    
    final senderId = typingData['sender_id'] as int?;
    final isTyping = typingData['is_typing'] as bool? ?? false;

    if (senderId != null) {
      _typingUsers[senderId] = isTyping;
      notifyListeners();

      // Auto-clear typing indicator after 3 seconds
      if (isTyping) {
        Timer(const Duration(seconds: 3), () {
          if (_typingUsers[senderId] == true) {
            _typingUsers[senderId] = false;
            notifyListeners();
          }
        });
      }
    }
  }

  void _handleBatchMessages(Map<String, dynamic> data) {
    final messages = data['messages'] as List?;
    if (messages == null) return;

    for (final msgData in messages) {
      if (msgData['type'] == 'message') {
        _handleIncomingMessage(msgData);
      }
    }
  }

  void _updateConversation(int userId, List<Message> messages) {
    if (messages.isEmpty) return;

    final lastMessage = messages.first;
    final existingConv = _conversations[userId];
    final otherFromLast = (lastMessage.senderId == userId) ? lastMessage.sender : null;

    final conversation = Conversation(
      otherUser: otherFromLast ?? existingConv?.otherUser ?? User(
            id: userId,
            username: 'User $userId',
            email: '',
            fullName: 'User $userId',
            avatar: '',
            isOnline: false,
          ),
      lastMessage: lastMessage,
      unreadCount: 0,
      lastActivity: lastMessage.createdAt,
    );

    _conversations[userId] = conversation;
  }

  bool _isPendingMessage(Message m) {
    return m.status == 'pending' || m.id == 0;
  }

  void _sortConversationMessages(List<Message> list) {
    // Newest-first ordering compatible with ListView(reverse:true):
    // - Pending optimistic messages first (by createdAt desc)
    // - Then server-backed messages by id desc
    list.sort((a, b) {
      final aPending = _isPendingMessage(a);
      final bPending = _isPendingMessage(b);
      if (aPending != bPending) return aPending ? -1 : 1;

      if (aPending && bPending) {
        final byTime = b.createdAt.compareTo(a.createdAt);
        if (byTime != 0) return byTime;
        return (b.clientId ?? '').compareTo(a.clientId ?? '');
      }

      final byId = b.id.compareTo(a.id);
      if (byId != 0) return byId;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  void _updateConversationWithMessage(int userId, Message message) async {
    final existingConv = _conversations[userId];
    
    final conversation = Conversation(
      otherUser: existingConv?.otherUser ?? User(
        id: userId,
        username: 'User $userId',
        email: '',
        fullName: 'User $userId',
        avatar: '',
        isOnline: false,
      ),
      lastMessage: message,
      unreadCount: message.senderId != _currentUser?.id 
          ? (existingConv?.unreadCount ?? 0) + 1 
          : 0,
      lastActivity: message.createdAt,
    );
    
    _conversations[userId] = conversation;
    
    // Persist to database
    await _database.upsertConversation(ConversationsCompanion.insert(
      otherUserId: Value(userId),
      otherUsername: conversation.otherUser.username,
      otherFullName: conversation.otherUser.fullName,
      otherAvatar: Value(conversation.otherUser.avatar),
      otherIsOnline: Value(conversation.otherUser.isOnline),
      lastMessageContent: Value(message.content),
      lastMessageTime: Value(message.createdAt),
      updatedAt: message.createdAt,
    ));
  }

  void sendTypingIndicator(int recipientId, bool isTyping) {
    _wsService.sendTyping(recipientId, isTyping);
  }

  void markAsRead(int messageId) {
    _wsService.sendRead(messageId);
  }

  Future<void> _sendQueuedMessage(String clientId, int recipientId, String content) async {
    // Check network connectivity
    if (!_isOnline) {
      throw Exception('offline');
    }

    // Ensure WebSocket is connected
    if (_wsService.status != ConnectionStatus.connected) {
      await _wsService.connect();

      // If a connect attempt is already in-flight (or handshake is slow on high RTT),
      // wait a bit longer for the status to flip to connected.
      if (_wsService.status != ConnectionStatus.connected) {
        final ok = await _waitForWsConnected(const Duration(seconds: 12));
        if (!ok) {
          throw Exception('ws_not_connected');
        }
      }
    }

    _wsService.sendChatMessage(
      clientId: clientId,
      recipientId: recipientId,
      content: content,
    );
  }

  Future<bool> _waitForWsConnected(Duration timeout) async {
    if (_wsService.status == ConnectionStatus.connected) return true;

    final completer = Completer<bool>();
    StreamSubscription<ConnectionStatus>? sub;
    Timer? timer;

    sub = _wsService.statusStream.listen((status) {
      if (status == ConnectionStatus.connected && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    final result = await completer.future;
    await sub.cancel();
    timer.cancel();
    return result;
  }

  Future<void> _updateQueueCount() async {
    _pendingQueueCount = await _queueService.getPendingCount();
    notifyListeners();
  }

  Future<void> retryFailedMessages() async {
    await _queueService.retryAllMessages();
    await _updateQueueCount();
  }

  Future<void> clearQueue() async {
    await _queueService.clearQueue();
    await _updateQueueCount();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _queueService.dispose();
    _wsService.dispose();
    _database.close();
    super.dispose();
  }
}
