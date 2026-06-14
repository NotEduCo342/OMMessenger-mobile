import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/group_service.dart';
import '../models/group.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _handleController = TextEditingController();
  bool _isPublic = false;
  bool _isSubmitting = false;
  String? _error;
  File? _avatarFile;

  bool _isCheckingHandle = false;
  bool? _isHandleAvailable;
  String? _handleError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _handleController.addListener(_onHandleChanged);
  }

  void _onHandleChanged() {
    if (!_isPublic) return;

    final handle = _handleController.text.trim();
    setState(() {
      _isHandleAvailable = null;
      _handleError = null;
    });

    if (handle.isEmpty) return;

    if (!RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(handle)) {
      setState(() {
        _handleError = 'Invalid handle format';
      });
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isCheckingHandle = true);

      final isAvailable = await GroupService().checkGroupHandleAvailability(handle);

      if (mounted) {
        setState(() {
          _isCheckingHandle = false;
          _isHandleAvailable = isAvailable;
          if (!isAvailable) {
            _handleError = 'Handle is taken';
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _handleController.removeListener(_onHandleChanged);
    _handleController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _avatarFile = File(picked.path);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isPublic && _isHandleAvailable != true) {
      setState(() {
        _handleError = 'Please choose a valid handle';
      });
      return;
    }
    
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final service = GroupService();
      Group group = await service.createGroup(
        name: _nameController.text,
        description: _descriptionController.text,
        isPublic: _isPublic,
        handle: _handleController.text,
      );

      if (_avatarFile != null) {
        group = await service.uploadGroupAvatar(group.id, _avatarFile!.path);
      }

      if (!mounted) return;
      Navigator.pop(context, group);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to create group';
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
        title: const Text('Create Group'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        backgroundImage: _avatarFile != null ? FileImage(_avatarFile!) : null,
                        child: _avatarFile == null
                            ? const Icon(Icons.group, size: 50, color: Colors.grey)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: IconButton(
                            tooltip: 'Set group avatar',
                            icon: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                            onPressed: _pickAvatar,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Group name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  title: const Text('Public group'),
                  subtitle: const Text('Allow others to find by handle'),
                  value: _isPublic,
                  onChanged: (value) {
                    setState(() {
                      _isPublic = value;
                    });
                  },
                ),
                if (_isPublic) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _handleController,
                    decoration: InputDecoration(
                      labelText: 'Handle (e.g. omdevs)',
                      border: const OutlineInputBorder(),
                      suffixIcon: _isCheckingHandle
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _isHandleAvailable != null
                              ? Icon(
                                  _isHandleAvailable! ? Icons.check_circle : Icons.cancel,
                                  color: _isHandleAvailable! ? Colors.green : Colors.red,
                                )
                              : null,
                      errorText: _handleError,
                    ),
                    validator: (value) {
                      if (!_isPublic) return null;
                      if (value == null || value.trim().isEmpty) {
                        return 'Handle is required for public groups';
                      }
                      if (_handleError != null) return _handleError;
                      return null;
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Group'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
