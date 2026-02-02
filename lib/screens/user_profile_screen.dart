import 'package:flutter/material.dart';
import '../models/user.dart';
import '../widgets/user_avatar.dart';
import 'package:flutter/services.dart';

class UserProfileScreen extends StatelessWidget {
  final User user;

  const UserProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final displayName = user.fullName.isNotEmpty ? user.fullName : user.username;
    final username = user.username.isNotEmpty ? '@${user.username}' : 'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              UserAvatar(
                username: displayName,
                avatarUrl: user.avatar,
                radius: 44,
              ),
              const SizedBox(height: 16),
              Text(
                displayName.isNotEmpty ? displayName : 'User ${user.id}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                username,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy username'),
                onTap: () async {
                  if (user.username.isEmpty) return;
                  await Clipboard.setData(ClipboardData(text: user.username));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Username copied')),
                    );
                  }
                },
              ),
              if (user.email.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(user.email),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
