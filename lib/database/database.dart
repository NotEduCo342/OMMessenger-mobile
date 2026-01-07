import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Messages, PendingMessages, Conversations, SyncState])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Future migrations will go here
      },
    );
  }

  // ==================== Message Operations ====================

  /// Insert or replace message (handles duplicates)
  Future<int> insertMessage(MessagesCompanion message) {
    return into(messages).insert(
      message,
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Get messages for a conversation
  Future<List<Message>> getMessagesForUser(int userId, {int limit = 50}) {
    return (select(messages)
          ..where((m) =>
              (m.recipientId.equals(userId) & m.isSentByMe.equals(true)) |
              (m.senderId.equals(userId) & m.isSentByMe.equals(false)))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Get messages after a cursor (for pagination)
  Future<List<Message>> getMessagesAfterCursor(
    int userId,
    int cursorId, {
    int limit = 50,
  }) {
    return (select(messages)
          ..where((m) =>
              ((m.recipientId.equals(userId) & m.isSentByMe.equals(true)) |
                  (m.senderId.equals(userId) & m.isSentByMe.equals(false))) &
              m.id.isSmallerThanValue(cursorId))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Update message with server ID after ACK
  Future<bool> updateMessageWithServerId(String clientId, int serverId, String status) {
    return (update(messages)..where((m) => m.clientId.equals(clientId))).write(
      MessagesCompanion(
        serverId: Value(serverId),
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    ).then((rows) => rows > 0);
  }

  /// Update message status
  Future<bool> updateMessageStatus(String clientId, String status, {bool? isDelivered, bool? isRead}) {
    return (update(messages)..where((m) => m.clientId.equals(clientId))).write(
      MessagesCompanion(
        status: Value(status),
        isDelivered: Value(isDelivered ?? false),
        isRead: Value(isRead ?? false),
        updatedAt: Value(DateTime.now()),
      ),
    ).then((rows) => rows > 0);
  }

  /// Get message by client ID
  Future<Message?> getMessageByClientId(String clientId) {
    return (select(messages)..where((m) => m.clientId.equals(clientId))).getSingleOrNull();
  }

  /// Delete old messages (keep last 1000 per conversation)
  Future<int> deleteOldMessages(int userId, int keepCount) async {
    final messagesToKeep = await (select(messages)
          ..where((m) =>
              (m.recipientId.equals(userId) & m.isSentByMe.equals(true)) |
              (m.senderId.equals(userId) & m.isSentByMe.equals(false)))
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(keepCount))
        .get();

    if (messagesToKeep.isEmpty) return 0;

    final oldestKeptId = messagesToKeep.last.id;
    return (delete(messages)
          ..where((m) =>
              ((m.recipientId.equals(userId) & m.isSentByMe.equals(true)) |
                  (m.senderId.equals(userId) & m.isSentByMe.equals(false))) &
              m.id.isSmallerThanValue(oldestKeptId)))
        .go();
  }

  // ==================== Pending Message Operations ====================

  /// Insert pending message to queue
  Future<int> insertPendingMessage(PendingMessagesCompanion message) {
    return into(pendingMessages).insert(message);
  }

  /// Get all pending messages ready for retry
  Future<List<PendingMessage>> getPendingMessagesForRetry() {
    return (select(pendingMessages)
          ..where((m) => m.nextRetryAt.isSmallerOrEqualValue(DateTime.now()))
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .get();
  }

  /// Get pending messages count
  Future<int> getPendingMessagesCount() async {
    final count = countAll();
    final query = selectOnly(pendingMessages)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Update pending message retry info
  Future<bool> updatePendingMessageRetry(String clientId, int retryCount, DateTime nextRetryAt, String? error) {
    return (update(pendingMessages)..where((m) => m.clientId.equals(clientId))).write(
      PendingMessagesCompanion(
        retryCount: Value(retryCount),
        nextRetryAt: Value(nextRetryAt),
        error: Value(error),
      ),
    ).then((rows) => rows > 0);
  }

  /// Delete pending message after successful send
  Future<int> deletePendingMessage(String clientId) async {
    return await (delete(pendingMessages)..where((m) => m.clientId.equals(clientId))).go();
  }

  /// Clear all pending messages (cleanup)
  Future<int> clearPendingMessages() {
    return delete(pendingMessages).go();
  }

  // ==================== Conversation Operations ====================

  /// Insert or update conversation
  Future<void> upsertConversation(ConversationsCompanion conversation) async {
    await into(conversations).insertOnConflictUpdate(conversation);
  }

  /// Get all conversations ordered by last message time
  Future<List<Conversation>> getAllConversations() {
    return (select(conversations)
          ..orderBy([(c) => OrderingTerm.desc(c.lastMessageTime)]))
        .get();
  }

  /// Get conversation by user ID
  Future<Conversation?> getConversation(int userId) {
    return (select(conversations)..where((c) => c.otherUserId.equals(userId))).getSingleOrNull();
  }

  /// Update conversation unread count
  Future<bool> updateConversationUnreadCount(int userId, int count) {
    return (update(conversations)..where((c) => c.otherUserId.equals(userId))).write(
      ConversationsCompanion(
        unreadCount: Value(count),
        updatedAt: Value(DateTime.now()),
      ),
    ).then((rows) => rows > 0);
  }

  /// Clear unread count for conversation
  Future<bool> clearUnreadCount(int userId) {
    return updateConversationUnreadCount(userId, 0);
  }

  /// Delete conversation
  Future<int> deleteConversation(int userId) {
    return (delete(conversations)..where((c) => c.otherUserId.equals(userId))).go();
  }

  // ==================== Sync State Operations ====================

  /// Get sync state for user
  Future<SyncStateData?> getSyncState(int userId) {
    return (select(syncState)..where((s) => s.userId.equals(userId))).getSingleOrNull();
  }

  /// Update sync state
  Future<void> updateSyncState(int userId, int lastMessageId) async {
    await into(syncState).insertOnConflictUpdate(
      SyncStateCompanion(
        userId: Value(userId),
        lastMessageId: Value(lastMessageId),
        lastSyncAt: Value(DateTime.now()),
      ),
    );
  }

  // ==================== Utility Operations ====================

  /// Clear all data (logout)
  Future<void> clearAllData() async {
    await delete(messages).go();
    await delete(pendingMessages).go();
    await delete(conversations).go();
    await delete(syncState).go();
  }

  /// Get database size in bytes
  Future<int> getDatabaseSize() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dbFolder.path, 'om_messenger.db'));
    if (await dbFile.exists()) {
      return await dbFile.length();
    }
    return 0;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'om_messenger.db'));
    return NativeDatabase.createInBackground(file, logStatements: false);
  });
}
