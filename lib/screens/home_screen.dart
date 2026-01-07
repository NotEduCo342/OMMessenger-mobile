import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../models/conversation.dart';
import '../services/websocket_service.dart';
import '../services/update_service.dart';
import '../widgets/offline_banner.dart';
import '../widgets/update_dialog.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'user_search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
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
                padding: const EdgeInsets.only(right: 8.0),
                child: Center(
                  child: Container(
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
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
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

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(user: conversation.otherUser),
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
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    conversation.otherUser.username[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (conversation.otherUser.isOnline)
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
                          conversation.otherUser.fullName.isNotEmpty
                              ? conversation.otherUser.fullName
                              : conversation.otherUser.username,
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
                          lastMessage?.content ?? 'No messages yet',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
