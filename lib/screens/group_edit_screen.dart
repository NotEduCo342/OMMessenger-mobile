import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/auth_provider.dart';
import '../services/group_service.dart';
import '../models/group.dart';

class GroupEditScreen extends StatefulWidget {
  final Group group;
  const GroupEditScreen({super.key, required this.group});

  @override
  State<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _GroupEditScreenState extends State<GroupEditScreen> {
  static const _storage = FlutterSecureStorage();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _handleController;
  late bool _isPublic;
  bool _isSubmitting = false;
  String? _error;
  File? _avatarFile;
  String? _accessToken;

  bool _isCheckingHandle = false;
  bool? _isHandleAvailable;
  String? _handleError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _descriptionController = TextEditingController(text: widget.group.description);
    _handleController = TextEditingController(text: widget.group.handle ?? '');
    _isPublic = widget.group.isPublic;
    _isHandleAvailable = widget.group.isPublic ? true : null;
    _handleController.addListener(_onHandleChanged);
    _loadToken();
  }

  void _onHandleChanged() {
    if (!_isPublic) return;

    final handle = _handleController.text.trim();
    setState(() {
      _isHandleAvailable = null;
      _handleError = null;
    });

    if (handle.isEmpty) return;

    if (handle.toLowerCase() == widget.group.handle?.toLowerCase()) {
      setState(() {
        _isHandleAvailable = true;
      });
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(handle)) {
      setState(() {
        _handleError = 'Invalid handle format';
      });
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isCheckingHandle = true);

      final isAvailable = await context.read<AuthProvider>().checkUsernameAvailability(handle);

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

  Future<void> _loadToken() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (mounted) {
        setState(() {
          _accessToken = token;
        });
      }
    } catch (_) {}
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
      Group group = await service.updateGroup(
        widget.group.id,
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
        _error = 'Failed to update group';
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
        title: const Text('Edit Group'),
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
                        backgroundImage: _avatarFile != null
                            ? FileImage(_avatarFile!)
                            : (widget.group.icon.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    widget.group.icon,
                                    headers: _accessToken != null ? {'Authorization': 'Bearer $_accessToken'} : null,
                                  )
                                : null) as ImageProvider?,
                        child: _avatarFile == null && widget.group.icon.isEmpty
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
                      if (_isPublic) {
                        _onHandleChanged();
                      }
                    });
                  },
                ),
                if (_isPublic) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _handleController,
                    decoration: InputDecoration(
                      labelText: 'Group handle',
                      prefixText: '@',
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
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
