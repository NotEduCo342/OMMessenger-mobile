import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/conversation.dart';
import '../models/group.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_prefs.dart';
import '../services/notification_service.dart';
import '../database/database.dart' hide Message, Conversation;

class MessageProvider with ChangeNotifier {
  final WebSocketService _wsService = WebSocketService();
  final ApiService _apiService = ApiService();
  final AppDatabase _database = AppDatabase();
  late final OfflineQueueService _queueService;
  final ConnectivityService _connectivityService = ConnectivityService();
  final _uuid = const Uuid();
  
  StreamSubscription? _connectivitySubscription;

  final Map<String, List<Message>> _messagesByConversation = {};
  final Map<String, Conversation> _conversations = {};
  final Map<String, Message> _pendingMessages = {};
  final Map<int, bool> _typingUsers = {};
  final Map<String, int?> _messageCursors = {}; // Track pagination cursor per conversation
  final Map<String, bool> _hasMoreMessages = {}; // Track if more messages exist
  final Set<int> _userFetchInFlight = {};
  final Map<int, Map<int, int>> _groupReadStates = {}; // groupId -> userId -> lastReadMessageId
  final Map<int, Map<int, User>> _groupMembers = {}; // groupId -> userId -> User

  String? _activeConversationId;

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
  bool hasMoreMessages(String conversationId) => _hasMoreMessages[conversationId] ?? true;

  List<Message> getMessages(String conversationId) {
    return _messagesByConversation[conversationId] ?? [];
  }

