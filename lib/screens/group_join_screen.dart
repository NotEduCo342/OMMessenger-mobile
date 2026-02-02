import 'package:flutter/material.dart';
import '../services/group_service.dart';
import '../models/group.dart';

class GroupJoinScreen extends StatefulWidget {
  const GroupJoinScreen({super.key});

  @override
  State<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

class _GroupJoinScreenState extends State<GroupJoinScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _handleController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _handleController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _joinByHandle() async {
    final handle = _handleController.text.trim();
    if (handle.isEmpty) {
      setState(() => _error = 'Handle is required');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final service = GroupService();
      final group = await service.joinByHandle(handle);
      if (!mounted) return;
      Navigator.pop(context, group);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to join by handle';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _joinByInvite() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Invite token is required');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final service = GroupService();
      final group = await service.joinByInviteToken(token);
      if (!mounted) return;
      Navigator.pop(context, group);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to join by invite';
      });
    } finally {
      if (mounted) {
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
        title: const Text('Join Group'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Handle'),
            Tab(text: 'Invite'),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TabBarView(
            controller: _tabController,
            children: [
              _JoinByHandle(
                controller: _handleController,
                isSubmitting: _isSubmitting,
                error: _error,
                onSubmit: _joinByHandle,
              ),
              _JoinByInvite(
                controller: _tokenController,
                isSubmitting: _isSubmitting,
                error: _error,
                onSubmit: _joinByInvite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinByHandle extends StatelessWidget {
  final TextEditingController controller;
  final bool isSubmitting;
  final String? error;
  final VoidCallback onSubmit;

  const _JoinByHandle({
    required this.controller,
    required this.isSubmitting,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Group handle',
            border: OutlineInputBorder(),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: isSubmitting ? null : onSubmit,
          child: isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join by Handle'),
        ),
      ],
    );
  }
}

class _JoinByInvite extends StatelessWidget {
  final TextEditingController controller;
  final bool isSubmitting;
  final String? error;
  final VoidCallback onSubmit;

  const _JoinByInvite({
    required this.controller,
    required this.isSubmitting,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Invite token',
            border: OutlineInputBorder(),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: isSubmitting ? null : onSubmit,
          child: isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join by Invite'),
        ),
      ],
    );
  }
}
