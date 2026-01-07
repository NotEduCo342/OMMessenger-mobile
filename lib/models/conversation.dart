import 'user.dart';
import 'message.dart';

class Conversation {
  final User otherUser;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime? lastActivity;

  Conversation({
    required this.otherUser,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastActivity,
  });

  Conversation copyWith({
    User? otherUser,
    Message? lastMessage,
    int? unreadCount,
    DateTime? lastActivity,
  }) {
    return Conversation(
      otherUser: otherUser ?? this.otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }
}
