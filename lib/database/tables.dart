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
  IntColumn get id => integer().autoIncrement()();
  IntColumn get otherUserId => integer().unique()();
  TextColumn get otherUsername => text()();
  TextColumn get otherFullName => text()();
  TextColumn get otherAvatar => text().withDefault(const Constant(''))();
  BoolColumn get otherIsOnline => boolean().withDefault(const Constant(false))();
  TextColumn get lastMessageContent => text().nullable()();
  DateTimeColumn get lastMessageTime => dateTime().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
}

// Sync state - track last synced message IDs per user
class SyncState extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().unique()();
  IntColumn get lastMessageId => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncAt => dateTime()();
}
