import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/conversation.dart';
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../services/api_service.dart';
import '../widgets/user_avatar.dart';
import '../models/group.dart';
import 'chat_screen.dart';
import 'group_create_screen.dart';
import 'group_discover_screen.dart';
import 'group_invite_join_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _searchController = TextEditingController();
  final _apiService = ApiService();

  List<User> _searchResults = [];
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().length < 3) {
      setState(() {
        _searchResults = [];
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
      final response = await _apiService.get('/users/search?q=$query');
      final users = (response['users'] as List)
          .map((json) => User.fromJson(json))
          .toList();

      setState(() {
        _searchResults = users;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to search users: $e';
        _isSearching = false;
      });
    }
  }

  void _openChat(User user) {
    // Persist peer profile so we don't fall back to placeholders.
    context.read<MessageProvider>().upsertConversationPeer(user);
    final conversationId = 'user_${user.id}';
    // Initialize message loading for this user.
    context.read<MessageProvider>().openConversation(conversationId);
    context.read<MessageProvider>().loadMessages(conversationId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          type: ConversationType.dm,
          user: user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by username or name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _searchUsers('');
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
                // Debounce search
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (!mounted) return;
                  if (value == _searchController.text) {
                    _searchUsers(value);
                  }
                });
              },
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.isEmpty) {
      return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.group_add),
            title: const Text('Create group'),
            onTap: () async {
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
                Navigator.pushReplacement(
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupInviteJoinScreen()),
              );
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Enter at least 3 characters to find people',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    if (_searchResults.isEmpty) {
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
              'No users found',
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

    final currentUser = context.watch<AuthProvider>().user;

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final isSelf = currentUser != null && user.id == currentUser.id;

        return ListTile(
          leading: isSelf
              ? CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Icon(
                    Icons.bookmark,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : Stack(
                  children: [
                    UserAvatar(
                      username: user.username,
                      avatarUrl: user.avatar,
                      radius: 24,
                    ),
                    if (user.isOnline)
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
          title: Text(
            isSelf ? 'Saved Messages' : (user.fullName.isNotEmpty ? user.fullName : user.username),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: isSelf
              ? null
              : Text(
                  '@${user.username}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
          trailing: Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          onTap: () => _openChat(user),
        );
      },
    );
  }
}
