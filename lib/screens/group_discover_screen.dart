import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../models/group.dart';
import '../providers/message_provider.dart';
import '../services/group_service.dart';
import 'chat_screen.dart';

class GroupDiscoverScreen extends StatefulWidget {
  const GroupDiscoverScreen({super.key});

  @override
  State<GroupDiscoverScreen> createState() => _GroupDiscoverScreenState();
}

class _GroupDiscoverScreenState extends State<GroupDiscoverScreen> {
  final _searchController = TextEditingController();
  final _handleController = TextEditingController();
  final _service = GroupService();

  List<Group> _results = [];
  bool _isSearching = false;
  String? _errorMessage;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _searchPublicGroups(value);
    });
  }

  Future<void> _searchPublicGroups(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _errorMessage = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final groups = await _service.searchPublicGroups(trimmed);
      if (!mounted) return;
      setState(() {
        _results = groups;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to search groups';
        _isSearching = false;
      });
    }
  }

  Future<void> _joinByHandle() async {
    final handle = _handleController.text.trim();
    if (handle.isEmpty) {
      setState(() {
        _errorMessage = 'Handle is required to join a public group';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    try {
      final group = await _service.joinByHandle(handle);
      if (!mounted) return;
      context.read<MessageProvider>().addOrUpdateGroupConversation(group, notify: false);
      _openGroupChat(group);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to join group by handle';
      });
    }
  }

  Future<void> _joinGroup(Group group) async {
    if (group.handle == null || group.handle!.isEmpty) {
      setState(() {
        _errorMessage = 'This group cannot be joined by handle';
      });
      return;
    }

    try {
      final joined = await _service.joinByHandle(group.handle!);
      if (!mounted) return;
      context.read<MessageProvider>().addOrUpdateGroupConversation(joined, notify: false);
      _openGroupChat(joined);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to join group';
      });
    }
  }

  void _openGroupChat(Group group) {
    final conversationId = 'group_${group.id}';
    final provider = context.read<MessageProvider>();
    provider.addOrUpdateGroupConversation(group, notify: false);
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
        title: const Text('Discover Groups'),
      ),
      body: Column(
        children: [
          _buildJoinByHandleCard(context),
          Expanded(child: _buildSearchBody(context)),
        ],
      ),
    );
  }

  Widget _buildJoinByHandleCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Join a public group by handle',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _handleController,
                  decoration: InputDecoration(
                    hintText: 'Handle (e.g. omdevs)',
                    prefixIcon: const Icon(Icons.tag),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _joinByHandle(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _joinByHandle,
                child: const Text('Join'),
              ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBody(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search public groups...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchPublicGroups('');
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              setState(() {});
              _onSearchChanged(value);
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildResults(context)),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.public,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search public groups',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Public groups can be discovered by handle or name',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No groups found',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final group = _results[index];
        final handle = group.handle?.isNotEmpty == true ? '@${group.handle}' : 'Public group';
        final description = group.description?.trim().isNotEmpty == true
            ? group.description!.trim()
            : 'Public group';

        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          title: Text(
            group.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                handle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
          trailing: TextButton(
            onPressed: () => _joinGroup(group),
            child: const Text('Join'),
          ),
        );
      },
    );
  }
}
