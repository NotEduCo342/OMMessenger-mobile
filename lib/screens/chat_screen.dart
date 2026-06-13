import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../providers/message_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/user_avatar.dart';
import 'user_profile_screen.dart';
import 'package:flutter/services.dart';
import 'group_details_screen.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../widgets/auth_image.dart';
import 'image_viewer_screen.dart';

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
  final _focusNode = FocusNode();
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _isLoadingMore = false;
  bool _isMuted = false;
  bool _muteLoaded = false;
  final _apiService = ApiService();
  bool _isUploadingImage = false;
  
  Message? _editingMessage;
  Message? _replyingToMessage;
  final Set<int> _deletingMessageIds = {};
  late final MessageProvider _messageProvider;

  @override
  void initState() {
    super.initState();
    _messageProvider = context.read<MessageProvider>();
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
    _focusNode.dispose();
    _typingTimer?.cancel();
    _messageProvider.setActiveConversation(null);
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
    if (widget.type == ConversationType.group) {
      final groupId = _getGroupId(context);
      if (groupId == null) return;

      if (text.isNotEmpty && !_isTyping) {
        _isTyping = true;
        context.read<MessageProvider>().sendGroupTypingIndicator(groupId, true);
      }

      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        if (_isTyping) {
          _isTyping = false;
          final groupId = _getGroupId(context);
          if (groupId != null) {
            context.read<MessageProvider>().sendGroupTypingIndicator(groupId, false);
          }
        }
      });
      return;
    }

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

    if (_editingMessage != null) {
      context.read<MessageProvider>().editMessage(_editingMessage!.id, text, widget.conversationId);
      setState(() {
        _editingMessage = null;
      });
    } else {
      if (widget.type == ConversationType.group) {
        final groupId = _getGroupId(context);
        if (groupId != null) {
          context.read<MessageProvider>().sendGroupMessage(groupId, text, replyToMessage: _replyingToMessage);
        }
      } else {
        final recipientId = _getDmRecipientId(context);
        if (recipientId != null) {
          context.read<MessageProvider>().sendMessage(recipientId, text, replyToMessage: _replyingToMessage);
        }
      }
      setState(() {
        _replyingToMessage = null;
      });
    }
    _messageController.clear();
    _focusNode.requestFocus();

    if (_isTyping) {
      _isTyping = false;
      if (widget.type == ConversationType.group) {
        final groupId = _getGroupId(context);
        if (groupId != null) {
          context.read<MessageProvider>().sendGroupTypingIndicator(groupId, false);
        }
      } else {
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

  Future<void> _handleDeleteMessage(Message message) async {
    setState(() {
      _deletingMessageIds.add(message.id);
    });
    
    // Wait for the shredding animation
    await Future.delayed(const Duration(milliseconds: 600));
    
    if (mounted) {
      setState(() {
        _deletingMessageIds.remove(message.id);
      });
      context.read<MessageProvider>().deleteMessage(message.id, widget.conversationId);
    }
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return;

    setState(() {
      _isUploadingImage = true;
    });

    try {
      final url = await _apiService.uploadAttachment(image.path);

      if (widget.type == ConversationType.group) {
        final groupId = _getGroupId(context);
        if (groupId != null) {
          context.read<MessageProvider>().sendGroupMessage(groupId, url, messageType: 'image');
        }
      } else {
        final recipientId = _getDmRecipientId(context);
        if (recipientId != null) {
          context.read<MessageProvider>().sendMessage(recipientId, url, messageType: 'image');
        }
      }

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.minScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
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
    final isSelf = !isGroup && user != null && user.id == currentUserId;

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
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (!isGroup && user != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(user: user!),
                ),
              );
            } else if (isGroup && group != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupDetailsScreen(group: group!),
                ),
              );
            }
          },
          child: Row(
            children: [
              isSelf
                  ? CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(
                        Icons.bookmark,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 20,
                      ),
                    )
                  : Stack(
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
                      isSelf
                          ? 'Saved Messages'
                          : (isGroup
                              ? (group?.name ?? 'Group')
                              : ((user?.fullName.isNotEmpty ?? false)
                                  ? user!.fullName
                                  : (user?.username ?? 'User'))),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (!isSelf) ...[
                      if (isGroup && messageProvider.getTypingUserIds(widget.conversationId).isNotEmpty)
                        Text(
                          messageProvider.getTypingIndicatorText(widget.conversationId),
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      else if (!isGroup && isOtherUserTyping)
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
                  ],
                ),
              ),
            ],
          ),
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
                            key: ValueKey(message.clientId),
                            message: message,
                            isMe: currentUserId != null &&
                                message.senderId == currentUserId,
                            readByLabel: readByLabel,
                            isDeleting: _deletingMessageIds.contains(message.id),
                            onReply: () {
                              setState(() {
                                _replyingToMessage = message;
                                _editingMessage = null;
                              });
                              _focusNode.requestFocus();
                            },
                            onEdit: () {
                              setState(() {
                                _editingMessage = message;
                                _replyingToMessage = null;
                                _messageController.text = message.content;
                              });
                              _focusNode.requestFocus();
                            },
                            onDelete: () => _handleDeleteMessage(message),
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
          Column(
            children: [
              if (_isUploadingImage)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context).cardColor,
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Uploading image...',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_editingMessage != null || _replyingToMessage != null)
                Container(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _editingMessage != null ? Icons.edit : Icons.reply,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _editingMessage != null ? 'Edit Message' : 'Reply to Message',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              (_editingMessage ?? _replyingToMessage)!.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _editingMessage = null;
                            _replyingToMessage = null;
                            _messageController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              if (!isGroup && user != null && user.isBlocked)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'You blocked this user.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          try {
                            await context.read<AuthProvider>().unblockUser(user.id);
                            if (context.mounted) {
                              context.read<MessageProvider>().refreshConversations();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('User unblocked')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to unblock: $e')),
                              );
                            }
                          }
                        },
                        child: const Text('Unblock'),
                      ),
                    ],
                  ),
                )
              else
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
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _isUploadingImage ? null : _sendImage,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
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
                      onSubmitted: (_) {
                        _sendMessage();
                        _focusNode.requestFocus();
                      },
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

