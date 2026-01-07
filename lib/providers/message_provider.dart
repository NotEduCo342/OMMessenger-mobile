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
  bool get isOnline => _isOnline;
  int get pendingQueueCount => _pendingQueueCount;
  int? get currentUserId => _currentUser?.id;
  bool hasMoreMessages(int userId) => _hasMoreMessages[userId] ?? true;

  List<Message> getMessages(int userId) {
    return _messagesByUser[userId] ?? [];
  }

  bool isTyping(int userId) => _typingUsers[userId] ?? false;

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

    // Connect WebSocket
    await _wsService.connect();

    // Listen to WebSocket messages
    _wsService.messageStream.listen(_handleWebSocketMessage);

    // Load conversations from database
    await _loadConversations();

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
              ? Message(
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
                  createdAt: convo.lastMessageTime ?? DateTime.now(),
                )
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
      // TODO: Add API endpoint for conversation list
      // For now, just reload from database
      await _loadConversations();
    } catch (e) {
      print('Error refreshing conversations: $e');
      rethrow;
    }
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
          _messagesByUser[userId] = localMessages
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
                    createdAt: dbMsg.createdAt,
                  ))
              .toList(); // Chronological order
          
          // Set initial cursor to oldest message ID
          if (localMessages.isNotEmpty) {
            _messageCursors[userId] = localMessages.last.serverId;
          }
          
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

      // Check if more messages exist
      final hasMore = messages.length == limit;
      _hasMoreMessages[userId] = hasMore;

      if (messages.isNotEmpty) {
        // Update cursor to last message ID
        _messageCursors[userId] = messages.last.id;

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
            updatedAt: msg.createdAt,
            isSentByMe: msg.senderId == _currentUser?.id,
          ));
        }

        if (loadMore) {
          // Append to existing messages, avoid duplicates
          final existingIds = _messagesByUser[userId]!.map((m) => m.clientId).toSet();
          final newMessages = messages.where((m) => !existingIds.contains(m.clientId ?? '')).toList();
          _messagesByUser[userId]!.addAll(newMessages);
        } else {
          // Replace all messages
          _messagesByUser[userId] = messages;
          _updateConversation(userId, messages);
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

  void sendMessage(int recipientId, String content) async {
    if (_currentUser == null) return;

    final clientId = _uuid.v4();
    final now = DateTime.now();

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
      updatedAt: now,
      isSentByMe: true,
    ));

    // Keep newest-first ordering in memory
    final messageList = _messagesByUser.putIfAbsent(recipientId, () => []);
    // Deduplicate by client_id
    messageList.removeWhere((m) => m.clientId == clientId);
    messageList.insert(0, message);
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

    // Send via WebSocket if online
    if (_isOnline && _wsService.status == ConnectionStatus.connected) {
      _wsService.sendChatMessage(
        clientId: clientId,
        recipientId: recipientId,
        content: content,
      );
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

    if (clientId == null || serverId == null) {
      return;
    }

    // Always update database first
    try {
      await _database.updateMessageWithServerId(clientId, serverId, status ?? 'sent');
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
        createdAt: pendingMessage.createdAt,
      );

      // Replace in message list
      final userId = pendingMessage.recipientId!;
      final messages = _messagesByUser[userId];
      if (messages != null) {
        final index = messages.indexWhere((m) => m.clientId == clientId);
        if (index != -1) {
          messages[index] = updatedMessage;
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
      updatedAt: message.createdAt,
      isSentByMe: false,
    ));

    // Update conversation in database
    await _database.upsertConversation(ConversationsCompanion.insert(
      otherUserId: otherUserId,
      otherUsername: message.sender?.username ?? 'User $otherUserId',
      otherFullName: message.sender?.fullName ?? 'User $otherUserId',
      otherAvatar: const Value(''),
      otherIsOnline: const Value(false),
      lastMessageContent: Value(message.content),
      lastMessageTime: Value(message.createdAt),
      updatedAt: message.createdAt,
    ));

    // Keep newest-first ordering in memory
    final list = _messagesByUser.putIfAbsent(otherUserId, () => []);
    list.insert(0, message);
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
      otherUserId: userId,
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
      return;
    }

    // Ensure WebSocket is connected
    if (_wsService.status != ConnectionStatus.connected) {
      await _wsService.connect();
      
      // Give it a moment to connect
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (_wsService.status != ConnectionStatus.connected) {
        return;
      }
    }

    _wsService.sendChatMessage(
      clientId: clientId,
      recipientId: recipientId,
      content: content,
    );
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
