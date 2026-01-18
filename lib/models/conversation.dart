import 'user.dart';
import 'group.dart';
import 'message.dart';

enum ConversationType { dm, group }

ConversationType conversationTypeFromString(String value) {
  switch (value) {
    case 'group':
      return ConversationType.group;
    case 'dm':
    default:
      return ConversationType.dm;
  }
}

String conversationTypeToString(ConversationType type) {
  return type == ConversationType.group ? 'group' : 'dm';
}

class Conversation {
  final String conversationId; // user_<id> or group_<id>
  final ConversationType type;
  final User? otherUser;
  final Group? group;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime? lastActivity;

  Conversation({
    required this.conversationId,
    required this.type,
    this.otherUser,
    this.group,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastActivity,
  });

  Conversation copyWith({
    String? conversationId,
    ConversationType? type,
    User? otherUser,
    Group? group,
    Message? lastMessage,
    int? unreadCount,
    DateTime? lastActivity,
  }) {
    return Conversation(
      conversationId: conversationId ?? this.conversationId,
      type: type ?? this.type,
      otherUser: otherUser ?? this.otherUser,
      group: group ?? this.group,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }
}
