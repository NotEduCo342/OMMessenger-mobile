import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../providers/message_provider.dart';
import '../widgets/user_avatar.dart';
import 'group_details_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final ConversationType type;
  final User? user;
  final Group? group;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.type,
    this.user,
    this.group,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _isLoadingMore = false;
  bool _isMuted = false;
  bool _muteLoaded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.type == ConversationType.dm && widget.user != null) {
        context.read<MessageProvider>().upsertConversationPeer(widget.user!);
      }
      context.read<MessageProvider>().setActiveConversation(widget.conversationId);
      context.read<MessageProvider>().openConversation(widget.conversationId);
      context.read<MessageProvider>().loadMessages(widget.conversationId);
      _loadMuteState();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    context.read<MessageProvider>().setActiveConversation(null);
    super.dispose();
  }

  Future<void> _loadMuteState() async {
    final muted = await context
        .read<MessageProvider>()
        .isConversationMuted(widget.conversationId);
    if (!mounted) return;
    if (_muteLoaded) return; // avoid overriding a user toggle
    setState(() {
      _isMuted = muted;
      _muteLoaded = true;
    });
  }

  Future<void> _toggleMute() async {
    final next = !_isMuted;
    if (mounted) {
      setState(() {
        _isMuted = next;
        _muteLoaded = true;
      });
    }

    try {
      await context
          .read<MessageProvider>()
          .setConversationMuted(widget.conversationId, next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isMuted = !next;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update mute setting')),
      );
    }
  }

  void _onScroll() {
    // With reverse:true, older messages are at the visual top (maxScrollExtent)
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        !_isLoadingMore) {
      final messageProvider = context.read<MessageProvider>();
      if (messageProvider.hasMoreMessages(widget.conversationId)) {
        _loadMoreMessages();
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore) return;
    
    setState(() {
      _isLoadingMore = true;
    });

    try {
      await context.read<MessageProvider>().loadMessages(
        widget.conversationId,
        loadMore: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onTextChanged(String text) {
    if (widget.type == ConversationType.group) return;
    final recipientId = _getDmRecipientId(context);
    if (recipientId == null) return;

    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      context.read<MessageProvider>().sendTypingIndicator(recipientId, true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        final recipientId = _getDmRecipientId(context);
        if (recipientId != null) {
          context.read<MessageProvider>().sendTypingIndicator(recipientId, false);
        }
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (widget.type == ConversationType.group) {
      final groupId = _getGroupId(context);
      if (groupId != null) {
        context.read<MessageProvider>().sendGroupMessage(groupId, text);
      }
    } else {
      final recipientId = _getDmRecipientId(context);
      if (recipientId != null) {
        context.read<MessageProvider>().sendMessage(recipientId, text);
      }
    }
    _messageController.clear();

    if (_isTyping) {
      _isTyping = false;
      if (widget.type == ConversationType.dm) {
        final recipientId = _getDmRecipientId(context);
        if (recipientId != null) {
          context.read<MessageProvider>().sendTypingIndicator(recipientId, false);
        }
      }
    }

    // Scroll to bottom (newest). With reverse:true, that's minScrollExtent.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messageProvider = context.watch<MessageProvider>();
    final messages = messageProvider.getMessages(widget.conversationId);
    final conversation = messageProvider.getConversation(widget.conversationId);
    final isGroup = (conversation?.type ?? widget.type) == ConversationType.group;
    final group = conversation?.group ?? widget.group;
    final user = conversation?.otherUser ?? widget.user;
    final dmRecipientId = _getDmRecipientId(context);
    final isOtherUserTyping = !isGroup && dmRecipientId != null
        ? messageProvider.isTyping(dmRecipientId)
        : false;
    final currentUserId = messageProvider.currentUserId;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          if (isGroup)
            IconButton(
              onPressed: group == null
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupDetailsScreen(group: group!),
                        ),
                      );
                    },
              tooltip: 'Group details',
              icon: const Icon(Icons.info_outline),
            ),
          IconButton(
            onPressed: _muteLoaded ? _toggleMute : null,
            tooltip: _isMuted ? 'Unmute' : 'Mute',
            icon: Icon(
              _isMuted ? Icons.notifications_off : Icons.notifications_active,
            ),
          ),
        ],
        title: Row(
          children: [
            Stack(
              children: [
                UserAvatar(
                  username: isGroup
                      ? (group?.name ?? 'Group')
                      : (user?.username ?? 'User'),
                  avatarUrl: isGroup ? (group?.icon ?? '') : (user?.avatar ?? ''),
                  radius: 20,
                ),
                if (!isGroup && (user?.isOnline ?? false))
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).appBarTheme.backgroundColor ?? Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isGroup
                        ? (group?.name ?? 'Group')
                        : ((user?.fullName.isNotEmpty ?? false)
                            ? user!.fullName
                            : (user?.username ?? 'User')),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!isGroup && isOtherUserTyping)
                    const Text(
                      'typing...',
                      style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                    )
                  else if (!isGroup && (user?.isOnline ?? false))
                    const Text(
                      'online',
                      style: TextStyle(fontSize: 13),
                    )
                  else if (isGroup && group != null)
                    Text(
                      '${group.memberCount} members',
                      style: const TextStyle(fontSize: 13),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet\nStart the conversation!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          String? readByLabel;
                          if (isGroup &&
                              currentUserId != null &&
                              message.senderId == currentUserId &&
                              group?.id != null &&
                              message.id > 0) {
                            final readers = messageProvider.getGroupReadersForMessage(
                              group!.id,
                              message.id,
                            );
                            if (readers.isNotEmpty) {
                              readByLabel = _formatReadByLabel(readers);
                            }
                          }
                          return _MessageBubble(
                            message: message,
                            isMe: currentUserId != null &&
                                message.senderId == currentUserId,
                            readByLabel: readByLabel,
                          );
                        },
                      ),
                      // Loading indicator at top
                      if (_isLoadingMore)
                        Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          // Input field
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onChanged: _onTextChanged,
                    decoration: InputDecoration(
                      hintText: 'Message',
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF17212B)
                          : const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int? _getDmRecipientId(BuildContext context) {
    if (widget.type == ConversationType.group) return null;
    final fromWidget = widget.user?.id;
    if (fromWidget != null) return fromWidget;
    final convo = context.read<MessageProvider>().getConversation(widget.conversationId);
    final fromConvo = convo?.otherUser?.id;
    if (fromConvo != null) return fromConvo;
    if (widget.conversationId.startsWith('user_')) {
      return int.tryParse(widget.conversationId.substring(5));
    }
    return null;
  }

  int? _getGroupId(BuildContext context) {
    if (widget.type == ConversationType.dm) return null;
    final fromWidget = widget.group?.id;
    if (fromWidget != null) return fromWidget;
    final convo = context.read<MessageProvider>().getConversation(widget.conversationId);
    final fromConvo = convo?.group?.id;
    if (fromConvo != null) return fromConvo;
    if (widget.conversationId.startsWith('group_')) {
      return int.tryParse(widget.conversationId.substring(6));
    }
    return null;
  }

  String _formatReadByLabel(List<User> readers) {
    if (readers.isEmpty) return '';
    final names = readers.map((u) {
      final name = u.fullName.isNotEmpty ? u.fullName : u.username;
      return name.isNotEmpty ? name : 'User ${u.id}';
    }).toList();

    const maxNames = 3;
    if (names.length <= maxNames) {
      return 'Seen by ${names.join(', ')}';
    }
    final first = names.take(maxNames).join(', ');
    final remaining = names.length - maxNames;
    return 'Seen by $first +$remaining';
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final String? readByLabel;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.readByLabel,
  });

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat('HH:mm').format(message.createdAtLocal);
    final colorScheme = Theme.of(context).colorScheme;

    final bubbleColor = isMe
        ? colorScheme.primary
        : (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF17212B)
            : const Color(0xFFF0F0F0));

    final textColor = isMe ? colorScheme.onPrimary : colorScheme.onSurface;
    final metaColor = isMe
        ? colorScheme.onPrimary.withOpacity(0.75)
        : colorScheme.onSurface.withOpacity(0.55);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: EdgeInsets.only(
              left: isMe ? 48 : 0,
              right: isMe ? 0 : 48,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 6),
                bottomRight: Radius.circular(isMe ? 6 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 16,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeText,
                      style: TextStyle(
                        fontSize: 11,
                        color: metaColor,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isRead
                            ? Icons.done_all
                            : message.isDelivered
                                ? Icons.done_all
                                : message.status == 'sent'
                                    ? Icons.done
                                    : Icons.schedule,
                        size: 14,
                        color: metaColor,
                      ),
                    ],
                  ],
                ),
                if (isMe && readByLabel != null) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      readByLabel!,
                      style: TextStyle(
                        fontSize: 10,
                        color: metaColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
