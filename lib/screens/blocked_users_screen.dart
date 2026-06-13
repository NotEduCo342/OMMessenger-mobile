import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../widgets/user_avatar.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<User> _blockedUsers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await context.read<AuthProvider>().getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load blocked users';
          _loading = false;
        });
      }
    }
  }

  Future<void> _unblockUser(User user) async {
    try {
      await context.read<AuthProvider>().unblockUser(user.id);
      await context.read<MessageProvider>().refreshConversations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.fullName.isNotEmpty ? user.fullName : user.username} unblocked')),
        );
        _loadBlockedUsers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unblock: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadBlockedUsers, child: const Text('Retry')),
                    ],
                  ),
                )
              : _blockedUsers.isEmpty
                  ? Center(
                      child: Text(
                        'No blocked users',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _blockedUsers.length,
                      itemBuilder: (context, index) {
                        final user = _blockedUsers[index];
                        final name = user.fullName.isNotEmpty ? user.fullName : user.username;
                        return ListTile(
                          leading: UserAvatar(
                            username: name,
                            avatarUrl: user.avatar,
                            radius: 20,
                          ),
                          title: Text(name),
                          subtitle: Text('@${user.username}'),
                          trailing: OutlinedButton(
                            onPressed: () => _unblockUser(user),
                            child: const Text('Unblock'),
                          ),
                        );
                      },
                    ),
    );
  }
}
