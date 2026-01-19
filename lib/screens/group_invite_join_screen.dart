import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../models/group.dart';
import '../providers/message_provider.dart';
import '../services/group_service.dart';
import 'chat_screen.dart';

class GroupInviteJoinScreen extends StatefulWidget {
  const GroupInviteJoinScreen({super.key});

  @override
  State<GroupInviteJoinScreen> createState() => _GroupInviteJoinScreenState();
}

class _GroupInviteJoinScreenState extends State<GroupInviteJoinScreen> {
  final _tokenController = TextEditingController();
  final _service = GroupService();

  Map<String, dynamic>? _preview;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  String _extractToken(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return segments.last;
      }
    }
    return trimmed;
  }

  Future<void> _previewInvite() async {
    final token = _extractToken(_tokenController.text);
    if (token.isEmpty) {
      setState(() {
        _error = 'Invite token is required';
        _preview = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _service.previewInviteToken(token);
      if (!mounted) return;
      setState(() {
        _preview = data;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _error = 'Unable to preview invite';
        _isLoading = false;
      });
    }
  }

  Future<void> _joinWithInvite() async {
    final token = _extractToken(_tokenController.text);
    if (token.isEmpty) {
      setState(() {
        _error = 'Invite token is required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final group = await _service.joinByInviteToken(token);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _openGroupChat(group);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Unable to join this group';
      });
    }
  }

  void _openGroupChat(Group group) {
    final conversationId = 'group_${group.id}';
    final provider = context.read<MessageProvider>();
    provider.openConversation(conversationId);
    provider.loadMessages(conversationId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          type: ConversationType.group,
          group: group,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join by Invite'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste an invite link or token',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tokenController,
                decoration: InputDecoration(
                  hintText: 'https://.../join/<token> or token',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _previewInvite(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _previewInvite,
                      child: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _joinWithInvite,
                      child: const Text('Join'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              if (_isLoading) const Center(child: CircularProgressIndicator()),
              if (!_isLoading && _preview != null) _buildPreviewCard(context),
              if (!_isLoading && _preview == null) _buildPrivacyHint(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final preview = _preview ?? const {};
    final groupJson = preview['group'] as Map?;
    final group = groupJson != null
        ? Group.fromJson(Map<String, dynamic>.from(groupJson))
        : null;
    final isPublic = group?.isPublic ?? false;
    final expiresAt = preview['expires_at']?.toString();
    final maxUses = preview['max_uses'];
    final usedCount = preview['used_count'];

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isPublic ? Icons.public : Icons.lock),
                const SizedBox(width: 8),
                Text(
                  isPublic ? 'Public group' : 'Private group',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              group?.name ?? 'Group',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (group?.description?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                group!.description!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (group?.handle?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text('@${group!.handle}'),
            ],
            const SizedBox(height: 12),
            if (expiresAt != null) Text('Expires: $expiresAt'),
            if (maxUses != null) Text('Max uses: $maxUses'),
            if (usedCount != null) Text('Used: $usedCount'),
            if (!isPublic)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Private groups are only accessible by invite.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyHint(BuildContext context) {
    return Text(
      'Invites can be used for private or public groups.\nPublic groups can also be found in Discover.',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
    );
  }
}
