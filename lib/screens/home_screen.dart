import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../models/conversation.dart';
import '../models/group.dart';
import '../services/websocket_service.dart';
import '../services/notification_prefs.dart';
import '../services/update_service.dart';
import '../widgets/offline_banner.dart';
import '../widgets/user_avatar.dart';
import '../widgets/update_dialog.dart';
import 'chat_screen.dart';
import 'group_create_screen.dart';
import 'group_discover_screen.dart';
import 'group_invite_join_screen.dart';
import 'blocked_users_screen.dart';
import 'settings_screen.dart';
import 'user_search_screen.dart';

class _HomeLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onResumed;
  final VoidCallback onPaused;

  _HomeLifecycleObserver({required this.onResumed, required this.onPaused});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      onPaused();
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedConversationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  late final _HomeLifecycleObserver _lifecycleObserver = _HomeLifecycleObserver(
    onResumed: () {
      if (!mounted) return;
      NotificationPrefs.setAppForeground(true);
      final user = context.read<AuthProvider>().user;
      if (user != null) {
        context.read<MessageProvider>().handleAppResumed();
      }
    },
    onPaused: () {
      NotificationPrefs.setAppForeground(false);
    },
  );

  @override
  void initState() {
    super.initState();
    NotificationPrefs.setAppForeground(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      if (user != null) {
        context.read<MessageProvider>().initialize(user);
        
        // Check for updates after 2 seconds (don't block initialization)
        Future.delayed(const Duration(seconds: 2), () {
          _checkForUpdates();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    try {
      final updateService = UpdateService();
      final updateInfo = await updateService.checkForUpdate();
      
      if (updateInfo['needsUpdate'] == true && mounted) {
        // Check if user clicked "Remind Me Later"
        final prefs = await SharedPreferences.getInstance();
        final remindAtStr = prefs.getString('update_remind_at');
        
        if (remindAtStr != null) {
          final remindAt = DateTime.parse(remindAtStr);
          // Don't show dialog if within reminder period (unless force update)
          if (DateTime.now().isBefore(remindAt) && !updateInfo['isForceUpdate']) {
            return; // Skip showing dialog
          }
        }
        
        showDialog(
          context: context,
          barrierDismissible: !updateInfo['isForceUpdate'],
          builder: (context) => UpdateDialog(
            currentVersion: updateInfo['currentVersion'],
            latestVersion: updateInfo['latestVersion'],
            downloadUrl: updateInfo['downloadUrl'],
            changelog: updateInfo['changelog'],
            isForceUpdate: updateInfo['isForceUpdate'] ?? false,
          ),
        );
      }
    } catch (e) {
      // Silently fail - don't block user if update check fails
    }
  }

  void _confirmDeleteConversation(String conversationId) {
    final messageProvider = context.read<MessageProvider>();
    final conversation = messageProvider.getConversation(conversationId);
    if (conversation == null) return;

    final isGroup = conversation.type == ConversationType.group;
    bool deleteForEveryone = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Delete Chat'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Are you sure you want to delete this chat? This action is not recoverable and all media will be lost.',
                    style: TextStyle(height: 1.4),
                  ),
                  if (!isGroup) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: deleteForEveryone,
                          onChanged: (val) {
                            setDialogState(() {
                              deleteForEveryone = val ?? false;
                            });
                          },
                        ),
                        const Expanded(
                          child: Text('Also delete for the receiver'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context); // Close dialog
                    
                    // Clear selection first
                    setState(() {
                      _selectedConversationId = null;
                    });

                    try {
                      // Perform deletion
                      await context.read<MessageProvider>().deleteConversation(
                            conversationId,
                            everyone: deleteForEveryone,
                          );

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Chat deleted')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to delete chat')),
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final messageProvider = context.watch<MessageProvider>();
    final conversations = messageProvider.conversations;

    return PopScope(
      canPop: _selectedConversationId == null,
      onPopInvoked: (didPop) {
        if (didPop) return;
        setState(() {
          _selectedConversationId = null;
        });
      },
      child: Scaffold(
        appBar: _selectedConversationId != null
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Close selection',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedConversationId = null;
                    });
                  },
                ),
                title: const Text('1 selected'),
                actions: [
                  IconButton(
                    tooltip: 'Delete chat',
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDeleteConversation(_selectedConversationId!),
                  ),
                ],
              )
            : AppBar(
                title: const Text('OM Messenger'),
                actions: [
                  // Connection status indicator
                  StreamBuilder<ConnectionStatus>(
                    stream: messageProvider.connectionStream,
                    initialData: messageProvider.connectionStatus,
                    builder: (context, snapshot) {
                      final status = snapshot.data ?? ConnectionStatus.disconnected;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () {
                                // Manual ping refresh
                                context.read<MessageProvider>().handleAppResumed();
                              },
                              child: StreamBuilder<int?>(
                                stream: messageProvider.pingMsStream,
                                initialData: messageProvider.pingMs,
                                builder: (context, pingSnapshot) {
                                  final ping = pingSnapshot.data;
                                  final text = (status == ConnectionStatus.connected && ping != null)
                                      ? '${ping}ms'
                                      : '--';
                                  return Text(
                                    text,
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                        ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: status == ConnectionStatus.connected
                                    ? Colors.green
                                    : status == ConnectionStatus.connecting ||
                                            status == ConnectionStatus.reconnecting
                                        ? Colors.orange
                                        : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
      drawer: _HomeDrawer(user: user),
      body: Column(
        children: [
          const OfflineBanner(),
          if (messageProvider.isRestoringPeers)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Restoring conversations…',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          Expanded(
            child: conversations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.forum_rounded,
                              size: 80,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Welcome to OM Messenger',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Connect with your friends, share media, and join vibrant communities. Start chatting now!',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  height: 1.5,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const UserSearchScreen()),
                              );
                            },
                            icon: const Icon(Icons.edit_square),
                            label: const Text('Start a New Chat'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
          : RefreshIndicator(
              onRefresh: () async {
                await messageProvider.refreshConversations();
              },
              child: ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return _ConversationTile(
                    conversation: conversation,
                    isSelected: _selectedConversationId == conversation.conversationId,
                    onTap: () {
                      if (_selectedConversationId != null) {
                        setState(() {
                          if (_selectedConversationId == conversation.conversationId) {
                            _selectedConversationId = null;
                          } else {
                            _selectedConversationId = conversation.conversationId;
                          }
                        });
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              conversationId: conversation.conversationId,
                              type: conversation.type,
                              user: conversation.otherUser,
                              group: conversation.group,
                            ),
                          ),
                        );
                      }
                    },
                    onLongPress: () {
                      setState(() {
                        _selectedConversationId = conversation.conversationId;
                      });
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'New chat',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserSearchScreen()),
            );
          },
          child: const Icon(Icons.edit),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final lastMessage = conversation.lastMessage;
    final timeText = lastMessage != null
        ? timeago.format(lastMessage.createdAt, locale: 'en_short')
        : '';
    final isGroup = conversation.type == ConversationType.group;
    final currentUser = context.watch<AuthProvider>().user;
    final isSelf = !isGroup && conversation.otherUser?.id == currentUser?.id;

    final title = isSelf
        ? 'Saved Messages'
        : (isGroup
            ? (conversation.group?.name ?? 'Group')
            : (conversation.otherUser?.fullName.isNotEmpty == true
                ? conversation.otherUser!.fullName
                : (conversation.otherUser?.username ?? 'User')));
    final avatarLabel = isGroup
        ? (conversation.group?.name ?? 'Group')
        : (conversation.otherUser?.username ?? 'User');
    final avatarUrl = isGroup
        ? (conversation.group?.icon ?? '')
        : (conversation.otherUser?.avatar ?? '');
    final subtitlePrefix = isGroup
        ? (conversation.lastMessage?.sender?.username != null
            ? '${conversation.lastMessage!.sender!.username}: '
            : '')
        : (lastMessage?.senderId == context.read<MessageProvider>().currentUserId
            ? 'You: '
            : '');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            isSelf
                ? CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(
                      Icons.bookmark,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 28,
                    ),
                  )
                : Stack(
                    children: [
                      UserAvatar(
                        username: avatarLabel,
                        avatarUrl: avatarUrl,
                        radius: 28,
                      ),
                      if (!isGroup && (conversation.otherUser?.isOnline ?? false))
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: TextStyle(
                            fontSize: 13,
                            color: conversation.unreadCount > 0
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${subtitlePrefix}${lastMessage?.messageType == 'image' ? '📷 Photo' : (lastMessage?.content ?? 'No messages yet')}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                        FutureBuilder<bool>(
                          future: context
                              .read<MessageProvider>()
                              .isConversationMuted(conversation.conversationId),
                          builder: (context, snapshot) {
                            if (snapshot.data == true) {
                              return Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.notifications_off,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.45),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      if (conversation.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            conversation.unreadCount > 99
                                ? '99+'
                                : conversation.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  final user;

  const _HomeDrawer({required this.user});

  @override
  Widget build(BuildContext context) {
    final displayName = (user?.fullName?.isNotEmpty == true)
        ? user!.fullName
        : (user?.username ?? 'User');
    final subtitle = user?.username ?? '';

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: UserAvatar(
                username: displayName,
                avatarUrl: user?.avatar ?? '',
                radius: 22,
              ),
              title: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: subtitle.isNotEmpty
                  ? Text(
                      '@$subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('New chat'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserSearchScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('Create group'),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupCreateScreen()),
                );
                if (!context.mounted) return;
                if (result is Group) {
                  final provider = context.read<MessageProvider>();
                  await provider.addOrUpdateGroupConversation(result);
                  provider.openConversation('group_${result.id}');
                  provider.loadMessages('group_${result.id}');
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        conversationId: 'group_${result.id}',
                        type: ConversationType.group,
                        group: result,
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Discover groups'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupDiscoverScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Join by invite'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupInviteJoinScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Blocked users'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
                );
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