class _MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final String? readByLabel;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isDeleting;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.readByLabel,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.isDeleting = false,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> with SingleTickerProviderStateMixin {
  late AnimationController _shredController;
  late Animation<double> _shredAnimation;

  @override
  void initState() {
    super.initState();
    _shredController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shredAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _shredController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDeleting && !oldWidget.isDeleting) {
      _shredController.forward();
    } else if (!widget.isDeleting && oldWidget.isDeleting) {
      _shredController.reset();
    }
  }

  @override
  void dispose() {
    _shredController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = widget.isMe;
    final readByLabel = widget.readByLabel;
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

    final isRtl = Bidi.detectRtlDirectionality(message.content);

    final messageProvider = context.watch<MessageProvider>();
    final showSenderInfo = message.groupId != null && !isMe;

    User? senderUser;
    if (showSenderInfo) {
      final members = messageProvider.getGroupMembers(message.groupId!);
      senderUser = members[message.senderId] ?? message.sender;
    }

    Color getSenderColor(String username, bool isDark) {
      final hash = username.hashCode;
      final double hue = (hash.abs() % 360).toDouble();
      return HSLColor.fromAHSL(
        1.0,
        hue,
        0.75,
        isDark ? 0.7 : 0.4,
      ).toColor();
    }

    return SizeTransition(
      sizeFactor: _shredAnimation,
      axisAlignment: isMe ? 1.0 : -1.0,
      child: FadeTransition(
        opacity: _shredAnimation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showSenderInfo) ...[
                  UserAvatar(
                    username: senderUser?.fullName.isNotEmpty == true
                        ? senderUser!.fullName
                        : (senderUser?.username ?? 'User'),
                    avatarUrl: senderUser?.avatar ?? '',
                    radius: 16,
                  ),
                  const SizedBox(width: 8),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * (showSenderInfo ? 0.70 : 0.78),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 6),
                      bottomRight: Radius.circular(isMe ? 6 : 18),
                    ),
                    onTap: () {
                      if (message.messageType == 'image') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ImageViewerScreen(imageUrl: message.content),
                          ),
                        );
                      }
                    },
                    onSecondaryTap: () => _showMessageOptions(context),
                    onLongPress: () => _showMessageOptions(context),
                    child: Container(
                      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
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
                      child: IntrinsicWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showSenderInfo) ...[
                              Text(
                                senderUser?.fullName.isNotEmpty == true
                                    ? senderUser!.fullName
                                    : (senderUser?.username ?? 'User'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: getSenderColor(
                                    senderUser?.username ?? 'User',
                                    Theme.of(context).brightness == Brightness.dark,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (message.replyToId != null && message.replyToMessageContent != null) ...[
                              Container(
                                padding: const EdgeInsets.all(8),
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border(
                                    left: BorderSide(
                                      color: isMe ? Colors.white : Theme.of(context).colorScheme.primary,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  message.replyToMessageContent!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textColor.withOpacity(0.9),
                                  ),
                                ),
                              ),
                            ],
                            if (message.messageType == 'image')
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: math.min(600.0, MediaQuery.sizeOf(context).width * 0.6),
                                    maxHeight: math.min(600.0, MediaQuery.sizeOf(context).height * 0.6),
                                  ),
                                  child: AuthImage(
                                    imageUrl: message.content,
                                    fit: BoxFit.cover,
                                    errorWidget: const Icon(Icons.broken_image, size: 100),
                                  ),
                                ),
                              )
                            else
                              Directionality(
                                textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
                                child: Text(
                                  message.content,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: textColor,
                                  ),
                                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (message.version > 1) ...[
                                  Text(
                                    '(edited) ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: metaColor.withOpacity(0.8),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
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
                                  readByLabel,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    if (widget.message.content.trim().isEmpty && widget.message.messageType != 'image') return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: widget.message.content));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message copied')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onReply?.call();
                },
              ),
              if (widget.isMe) ...[
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onEdit?.call();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onDelete?.call();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
