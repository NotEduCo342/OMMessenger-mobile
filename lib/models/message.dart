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
  final DateTime createdAt;

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
  });

  factory Message.fromJson(Map<String, dynamic> json) {
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
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
