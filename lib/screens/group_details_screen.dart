import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/group.dart';
import '../models/user.dart';
import '../services/group_service.dart';
import '../widgets/user_avatar.dart';

class GroupDetailsScreen extends StatefulWidget {
  final Group group;

  const GroupDetailsScreen({super.key, required this.group});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  final _service = GroupService();

  bool _loadingMembers = true;
  String? _error;
  List<User> _members = [];

  bool _creatingInvite = false;
  Map<String, dynamic>? _inviteLink;
  bool _singleUse = false;
  int? _expiresInSeconds;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loadingMembers = true;
      _error = null;
    });

    try {
      final rawMembers = await _service.getGroupMembers(widget.group.id);
      final members = rawMembers
          .whereType<Map>()
          .map((item) => User.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (!mounted) return;
      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load members';
        _loadingMembers = false;
      });
    }
  }

  Future<void> _createInviteLink() async {
    setState(() {
      _creatingInvite = true;
      _error = null;
      _inviteLink = null;
    });

    try {
      final link = await _service.createInviteLink(
        widget.group.id,
        singleUse: _singleUse,
        expiresInSeconds: _expiresInSeconds,
      );
      if (!mounted) return;
      setState(() {
        _inviteLink = link;
        _creatingInvite = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to create invite link (admin only)';
        _creatingInvite = false;
      });
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text('You will need an invite to rejoin private groups.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.leaveGroup(widget.group.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to leave group';
      });
    }
  }

  void _copyInvite(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final privacyLabel = group.isPublic ? 'Public group' : 'Private group';
    final privacyIcon = group.isPublic ? Icons.public : Icons.lock;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group details'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMembers,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(context, group, privacyLabel, privacyIcon),
              const SizedBox(height: 16),
              _buildInviteSection(context),
              const SizedBox(height: 16),
              _buildMembersSection(context),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _leaveGroup,
                icon: const Icon(Icons.exit_to_app),
                label: const Text('Leave group'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Group group,
    String privacyLabel,
    IconData privacyIcon,
  ) {
    final memberCount = _members.isNotEmpty
        ? _members.length
        : (group.memberCount > 0 ? group.memberCount : null);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(privacyIcon, size: 16),
                  const SizedBox(width: 6),
                  Text(privacyLabel),
                ],
              ),
              if (group.handle?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text('@${group.handle}'),
              ],
              if (group.description?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(group.description!.trim()),
              ],
              if (memberCount != null) ...[
                const SizedBox(height: 8),
                Text('$memberCount members'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInviteSection(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invite link',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _singleUse,
              onChanged: (value) {
                setState(() {
                  _singleUse = value;
                });
              },
              title: const Text('Single use'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _expiresInSeconds,
              decoration: const InputDecoration(
                labelText: 'Expires',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Never')),
                DropdownMenuItem(value: 3600, child: Text('1 hour')),
                DropdownMenuItem(value: 86400, child: Text('24 hours')),
                DropdownMenuItem(value: 604800, child: Text('7 days')),
              ],
              onChanged: (value) {
                setState(() {
                  _expiresInSeconds = value;
                });
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _creatingInvite ? null : _createInviteLink,
              icon: _creatingInvite
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('Create invite'),
            ),
            if (_inviteLink != null) ...[
              const SizedBox(height: 12),
              _buildInviteResult(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInviteResult(BuildContext context) {
    final token = _inviteLink?['token']?.toString() ?? '';
    final joinUrl = _inviteLink?['join_url']?.toString() ?? '';
    final joinPath = _inviteLink?['join_path']?.toString() ?? '';
    final display = joinUrl.isNotEmpty ? joinUrl : joinPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invite created',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        if (display.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  display,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => _copyInvite(display),
                icon: const Icon(Icons.copy),
                tooltip: 'Copy invite',
              ),
            ],
          )
        else if (token.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(token),
              ),
              IconButton(
                onPressed: () => _copyInvite(token),
                icon: const Icon(Icons.copy),
                tooltip: 'Copy token',
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMembersSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Members',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_loadingMembers)
          const Center(child: CircularProgressIndicator())
        else if (_members.isEmpty)
          Text(
            'No members to show',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
          )
        else
          ..._members.map((member) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  username: member.username,
                  avatarUrl: member.avatar,
                  radius: 18,
                  showProgress: false,
                ),
                title: Text(
                  member.fullName.isNotEmpty ? member.fullName : member.username,
                ),
                subtitle: Text('@${member.username}'),
              )),
      ],
    );
  }
}
