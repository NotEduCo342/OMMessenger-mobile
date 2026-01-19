import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Messages, PendingMessages, Conversations, GroupReadStates, SyncState])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(messages, messages.createdAtUnix);
          // Backfill from existing created_at (stored as unix milliseconds in sqlite).
          await customStatement(
            'UPDATE messages SET created_at_unix = created_at / 1000 '
            'WHERE created_at_unix IS NULL AND created_at IS NOT NULL;',
          );
        }

        if (from < 3) {
          // Conversations is a cache table; schema changed to use otherUserId as PK.
          await customStatement('DROP TABLE IF EXISTS conversations;');
          await m.createTable(conversations);
        }

        if (from < 4) {
          // Conversations is a cache table; safe to drop/recreate with unified schema.
          await customStatement('DROP TABLE IF EXISTS conversations;');
          await m.createTable(conversations);
          await m.createTable(groupReadStates);
        }
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

  (String kind, int id) _parseConversationId(String conversationId) {
    final trimmed = conversationId.trim();
    if (trimmed.startsWith('user_')) {
      return ('user', int.parse(trimmed.substring(5)));
    }
    if (trimmed.startsWith('group_')) {
      return ('group', int.parse(trimmed.substring(6)));
    }
    throw ArgumentError('Invalid conversationId: $conversationId');
  }

  /// Get messages for a conversation
  Future<List<Message>> getMessagesForConversation(
    String conversationId,
    int currentUserId, {
    int limit = 50,
  }) {
    final parsed = _parseConversationId(conversationId);
    if (parsed.$1 == 'group') {
      final groupId = parsed.$2;
      return (select(messages)
            ..where((m) => m.groupId.equals(groupId))
            ..orderBy([
              (m) => OrderingTerm.desc(m.createdAtUnix),
              (m) => OrderingTerm.desc(m.serverId),
              (m) => OrderingTerm.desc(m.id),
            ])
            ..limit(limit))
          .get();
    }

    final userId = parsed.$2;
    return (select(messages)
          ..where((m) =>
              (m.recipientId.equals(userId) & m.isSentByMe.equals(true)) |
              (m.senderId.equals(userId) & m.isSentByMe.equals(false)))
          ..orderBy([
            (m) => OrderingTerm.desc(m.createdAtUnix),
            (m) => OrderingTerm.desc(m.serverId),
            (m) => OrderingTerm.desc(m.id),
          ])
          ..limit(limit))
        .get();
  }

  /// Get messages after a cursor (for pagination)
  Future<List<Message>> getMessagesAfterCursor(
    String conversationId,
    int cursorId, {
    int limit = 50,
  }) {
    final parsed = _parseConversationId(conversationId);
    if (parsed.$1 == 'group') {
      final groupId = parsed.$2;
      return (select(messages)
            ..where((m) => m.groupId.equals(groupId) &
                m.serverId.isNotNull() &
                m.serverId.isSmallerThanValue(cursorId))
            ..orderBy([
              (m) => OrderingTerm.desc(m.serverId),
              (m) => OrderingTerm.desc(m.id),
            ])
            ..limit(limit))
          .get();
    }

    final userId = parsed.$2;
    return (select(messages)
          ..where((m) =>
              ((m.recipientId.equals(userId) & m.isSentByMe.equals(true)) |
                  (m.senderId.equals(userId) & m.isSentByMe.equals(false))) &
              m.serverId.isNotNull() &
              m.serverId.isSmallerThanValue(cursorId))
          ..orderBy([
            (m) => OrderingTerm.desc(m.serverId),
            (m) => OrderingTerm.desc(m.id),
          ])
          ..limit(limit))
        .get();
  }

  /// Get latest server message ID for a conversation (0 if none).
  Future<int> getLatestServerMessageIdForConversation(String conversationId) async {
    final parsed = _parseConversationId(conversationId);
    if (parsed.$1 == 'group') {
      final groupId = parsed.$2;
      final row = await (select(messages)
            ..where((m) => m.groupId.equals(groupId) & m.serverId.isNotNull())
            ..orderBy([(m) => OrderingTerm.desc(m.serverId)])
            ..limit(1))
          .getSingleOrNull();
      return row?.serverId ?? 0;
    }

    final userId = parsed.$2;
    final row = await (select(messages)
          ..where((m) =>
              ((m.recipientId.equals(userId) & m.isSentByMe.equals(true)) |
                  (m.senderId.equals(userId) & m.isSentByMe.equals(false))) &
              m.serverId.isNotNull())
          ..orderBy([(m) => OrderingTerm.desc(m.serverId)])
          ..limit(1))
        .getSingleOrNull();
    return row?.serverId ?? 0;
  }

  Future<bool> hasMessageWithServerId(int serverId) async {
    if (serverId <= 0) return false;
    final row = await (select(messages)
          ..where((m) => m.serverId.equals(serverId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Update message with server ID after ACK
  Future<bool> updateMessageWithServerInfo(
    String clientId,
    int serverId,
    String status, {
    int? createdAtUnix,
  }) {
    final createdAtUtc = createdAtUnix != null
        ? DateTime.fromMillisecondsSinceEpoch(createdAtUnix * 1000, isUtc: true)
        : null;

    return (update(messages)..where((m) => m.clientId.equals(clientId))).write(
      MessagesCompanion(
        serverId: Value(serverId),
        status: Value(status),
        createdAtUnix: Value(createdAtUnix),
        createdAt: createdAtUtc != null ? Value(createdAtUtc) : const Value.absent(),
        updatedAt: Value(DateTime.now().toUtc()),
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
          ..orderBy([
            (c) => OrderingTerm.desc(c.lastMessageCreatedAtUnix),
            (c) => OrderingTerm.desc(c.lastMessageTime),
            (c) => OrderingTerm.desc(c.updatedAt),
          ]))
        .get();
  }

  /// Get conversation by id
  Future<Conversation?> getConversation(String conversationId) {
    return (select(conversations)
          ..where((c) => c.conversationId.equals(conversationId)))
        .getSingleOrNull();
  }

  /// Update conversation unread count
  Future<bool> updateConversationUnreadCount(String conversationId, int count) {
    return (update(conversations)
          ..where((c) => c.conversationId.equals(conversationId)))
        .write(
      ConversationsCompanion(
        unreadCount: Value(count),
        updatedAt: Value(DateTime.now()),
      ),
    ).then((rows) => rows > 0);
  }

  /// Clear unread count for conversation
  Future<bool> clearUnreadCount(String conversationId) {
    return updateConversationUnreadCount(conversationId, 0);
  }

  /// Mark outgoing DM messages as read up to a server message ID.
  Future<int> markDmMessagesRead(int senderId, int recipientId, int lastReadMessageId) {
    if (lastReadMessageId <= 0) return Future.value(0);
    return (update(messages)
          ..where((m) => m.groupId.isNull())
          ..where((m) => m.senderId.equals(senderId))
          ..where((m) => m.recipientId.equals(recipientId))
          ..where((m) => m.serverId.isSmallerOrEqualValue(lastReadMessageId)))
        .write(MessagesCompanion(
          status: const Value('read'),
          isRead: const Value(true),
          isDelivered: const Value(true),
        ));
  }

  /// Mark incoming DM messages as read up to a server message ID.
  Future<int> markIncomingDmMessagesRead(int senderId, int recipientId, int lastReadMessageId) {
    if (lastReadMessageId <= 0) return Future.value(0);
    return (update(messages)
          ..where((m) => m.groupId.isNull())
          ..where((m) => m.senderId.equals(senderId))
          ..where((m) => m.recipientId.equals(recipientId))
          ..where((m) => m.serverId.isSmallerOrEqualValue(lastReadMessageId)))
        .write(MessagesCompanion(
          status: const Value('read'),
          isRead: const Value(true),
          isDelivered: const Value(true),
        ));
  }

  /// Delete conversation
  Future<int> deleteConversation(String conversationId) {
    return (delete(conversations)
          ..where((c) => c.conversationId.equals(conversationId)))
        .go();
  }

  // ==================== Group Read State Operations ====================

  Future<void> upsertGroupReadState(int groupId, int userId, int lastReadMessageId) async {
    await into(groupReadStates).insertOnConflictUpdate(
      GroupReadStatesCompanion(
        groupId: Value(groupId),
        userId: Value(userId),
        lastReadMessageId: Value(lastReadMessageId),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<GroupReadState?> getGroupReadState(int groupId, int userId) {
    return (select(groupReadStates)
          ..where((g) => g.groupId.equals(groupId) & g.userId.equals(userId)))
        .getSingleOrNull();
  }

  Future<List<GroupReadState>> getGroupReadStates(int groupId) {
    return (select(groupReadStates)..where((g) => g.groupId.equals(groupId))).get();
  }

  Future<List<GroupReadState>> getAllGroupReadStates() {
    return select(groupReadStates).get();
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
    await delete(groupReadStates).go();
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
