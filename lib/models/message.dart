import 'user.dart';

class Message {
  final int id;
  final String clientId;
  final int senderId;
  final User? sender;
  final int? recipientId;
  final int? groupId;
  final String content;
  final String messageType;
  final String status;
  final bool isDelivered;
  final bool isRead;
  // Canonical message time (UTC). Use createdAtLocal for display.
  final DateTime createdAt;
  // Canonical message time in UTC seconds since epoch.
  final int createdAtUnix;

  Message({
    required this.id,
    required this.clientId,
    required this.senderId,
    this.sender,
    this.recipientId,
    this.groupId,
    required this.content,
    required this.messageType,
    required this.status,
    required this.isDelivered,
    required this.isRead,
    required this.createdAt,
    required this.createdAtUnix,
  });

  DateTime get createdAtLocal => createdAt.toLocal();

  factory Message.fromJson(Map<String, dynamic> json) {
    final createdAtUnixRaw = json['created_at_unix'];
    DateTime createdAtUtc;
    int createdAtUnix;

    if (createdAtUnixRaw is int || createdAtUnixRaw is num) {
      createdAtUnix = (createdAtUnixRaw as num).toInt();
      createdAtUtc = DateTime.fromMillisecondsSinceEpoch(
        createdAtUnix * 1000,
        isUtc: true,
      );
    } else {
      // Fallback for older servers/rows.
      final parsed = DateTime.parse(json['created_at']);
      createdAtUtc = parsed.isUtc ? parsed : parsed.toUtc();
      createdAtUnix = createdAtUtc.millisecondsSinceEpoch ~/ 1000;
    }

    return Message(
      id: json['id'],
      clientId: json['client_id'] ?? '',
      senderId: json['sender_id'],
      sender: json['sender'] != null ? User.fromJson(json['sender']) : null,
      recipientId: json['recipient_id'],
      groupId: json['group_id'],
      content: json['content'],
      messageType: json['message_type'],
      status: json['status'],
      isDelivered: json['is_delivered'] ?? false,
      isRead: json['is_read'] ?? false,
      createdAt: createdAtUtc,
      createdAtUnix: createdAtUnix,
    );
  }
}
