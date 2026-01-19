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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final messageProvider = context.watch<MessageProvider>();
    final conversations = messageProvider.conversations;

    return Scaffold(
      appBar: AppBar(
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
                    child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start chatting with your friends!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                        ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await messageProvider.refreshConversations();
              },
              child: ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  return _ConversationTile(conversation: conversations[index]);
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UserSearchScreen()),
          );
        },
        child: const Icon(Icons.edit),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;

  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final lastMessage = conversation.lastMessage;
    final timeText = lastMessage != null
        ? timeago.format(lastMessage.createdAt, locale: 'en_short')
        : '';
    final isGroup = conversation.type == ConversationType.group;
    final title = isGroup
        ? (conversation.group?.name ?? 'Group')
        : (conversation.otherUser?.fullName.isNotEmpty == true
            ? conversation.otherUser!.fullName
            : (conversation.otherUser?.username ?? 'User'));
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
      onTap: () {
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
      },
      child: Container(
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
            Stack(
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
                          '${subtitlePrefix}${lastMessage?.content ?? 'No messages yet'}',
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
                  await provider.addOrUpdateGroupConversation(result, notify: false);
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
