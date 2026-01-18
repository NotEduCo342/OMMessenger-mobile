import 'package:drift/drift.dart';

// Messages table - stores all chat messages
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().unique()();
  IntColumn get serverId => integer().nullable()(); // From backend after ACK
  IntColumn get senderId => integer()();
  IntColumn get recipientId => integer().nullable()();
  IntColumn get groupId => integer().nullable()();
  TextColumn get content => text()();
  TextColumn get messageType => text().withDefault(const Constant('text'))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, sent, delivered, read
  BoolColumn get isDelivered => boolean().withDefault(const Constant(false))();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  // Canonical server timestamp (UTC seconds since epoch). Used to avoid timezone drift.
  IntColumn get createdAtUnix => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isSentByMe => boolean()();
}

// Pending messages - queue for offline/failed messages
class PendingMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientId => text().unique()();
  IntColumn get recipientId => integer().nullable()();
  IntColumn get groupId => integer().nullable()();
  TextColumn get content => text()();
  TextColumn get messageType => text().withDefault(const Constant('text'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get error => text().nullable()();
}

// Conversations - cached conversation metadata
class Conversations extends Table {
  TextColumn get conversationId => text()();
  TextColumn get conversationType => text()(); // dm | group
  IntColumn get otherUserId => integer().nullable()();
  TextColumn get otherUsername => text().nullable()();
  TextColumn get otherFullName => text().nullable()();
  TextColumn get otherAvatar => text().withDefault(const Constant(''))();
  BoolColumn get otherIsOnline => boolean().withDefault(const Constant(false))();
  IntColumn get groupId => integer().nullable()();
  TextColumn get groupName => text().nullable()();
  TextColumn get groupIcon => text().nullable()();
  IntColumn get groupMemberCount => integer().nullable()();
  TextColumn get lastMessageContent => text().nullable()();
  DateTimeColumn get lastMessageTime => dateTime().nullable()();
  IntColumn get lastMessageCreatedAtUnix => integer().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {conversationId};
}

// Group read states - per-member read progress cache
class GroupReadStates extends Table {
  IntColumn get groupId => integer()();
  IntColumn get userId => integer()();
  IntColumn get lastReadMessageId => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {groupId, userId};
}

// Sync state - track last synced message IDs per user
class SyncState extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().unique()();
  IntColumn get lastMessageId => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncAt => dateTime()();
}
