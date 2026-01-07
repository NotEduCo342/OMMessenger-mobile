import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WebSocketService {
  WebSocketChannel? _channel;
  final _storage = const FlutterSecureStorage();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;
  static const int _compressionThreshold = 512; // Compress messages > 512 bytes
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus get status => _status;

  Future<void> connect() async {
    if (_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) {
      return;
    }

    _updateStatus(ConnectionStatus.connecting);

    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) {
        throw Exception('No access token found');
      }

      // Pass token as query parameter for WebSocket auth
      final uri = Uri.parse('${AppConstants.wsUrl}?token=$token&gzip=1');
      
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;
      
      _updateStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;

      // Start ping timer
      _startPingTimer();

      // Listen to messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
    } catch (e) {
      _updateStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic data) {
    try {
      String jsonString;
      
      // Handle compressed messages (sent as binary)
      if (data is List<int>) {
        final decompressed = gzip.decode(data);
        jsonString = utf8.decode(decompressed);
      } else {
        jsonString = data as String;
      }
      
      final message = jsonDecode(jsonString);
      _messageController.add(message as Map<String, dynamic>);
    } catch (e) {
      print('Error parsing message: $e');
    }
  }

  void _handleError(error) {
    print('WebSocket error: $error');
    _scheduleReconnect();
  }

  void _handleDisconnect() {
    print('WebSocket disconnected');
    _updateStatus(ConnectionStatus.disconnected);
    _pingTimer?.cancel();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached');
      return;
    }

    _updateStatus(ConnectionStatus.reconnecting);
    
    final delay = Duration(seconds: 2 * (_reconnectAttempts + 1));
    _reconnectAttempts++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      print('Reconnecting... (attempt $_reconnectAttempts)');
      connect();
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_status == ConnectionStatus.connected) {
        send({'type': 'ping'});
      }
    });
  }

  void send(Map<String, dynamic> message) {
    if (_status != ConnectionStatus.connected) {
      print('Cannot send message: not connected');
      return;
    }

    try {
      // Backend expects wrapped format: {"type": "...", "payload": {...}}
      final messageType = message['type'] as String;
      final payload = Map<String, dynamic>.from(message)..remove('type');
      
      final wrappedMessage = {
        'type': messageType,
        'payload': payload,
      };
      
      final jsonString = jsonEncode(wrappedMessage);
      
      // Auto-compress large messages and send as binary frame
      if (jsonString.length > _compressionThreshold) {
        final bytes = utf8.encode(jsonString);
        final compressed = gzip.encode(bytes);
        
        // Only use compression if it actually reduces size
        if (compressed.length < bytes.length) {
          // Send as binary message for backend to detect
          _channel?.sink.add(compressed);
          return;
        }
      }
      
      // Send as text message
      _channel?.sink.add(jsonString);
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  void sendChatMessage({
    required String clientId,
    required int recipientId,
    required String content,
    String messageType = 'text',
  }) {
    send({
      'type': 'chat',
      'client_id': clientId,
      'recipient_id': recipientId,
      'content': content,
      'message_type': messageType,
    });
  }

  void sendTyping(int recipientId, bool isTyping) {
    send({
      'type': 'typing',
      'recipient_id': recipientId,
      'is_typing': isTyping,
    });
  }

  void sendRead(int messageId) {
    send({
      'type': 'read',
      'message_id': messageId,
    });
  }

  void sendSync(List<Map<String, dynamic>> conversations) {
    send({
      'type': 'sync',
      'conversations': conversations,
    });
  }

  void _updateStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void disconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _updateStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
  }
}