  Conversation? getConversation(String conversationId) {
    return _conversations[conversationId];
  }

  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
  }

  Map<int, int> getGroupReadStates(int groupId) {
    return _groupReadStates[groupId] ?? const {};
  }

  Map<int, User> getGroupMembers(int groupId) {
    return _groupMembers[groupId] ?? const {};
  }

  List<User> getGroupReadersForMessage(int groupId, int messageId) {
    final states = _groupReadStates[groupId];
    if (states == null || states.isEmpty) return const [];
    final members = _groupMembers[groupId] ?? const {};
    final readers = <User>[];
    for (final entry in states.entries) {
      final userId = entry.key;
      if (userId == _currentUser?.id) continue;
      if (entry.value >= messageId) {
        final user = members[userId];
        if (user != null) readers.add(user);
      }
    }
    return readers;
  }

  (String kind, int id) _parseConversationId(String conversationId) {
    if (conversationId.startsWith('user_')) {
      return ('user', int.parse(conversationId.substring(5)));
    }
    if (conversationId.startsWith('group_')) {
      return ('group', int.parse(conversationId.substring(6)));
    }
    throw ArgumentError('Invalid conversationId: $conversationId');
  }

  String _dmConversationId(int userId) => 'user_$userId';
  String _groupConversationId(int groupId) => 'group_$groupId';

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
      await NotificationService.instance.cancelAll();
    } catch (_) {
      // Best-effort.
    } finally {
      notifyListeners();
    }
  }

  Future<void> upsertConversationPeer(User otherUser) async {
    final conversationId = _dmConversationId(otherUser.id);
    final existing = _conversations[conversationId];
    final updated = Conversation(
      conversationId: conversationId,
      type: ConversationType.dm,
      otherUser: otherUser,
      lastMessage: existing?.lastMessage,
      unreadCount: existing?.unreadCount ?? 0,
      lastActivity: existing?.lastActivity,
    );
    _conversations[conversationId] = updated;

    await _database.upsertConversation(ConversationsCompanion.insert(
      conversationId: conversationId,
      conversationType: conversationTypeToString(ConversationType.dm),
      otherUserId: Value(otherUser.id),
      otherUsername: Value(otherUser.username),
      otherFullName: Value(otherUser.fullName),
      otherAvatar: Value(otherUser.avatar),
      otherIsOnline: Value(otherUser.isOnline),
      groupId: const Value.absent(),
      groupName: const Value.absent(),
      groupIcon: const Value.absent(),
      groupMemberCount: const Value.absent(),
      lastMessageContent: Value(existing?.lastMessage?.content),
      lastMessageTime: Value(existing?.lastMessage?.createdAt),
      lastMessageCreatedAtUnix: Value(existing?.lastMessage?.createdAtUnix),
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
        final type = conversationTypeFromString(convo.conversationType);
        final conversationId = convo.conversationId;
        final otherUser = (type == ConversationType.dm && convo.otherUserId != null)
            ? User(
                id: convo.otherUserId!,
                username: convo.otherUsername ?? 'User ${convo.otherUserId}',
                email: '',
                fullName: convo.otherFullName ?? 'User ${convo.otherUserId}',
                avatar: convo.otherAvatar,
                isOnline: convo.otherIsOnline,
              )
            : null;
        final group = (type == ConversationType.group && convo.groupId != null)
            ? Group(
                id: convo.groupId!,
                name: convo.groupName ?? 'Group ${convo.groupId}',
                icon: convo.groupIcon ?? '',
                memberCount: convo.groupMemberCount ?? 0,
              )
            : null;

        Message? lastMessage;
        if (convo.lastMessageContent != null && (convo.lastMessageTime != null)) {
          final createdAtUtc = convo.lastMessageTime!.toUtc();
          final createdAtUnix = convo.lastMessageCreatedAtUnix ??
              (createdAtUtc.millisecondsSinceEpoch ~/ 1000);
          lastMessage = Message(
            id: 0,
            clientId: '',
            senderId: otherUser?.id ?? 0,
            sender: null,
            recipientId: type == ConversationType.dm ? _currentUser?.id : null,
            groupId: type == ConversationType.group ? group?.id : null,
            content: convo.lastMessageContent!,
            messageType: 'text',
            status: 'delivered',
            isDelivered: true,
            isRead: true,
            createdAt: createdAtUtc,
            createdAtUnix: createdAtUnix,
          );
        }

        _conversations[conversationId] = Conversation(
          conversationId: conversationId,
          type: type,
          otherUser: otherUser,
          group: group,
          lastMessage: lastMessage,
          unreadCount: convo.unreadCount,
          lastActivity: convo.lastMessageTime,
        );

        final title = type == ConversationType.group
            ? (group?.name ?? 'Group')
            : (otherUser?.fullName.isNotEmpty == true
                ? otherUser!.fullName
                : (otherUser?.username ?? 'User'));
        await NotificationPrefs.setConversationMeta(
          conversationId,
          title: title,
          isGroup: type == ConversationType.group,
        );
        if (lastMessage != null && lastMessage.id > 0) {
          await NotificationPrefs.setCursor(conversationId, lastMessage.id);
        }
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

        final conversationId = item['conversation_id'] as String?;
        if (conversationId == null || conversationId.isEmpty) continue;

        final unreadCount = (item['unread_count'] is int) ? item['unread_count'] as int : 0;
        final lastMessageJson = item['last_message'];
        final lastMessage = (lastMessageJson is Map)
            ? Message.fromJson(Map<String, dynamic>.from(lastMessageJson))
            : null;

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

        ConversationType type;
        User? otherUser;
        Group? group;

        final peerJson = item['peer'];
        if (peerJson is Map) {
          type = ConversationType.dm;
          otherUser = User.fromJson(Map<String, dynamic>.from(peerJson));
        } else {
          type = ConversationType.group;
          final groupJson = item['group'];
          if (groupJson is Map) {
            group = Group.fromJson(Map<String, dynamic>.from(groupJson));
          }
        }

        _conversations[conversationId] = Conversation(
          conversationId: conversationId,
          type: type,
          otherUser: otherUser,
          group: group,
          lastMessage: lastMessage,
          unreadCount: unreadCount,
          lastActivity: lastActivity,
        );

        final title = type == ConversationType.group
            ? (group?.name ?? 'Group')
            : (otherUser?.fullName.isNotEmpty == true
                ? otherUser!.fullName
                : (otherUser?.username ?? 'User'));
        await NotificationPrefs.setConversationMeta(
          conversationId,
          title: title,
          isGroup: type == ConversationType.group,
        );
        if (lastMessage != null && lastMessage.id > 0) {
          await NotificationPrefs.setCursor(conversationId, lastMessage.id);
        }

        await _database.upsertConversation(ConversationsCompanion.insert(
          conversationId: conversationId,
          conversationType: conversationTypeToString(type),
          otherUserId: Value(otherUser?.id),
          otherUsername: Value(otherUser?.username),
          otherFullName: Value(otherUser?.fullName),
          otherAvatar: Value(otherUser?.avatar ?? ''),
          otherIsOnline: Value(otherUser?.isOnline ?? false),
          groupId: Value(group?.id),
          groupName: Value(group?.name),
          groupIcon: Value(group?.icon),
          groupMemberCount: Value(group?.memberCount),
          lastMessageContent: Value(lastMessage?.content),
          lastMessageTime: Value(lastMessage?.createdAt),
          lastMessageCreatedAtUnix: Value(lastMessage?.createdAtUnix),
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

  Future<void> loadMessages(String conversationId, {int limit = 20, bool loadMore = false}) async {
    try {
      // Determine cursor for pagination
      int? cursor;
      if (loadMore) {
        cursor = _messageCursors[conversationId];
        if (cursor == null || !(_hasMoreMessages[conversationId] ?? true)) {
          print('No more messages to load for conversation $conversationId');
          return; // No more messages or already at end
        }
      }

      final parsed = _parseConversationId(conversationId);
      final isGroup = parsed.$1 == 'group';
      final numericId = parsed.$2;

      // First, load from local database
      if (!loadMore) {
        final localMessages = await _database.getMessagesForConversation(
          conversationId,
          _currentUser?.id ?? 0,
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
          _messagesByConversation[conversationId] = msgs;

          // Cursor should point to the oldest server-backed message we have loaded.
          final oldestServerBacked = msgs.lastWhere(
            (m) => m.id > 0,
            orElse: () => msgs.last,
          );
          _messageCursors[conversationId] = oldestServerBacked.id > 0 ? oldestServerBacked.id : null;
          
          notifyListeners();
        }
      }

      // Then fetch from API if online
      if (!_isOnline) return;

      final endpoint = isGroup
          ? (cursor != null
            ? '/groups/$numericId/messages?limit=$limit&cursor=$cursor'
            : '/groups/$numericId/messages?limit=$limit')
          : (cursor != null
            ? '/messages?recipient_id=$numericId&limit=$limit&cursor=$cursor'
            : '/messages?recipient_id=$numericId&limit=$limit');
      
      final response = await _apiService.get(endpoint);
      final messages = (response['messages'] as List)
          .map((json) => Message.fromJson(json))
          .toList();

      // Check if more messages exist (backend returns newest-first)
      final hasMore = messages.length == limit;
      _hasMoreMessages[conversationId] = hasMore;

      if (messages.isNotEmpty) {
        // Backend provides next_cursor (oldest message ID in this page)
        final nextCursor = response['next_cursor'];
        if (nextCursor is int && nextCursor > 0) {
          _messageCursors[conversationId] = nextCursor;
        } else {
          _messageCursors[conversationId] = messages.last.id;
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
          final list = _messagesByConversation.putIfAbsent(conversationId, () => []);
          final existingIds = list.map((m) => m.id).toSet();
          final newMessages = messages.where((m) => !existingIds.contains(m.id)).toList();
          list.addAll(newMessages);
          _sortConversationMessages(list);
        } else {
          // Replace with newest-first list from backend, but preserve any pending
          // optimistic messages already shown.
          final existing = _messagesByConversation[conversationId] ?? const <Message>[];
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
          _messagesByConversation[conversationId] = deduped;
          _updateConversation(conversationId, deduped);

          // If we still only have placeholder peer data, try to hydrate from message senders.
          final conv = _conversations[conversationId];
          if (!isGroup && conv != null && conv.otherUser != null && _isPlaceholderUser(conv.otherUser!)) {
            final peerMsg = messages.cast<Message?>().firstWhere(
                  (m) => m != null && m.senderId == numericId && m.sender != null,
                  orElse: () => null,
                );
            final peer = peerMsg?.sender;
            if (peer != null) {
              await upsertConversationPeer(peer);
            } else {
              await _ensurePeerProfile(numericId);
            }
          }
        }
      } else if (!loadMore) {
        // No messages from API but might have local ones
        _hasMoreMessages[conversationId] = false;
      }

      notifyListeners();
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  /// Called when a conversation screen is opened.
  /// Clears unread count locally immediately and asks the server to mark the DM as read.
  Future<void> openConversation(String conversationId) async {
    // Local: clear unread count for snappy UI.
    final existing = _conversations[conversationId];
    if (existing != null && existing.unreadCount != 0) {
      _conversations[conversationId] = existing.copyWith(unreadCount: 0);
      await _database.clearUnreadCount(conversationId);
      notifyListeners();
    }

    await NotificationService.instance.cancelConversation(conversationId);

    final parsed = _parseConversationId(conversationId);
    final isGroup = parsed.$1 == 'group';
    final numericId = parsed.$2;

    // Server: mark all messages from this peer to me as read.
    // Best-effort; if it fails we'll still have local UI cleared, but on next
    // login the server will re-send unread_count unless this succeeds.
    try {
      if (isGroup) {
        // Use newest known server-backed message as last_read_message_id.
        final list = _messagesByConversation[conversationId] ?? [];
        final newestServer = list.firstWhere((m) => m.id > 0, orElse: () => list.isEmpty ? Message.empty() : list.first);
        final lastReadId = newestServer.id > 0 ? newestServer.id : 0;
        await _apiService.post('/groups/$numericId/read', {
          'last_read_message_id': lastReadId,
        });
        if (lastReadId > 0) {
          _wsService.sendGroupRead(numericId, lastReadId);
        }

        await _refreshGroupMembers(numericId);
        await _refreshGroupReadState(numericId);
      } else {
        await _apiService.post('/conversations/$numericId/read', {});

        _markLocalDmRead(conversationId, numericId);
      }
    } catch (_) {
      // best-effort
    }
  }

  void sendMessage(int recipientId, String content) async {
    // Backward-compatible DM entry point
    await sendDmMessage(recipientId, content);
  }

  Future<void> sendDmMessage(int recipientId, String content) async {
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

    final conversationId = _dmConversationId(recipientId);

    // Add to message list (ChatScreen reverse:true expects newest-first)
    final messageList = _messagesByConversation.putIfAbsent(conversationId, () => []);
    // Deduplicate by client_id
    messageList.removeWhere((m) => m.clientId == clientId);
    // Pending outgoing should appear as the newest message.
    messageList.insert(0, message);
    _sortConversationMessages(messageList);
    _pendingMessages[clientId] = message;

    // Update conversation
    _updateConversationWithMessage(conversationId, message);
    notifyListeners();

    // Always add to offline queue for retry logic
    await _queueService.enqueueMessage(
      clientId: clientId,
      recipientId: recipientId,
      content: content,
      messageType: 'text',
    );
    await _updateQueueCount();

    // Best-effort immediate send (queue will retry if this fails).
    if (_isOnline) {
      try {
        await _sendQueuedMessage(
          clientId: clientId,
          recipientId: recipientId,
          content: content,
          messageType: 'text',
        );
      } catch (_) {
        // Ignore: queued retry will handle it.
      }
    }
  }

  Future<void> sendGroupMessage(int groupId, String content) async {
    if (_currentUser == null) return;

    final clientId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final nowUnix = now.millisecondsSinceEpoch ~/ 1000;
    final conversationId = _groupConversationId(groupId);

    final message = Message(
      id: 0,
      clientId: clientId,
      senderId: _currentUser!.id,
      sender: _currentUser,
      recipientId: null,
      groupId: groupId,
      content: content,
      messageType: 'text',
      status: 'pending',
      isDelivered: false,
      isRead: false,
      createdAt: now,
      createdAtUnix: nowUnix,
    );

    await _database.insertMessage(MessagesCompanion.insert(
      clientId: clientId,
      senderId: _currentUser!.id,
      recipientId: const Value.absent(),
      groupId: Value(groupId),
      content: content,
      messageType: const Value('text'),
      status: const Value('pending'),
      createdAt: now,
      createdAtUnix: Value(nowUnix),
      updatedAt: now,
      isSentByMe: true,
    ));

    final messageList = _messagesByConversation.putIfAbsent(conversationId, () => []);
    messageList.removeWhere((m) => m.clientId == clientId);
    messageList.insert(0, message);
    _sortConversationMessages(messageList);
    _pendingMessages[clientId] = message;

    _updateConversationWithMessage(conversationId, message);
    notifyListeners();

    await _queueService.enqueueMessage(
      clientId: clientId,
      groupId: groupId,
      content: content,
      messageType: 'text',
    );
    await _updateQueueCount();

    if (_isOnline) {
      try {
        await _sendQueuedMessage(
          clientId: clientId,
          groupId: groupId,
          content: content,
          messageType: 'text',
        );
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
      case 'group_read_update':
        _handleGroupReadUpdate(data);
        break;
      case 'read_update':
        _handleReadUpdate(data);
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
      final conversationId = pendingMessage.groupId != null
          ? _groupConversationId(pendingMessage.groupId!)
          : _dmConversationId(pendingMessage.recipientId!);
      final messages = _messagesByConversation[conversationId];
      if (messages != null) {
        final index = messages.indexWhere((m) => m.clientId == clientId);
        if (index != -1) {
          messages[index] = updatedMessage;
          _sortConversationMessages(messages);
        }
      }

      if (serverId > 0) {
        await NotificationPrefs.setCursor(conversationId, serverId);
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
    final isGroup = message.groupId != null;
    final conversationId = isGroup
        ? _groupConversationId(message.groupId!)
        : _dmConversationId(message.senderId);

    // Persist peer profile ASAP to avoid placeholders (DM + sender profile cache for groups).
    if (message.sender != null) {
      await upsertConversationPeer(message.sender!);
    } else if (!isGroup) {
      await _ensurePeerProfile(message.senderId);
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
    if (isGroup) {
      final existing = _conversations[conversationId];
      final group = existing?.group ?? Group(id: message.groupId!, name: 'Group ${message.groupId}', icon: '', memberCount: 0);
      await _database.upsertConversation(ConversationsCompanion.insert(
        conversationId: conversationId,
        conversationType: conversationTypeToString(ConversationType.group),
        otherUserId: const Value.absent(),
        otherUsername: const Value.absent(),
        otherFullName: const Value.absent(),
        otherAvatar: const Value(''),
        otherIsOnline: const Value(false),
        groupId: Value(group.id),
        groupName: Value(group.name),
        groupIcon: Value(group.icon),
        groupMemberCount: Value(group.memberCount),
        lastMessageContent: Value(message.content),
        lastMessageTime: Value(message.createdAt),
        lastMessageCreatedAtUnix: Value(message.createdAtUnix),
        updatedAt: message.createdAt,
      ));
    } else {
      final otherUserId = message.senderId;
      await _database.upsertConversation(ConversationsCompanion.insert(
        conversationId: conversationId,
        conversationType: conversationTypeToString(ConversationType.dm),
        otherUserId: Value(otherUserId),
        otherUsername: Value(message.sender?.username ?? 'User $otherUserId'),
        otherFullName: Value(message.sender?.fullName ?? 'User $otherUserId'),
        otherAvatar: Value(message.sender?.avatar ?? ''),
        otherIsOnline: Value(message.sender?.isOnline ?? false),
        groupId: const Value.absent(),
        groupName: const Value.absent(),
        groupIcon: const Value.absent(),
        groupMemberCount: const Value.absent(),
        lastMessageContent: Value(message.content),
        lastMessageTime: Value(message.createdAt),
        lastMessageCreatedAtUnix: Value(message.createdAtUnix),
        updatedAt: message.createdAt,
      ));
    }

    // Add to message list (keep newest-first)
    final list = _messagesByConversation.putIfAbsent(conversationId, () => []);
    // Remove duplicate if exists
    list.removeWhere((m) => m.id == message.id || (m.clientId != null && m.clientId == message.clientId));
    list.add(message);
    _sortConversationMessages(list);
    _updateConversationWithMessage(conversationId, message);
    notifyListeners();

    if (message.id > 0) {
      await NotificationPrefs.setCursor(conversationId, message.id);
    }

    if (_activeConversationId == conversationId) {
      if (isGroup && message.groupId != null && message.id > 0) {
        _wsService.sendGroupRead(message.groupId!, message.id);
        final uid = _currentUser?.id;
        if (uid != null) {
          await _database.upsertGroupReadState(message.groupId!, uid, message.id);
          final groupMap = _groupReadStates.putIfAbsent(message.groupId!, () => {});
          final current = groupMap[uid] ?? 0;
          if (message.id > current) {
            groupMap[uid] = message.id;
          }
        }
      } else if (!isGroup && message.id > 0) {
        _wsService.sendRead(message.id);
      }
    }

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

  void _handleGroupReadUpdate(Map<String, dynamic> data) async {
    final groupId = data['group_id'] as int?;
    final userId = data['user_id'] as int?;
    final lastRead = data['last_read_message_id'] as int?;
    if (groupId == null || userId == null || lastRead == null) return;

    await _database.upsertGroupReadState(groupId, userId, lastRead);
    final groupMap = _groupReadStates.putIfAbsent(groupId, () => {});
    final current = groupMap[userId] ?? 0;
    if (lastRead > current) {
      groupMap[userId] = lastRead;
    }
    notifyListeners();
  }

  void _handleReadUpdate(Map<String, dynamic> data) async {
    final readerId = data['user_id'] as int?;
    final lastRead = data['last_read_message_id'] as int?;
    final conversationId = data['conversation_id'] as String?;
    if (readerId == null || lastRead == null || conversationId == null) return;

    final currentUserId = _currentUser?.id;
    if (currentUserId == null) return;

    final list = _messagesByConversation[conversationId];
    if (list != null) {
      bool changed = false;
      for (var i = 0; i < list.length; i++) {
        final m = list[i];
        if (m.senderId == currentUserId &&
            m.recipientId == readerId &&
            m.id > 0 &&
            m.id <= lastRead &&
            !m.isRead) {
          list[i] = Message(
            id: m.id,
            clientId: m.clientId,
            senderId: m.senderId,
            sender: m.sender,
            recipientId: m.recipientId,
            groupId: m.groupId,
            content: m.content,
            messageType: m.messageType,
            status: 'read',
            isDelivered: true,
            isRead: true,
            createdAt: m.createdAt,
            createdAtUnix: m.createdAtUnix,
          );
          changed = true;
        }
      }
      if (changed) {
        _sortConversationMessages(list);
      }
    }

    await _database.markDmMessagesRead(currentUserId, readerId, lastRead);

    final conv = _conversations[conversationId];
    if (conv?.lastMessage != null &&
        conv!.lastMessage!.senderId == currentUserId &&
        conv.lastMessage!.id <= lastRead &&
        !conv.lastMessage!.isRead) {
      final m = conv.lastMessage!;
      _conversations[conversationId] = conv.copyWith(
        lastMessage: Message(
          id: m.id,
          clientId: m.clientId,
          senderId: m.senderId,
          sender: m.sender,
          recipientId: m.recipientId,
          groupId: m.groupId,
          content: m.content,
          messageType: m.messageType,
          status: 'read',
          isDelivered: true,
          isRead: true,
          createdAt: m.createdAt,
          createdAtUnix: m.createdAtUnix,
        ),
      );
    }

    notifyListeners();
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

  Future<void> _refreshGroupMembers(int groupId) async {
    try {
      final response = await _apiService.get('/groups/$groupId/members');
      final list = response is List
          ? response
          : (response is Map ? (response['members'] as List? ?? []) : []);

      final members = <int, User>{};
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final user = User.fromJson(item);
          members[user.id] = user;
        }
      }

      if (members.isNotEmpty) {
        _groupMembers[groupId] = members;
        final conversationId = _groupConversationId(groupId);
        final conv = _conversations[conversationId];
        if (conv?.group != null) {
          final g = conv!.group!;
          _conversations[conversationId] = conv.copyWith(
            group: Group(
              id: g.id,
              name: g.name,
              icon: g.icon,
              memberCount: members.length,
            ),
          );
        }
      }
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _refreshGroupReadState(int groupId) async {
    try {
      final response = await _apiService.get('/groups/$groupId/read-state');
      if (response is! Map) return;
      final members = (response['members'] as List?) ?? [];

      final groupMap = _groupReadStates.putIfAbsent(groupId, () => {});
      for (final item in members) {
        if (item is Map<String, dynamic>) {
          final userId = item['user_id'] as int?;
          final lastRead = item['last_read_message_id'] as int? ?? 0;
          if (userId != null) {
            final existing = groupMap[userId] ?? 0;
            if (lastRead > existing) {
              groupMap[userId] = lastRead;
            }
            await _database.upsertGroupReadState(groupId, userId, lastRead);
          }
        }
      }
    } catch (_) {
      // best-effort
    }
  }

  void _markLocalDmRead(String conversationId, int peerId) async {
    final currentUserId = _currentUser?.id;
    if (currentUserId == null) return;
    final list = _messagesByConversation[conversationId];
    if (list == null || list.isEmpty) return;

    final newestServer = list.firstWhere((m) => m.id > 0, orElse: () => list.first);
    final lastReadId = newestServer.id > 0 ? newestServer.id : 0;
    if (lastReadId == 0) return;

    bool changed = false;
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      if (m.senderId == peerId &&
          m.recipientId == currentUserId &&
          m.id > 0 &&
          m.id <= lastReadId &&
          !m.isRead) {
        list[i] = Message(
          id: m.id,
          clientId: m.clientId,
          senderId: m.senderId,
          sender: m.sender,
          recipientId: m.recipientId,
          groupId: m.groupId,
          content: m.content,
          messageType: m.messageType,
          status: 'read',
          isDelivered: true,
          isRead: true,
          createdAt: m.createdAt,
          createdAtUnix: m.createdAtUnix,
        );
        changed = true;
      }
    }

    if (changed) {
      _sortConversationMessages(list);
      notifyListeners();
    }

    await _database.markIncomingDmMessagesRead(peerId, currentUserId, lastReadId);
  }

  void _updateConversation(String conversationId, List<Message> messages) {
    if (messages.isEmpty) return;

    final lastMessage = messages.first;
    final existingConv = _conversations[conversationId];
    final parsed = _parseConversationId(conversationId);
    final isGroup = parsed.$1 == 'group';
    final numericId = parsed.$2;

    final conversation = Conversation(
      conversationId: conversationId,
      type: isGroup ? ConversationType.group : ConversationType.dm,
      otherUser: isGroup
          ? null
          : (existingConv?.otherUser ??
              User(
                id: numericId,
                username: 'User $numericId',
                email: '',
                fullName: 'User $numericId',
                avatar: '',
                isOnline: false,
              )),
      group: isGroup
          ? (existingConv?.group ??
              Group(
                id: numericId,
                name: 'Group $numericId',
                icon: '',
                memberCount: 0,
              ))
          : null,
      lastMessage: lastMessage,
      unreadCount: existingConv?.unreadCount ?? 0,
      lastActivity: lastMessage.createdAt,
    );

    _conversations[conversationId] = conversation;
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

      final byUnix = b.createdAtUnix.compareTo(a.createdAtUnix);
      if (byUnix != 0) return byUnix;
      final byId = b.id.compareTo(a.id);
      if (byId != 0) return byId;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  void _updateConversationWithMessage(String conversationId, Message message) async {
    final existingConv = _conversations[conversationId];
    final parsed = _parseConversationId(conversationId);
    final isGroup = parsed.$1 == 'group';
    final numericId = parsed.$2;

    final shouldIncrementUnread = message.senderId != _currentUser?.id &&
      _activeConversationId != conversationId;
    final unreadCount = shouldIncrementUnread
      ? (existingConv?.unreadCount ?? 0) + 1
      : 0;

    final conversation = Conversation(
      conversationId: conversationId,
      type: isGroup ? ConversationType.group : ConversationType.dm,
      otherUser: isGroup
          ? null
          : (existingConv?.otherUser ??
              User(
                id: numericId,
                username: 'User $numericId',
                email: '',
                fullName: 'User $numericId',
                avatar: '',
                isOnline: false,
              )),
      group: isGroup
          ? (existingConv?.group ??
              Group(
                id: numericId,
                name: 'Group $numericId',
                icon: '',
                memberCount: 0,
              ))
          : null,
      lastMessage: message,
      unreadCount: unreadCount,
      lastActivity: message.createdAt,
    );

    _conversations[conversationId] = conversation;

    await _database.upsertConversation(ConversationsCompanion.insert(
      conversationId: conversationId,
      conversationType: conversationTypeToString(conversation.type),
      otherUserId: Value(conversation.otherUser?.id),
      otherUsername: Value(conversation.otherUser?.username),
      otherFullName: Value(conversation.otherUser?.fullName),
      otherAvatar: Value(conversation.otherUser?.avatar ?? ''),
      otherIsOnline: Value(conversation.otherUser?.isOnline ?? false),
      groupId: Value(conversation.group?.id),
      groupName: Value(conversation.group?.name),
      groupIcon: Value(conversation.group?.icon),
      groupMemberCount: Value(conversation.group?.memberCount),
      lastMessageContent: Value(message.content),
      lastMessageTime: Value(message.createdAt),
      lastMessageCreatedAtUnix: Value(message.createdAtUnix),
      unreadCount: Value(unreadCount),
      updatedAt: message.createdAt,
    ));

    final title = conversation.type == ConversationType.group
        ? (conversation.group?.name ?? 'Group')
        : (conversation.otherUser?.fullName.isNotEmpty == true
            ? conversation.otherUser!.fullName
            : (conversation.otherUser?.username ?? 'User'));
    await NotificationPrefs.setConversationMeta(
      conversationId,
      title: title,
      isGroup: conversation.type == ConversationType.group,
    );
    if (message.id > 0) {
      await NotificationPrefs.setCursor(conversationId, message.id);
    }
  }

  void sendTypingIndicator(int recipientId, bool isTyping) {
    _wsService.sendTyping(recipientId, isTyping);
  }

  void markAsRead(int messageId) {
    _wsService.sendRead(messageId);
  }

  Future<void> setConversationMuted(String conversationId, bool muted) async {
    await NotificationPrefs.setMuted(conversationId, muted);
    if (muted) {
      await NotificationService.instance.cancelConversation(conversationId);
    }
    notifyListeners();
  }

  Future<bool> isConversationMuted(String conversationId) {
    return NotificationPrefs.isMuted(conversationId);
  }

  Future<void> _sendQueuedMessage({
    required String clientId,
    int? recipientId,
    int? groupId,
    required String content,
    required String messageType,
  }) async {
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

    if (groupId != null) {
      _wsService.sendGroupChatMessage(
        clientId: clientId,
        groupId: groupId,
        content: content,
        messageType: messageType,
      );
      return;
    }
    if (recipientId == null) {
      throw Exception('missing_recipient');
    }

    _wsService.sendChatMessage(
      clientId: clientId,
      recipientId: recipientId,
      content: content,
      messageType: messageType,
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
