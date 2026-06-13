import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/group_service.dart';
import '../models/user.dart';
import '../widgets/user_avatar.dart';

class GroupAddMembersScreen extends StatefulWidget {
  final int groupId;
  const GroupAddMembersScreen({super.key, required this.groupId});

  @override
  State<GroupAddMembersScreen> createState() => _GroupAddMembersScreenState();
}

class _GroupAddMembersScreenState extends State<GroupAddMembersScreen> {
  final ApiService _api = ApiService();
  final GroupService _groupService = GroupService();
  
  List<User> _peers = [];
  bool _isLoading = true;
  String? _error;
  
  final Set<int> _selectedUserIds = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadPeers();
  }

  Future<void> _loadPeers() async {
    try {
      final response = await _api.get('/conversations/peers?limit=100');
      if (response is Map && response['peers'] is List) {
        final list = response['peers'] as List;
        setState(() {
          _peers = list.map((json) {
            final p = json['peer'] as Map<String, dynamic>;
            return User.fromJson(p);
          }).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Invalid response');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load contacts';
          _isLoading = false;
        });
      }
    }
  }

  void _toggleSelection(int userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _submit() async {
    if (_selectedUserIds.isEmpty) return;
    
    setState(() {
      _isSubmitting = true;
    });

    try {
      for (final userId in _selectedUserIds) {
        await _groupService.addMember(widget.groupId, userId);
      }
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add some members: $e')),
        );
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Members'),
      ),
      body: _buildBody(),
      floatingActionButton: _selectedUserIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text('Add ${_selectedUserIds.length}'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadPeers();
              },
              child: const Text('Retry'),
            )
          ],
        ),
      );
    }
    if (_peers.isEmpty) {
      return const Center(child: Text('No recent contacts found'));
    }

    return ListView.builder(
      itemCount: _peers.length,
      itemBuilder: (context, index) {
        final user = _peers[index];
        final isSelected = _selectedUserIds.contains(user.id);
        
        return ListTile(
          leading: UserAvatar(
            avatarUrl: user.avatar,
            username: user.username,
            radius: 20,
          ),
          title: Text(user.fullName ?? user.username),
          subtitle: Text('@${user.username}'),
          trailing: Checkbox(
            value: isSelected,
            onChanged: (val) => _toggleSelection(user.id),
          ),
          onTap: () => _toggleSelection(user.id),
        );
      },
    );
  }
}
