import 'dart:async';
import 'package:drift/drift.dart' as drift;
import '../database/database.dart';
import 'connectivity_service.dart';

class OfflineQueueService {
  final AppDatabase _db;
  final ConnectivityService _connectivityService;
  final Function(String clientId, int recipientId, String content) onMessageReady;
  
  Timer? _retryTimer;
  bool _isProcessing = false;
  bool _isOnline = false;

  OfflineQueueService({
    required AppDatabase database,
    required ConnectivityService connectivityService,
    required this.onMessageReady,
  })  : _db = database,
        _connectivityService = connectivityService {
    start();
  }

  /// Start the queue processor
  void start() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isOnline && !_isProcessing) {
        _processQueue();
      }
    });
  }

  /// Stop the queue processor
  void stop() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Set online/offline state
  void setOnline(bool isOnline) {
    _isOnline = isOnline;
    if (isOnline && !_isProcessing) {
      // Immediately process queue when coming online
      _processQueue();
    }
  }

  /// Add message to offline queue
  Future<void> enqueueMessage({
    required String clientId,
    required int recipientId,
    required String content,
    String messageType = 'text',
  }) async {
    await _db.insertPendingMessage(
      PendingMessagesCompanion(
        clientId: drift.Value(clientId),
        recipientId: drift.Value(recipientId),
        content: drift.Value(content),
        messageType: drift.Value(messageType),
        retryCount: const drift.Value(0),
        nextRetryAt: drift.Value(DateTime.now()),
        createdAt: drift.Value(DateTime.now()),
      ),
    );
  }

  /// Process pending messages queue
  Future<void> _processQueue() async {
    if (_isProcessing || !_isOnline) return;

    _isProcessing = true;

    try {
      final pendingMessages = await _db.getPendingMessagesForRetry();

      for (final message in pendingMessages) {
        if (!_isOnline) break; // Stop if went offline

        try {
          // Callback to send message via WebSocket
          onMessageReady(message.clientId, message.recipientId ?? 0, message.content);

          // Don't delete yet - wait for ACK
          // Will be deleted in message provider after successful ACK
        } catch (e) {
          // Update retry info
          await _handleRetryFailure(message, e.toString());
        }

        // Adaptive delay based on network type
        final delay = _getDelayForNetworkType();
        await Future.delayed(delay);
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Handle message send failure - update retry schedule
  Future<void> _handleRetryFailure(PendingMessage message, String error) async {
    final newRetryCount = message.retryCount + 1;
    
    // Adaptive exponential backoff based on network type
    final baseDelay = _getBaseRetryDelay();
    final delaySeconds = (baseDelay * (1 << (newRetryCount - 1))).clamp(baseDelay, 60);
    final nextRetryAt = DateTime.now().add(Duration(seconds: delaySeconds));

    if (newRetryCount >= 5) {
      // Max retries reached - mark as failed but keep in queue
      // User can manually retry or it will retry after 1 hour
      final nextRetry = DateTime.now().add(const Duration(hours: 1));
      await _db.updatePendingMessageRetry(
        message.clientId,
        newRetryCount,
        nextRetry,
        'Max retries reached: $error',
      );
    } else {
      // Schedule next retry
      await _db.updatePendingMessageRetry(
        message.clientId,
        newRetryCount,
        nextRetryAt,
        error,
      );
    }
  }

  /// Get delay between messages based on network type
  Duration _getDelayForNetworkType() {
    final networkType = _connectivityService.currentType;
    
    switch (networkType) {
      case NetworkType.wifi:
      case NetworkType.ethernet:
        return const Duration(milliseconds: 50);
      case NetworkType.mobile4G:
        return const Duration(milliseconds: 100);
      case NetworkType.mobile3G:
        return const Duration(milliseconds: 300);
      case NetworkType.mobile2G:
        return const Duration(milliseconds: 500);
      case NetworkType.vpn:
        return const Duration(milliseconds: 150);
      default:
        return const Duration(milliseconds: 200);
    }
  }

  /// Get base retry delay based on network type
  int _getBaseRetryDelay() {
    final networkType = _connectivityService.currentType;
    
    switch (networkType) {
      case NetworkType.wifi:
      case NetworkType.ethernet:
        return 2; // 2s, 4s, 8s, 16s, 32s
      case NetworkType.mobile4G:
        return 3; // 3s, 6s, 12s, 24s, 48s
      case NetworkType.mobile3G:
        return 5; // 5s, 10s, 20s, 40s, 60s
      case NetworkType.mobile2G:
        return 10; // 10s, 20s, 40s, 60s, 60s
      case NetworkType.vpn:
        return 4; // 4s, 8s, 16s, 32s, 60s
      default:
        return 2;
    }
  }

  /// Mark message as successfully sent (call after ACK received)
  Future<void> markMessageSent(String clientId) async {
    await _db.deletePendingMessage(clientId);
  }

  /// Retry failed message immediately
  Future<void> retryMessage(String clientId) async {
    await _db.updatePendingMessageRetry(
      clientId,
      0, // Reset retry count
      DateTime.now(),
      null,
    );
    
    if (_isOnline) {
      _processQueue();
    }
  }

  /// Retry all failed messages
  Future<void> retryAllMessages() async {
    final pending = await _db.getPendingMessagesForRetry();
    for (final msg in pending) {
      await _db.updatePendingMessageRetry(
        msg.clientId,
        0,
        DateTime.now(),
        null,
      );
    }
    
    if (_isOnline) {
      _processQueue();
    }
  }

  /// Get count of pending messages
  Future<int> getPendingCount() async {
    return await _db.getPendingMessagesCount();
  }

  /// Clear all pending messages (use with caution)
  Future<void> clearQueue() async {
    await _db.clearPendingMessages();
  }

  void dispose() {
    stop();
  }
}
