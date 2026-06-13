import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../widgets/user_avatar.dart';
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import 'package:flutter/services.dart';

class UserProfileScreen extends StatefulWidget {
  final User user;

  const UserProfileScreen({super.key, required this.user});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late bool _isBlocked;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isBlocked = widget.user.isBlocked;
  }

  Future<void> _toggleBlock() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final messageProvider = context.read<MessageProvider>();

      if (_isBlocked) {
        await authProvider.unblockUser(widget.user.id);
        setState(() {
          _isBlocked = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User unblocked')),
          );
        }
      } else {
        // Confirm block
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Block User?'),
            content: Text('Are you sure you want to block ${widget.user.fullName.isNotEmpty ? widget.user.fullName : widget.user.username}? They won\'t be able to message you.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Block'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await authProvider.blockUser(widget.user.id);
          setState(() {
            _isBlocked = true;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('User blocked')),
            );
          }
        }
      }

      // Refresh conversations to update cache
      await messageProvider.refreshConversations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operation failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.fullName.isNotEmpty ? widget.user.fullName : widget.user.username;
    final username = widget.user.username.isNotEmpty ? '@${widget.user.username}' : 'Unknown';

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
                avatarUrl: _isBlocked ? '' : widget.user.avatar,
                radius: 44,
              ),
              const SizedBox(height: 16),
              Text(
                displayName.isNotEmpty ? displayName : 'User ${widget.user.id}',
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
                  if (widget.user.username.isEmpty) return;
                  await Clipboard.setData(ClipboardData(text: widget.user.username));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Username copied')),
                    );
                  }
                },
              ),
              if (widget.user.email.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(widget.user.email),
                ),
              ],
              const Spacer(),
              _isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _isBlocked ? Colors.green : Theme.of(context).colorScheme.error,
                          side: BorderSide(
                            color: _isBlocked ? Colors.green : Theme.of(context).colorScheme.error,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _toggleBlock,
                        icon: Icon(_isBlocked ? Icons.check_circle_outline : Icons.block),
                        label: Text(_isBlocked ? 'Unblock User' : 'Block User'),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
