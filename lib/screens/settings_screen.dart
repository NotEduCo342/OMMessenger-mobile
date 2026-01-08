import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/user_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _imagePicker = ImagePicker();

  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameErrorText;
  bool _didInitControllers = false;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _isDeletingAvatar = false;

  // Debounce to avoid spamming the server while typing.
  // (No timers/animations beyond this simple UX.)
  static const _usernameDebounce = Duration(milliseconds: 350);
  Future<void>? _pendingUsernameCheck;

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _syncFromUser() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    _fullNameController.text = user.fullName;
    _usernameController.text = user.username;
    _isUsernameAvailable = null;
    _usernameErrorText = null;
  }

  String _normalizedUsernameInput(String raw) {
    // Mirror backend normalization as closely as possible without duplicating
    // all validation logic.
    return raw.trim().toLowerCase();
  }

  Future<void> _checkUsernameAvailability() async {
    final auth = context.read<AuthProvider>();
    final currentUser = auth.user;
    if (currentUser == null) return;

    final raw = _usernameController.text;
    final username = _normalizedUsernameInput(raw);

    if (username.isEmpty) {
      setState(() {
        _isUsernameAvailable = null;
        _usernameErrorText = 'Username is required';
      });
      return;
    }

    // If unchanged, treat as valid/available.
    if (username == currentUser.username) {
      setState(() {
        _isUsernameAvailable = true;
        _usernameErrorText = null;
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameErrorText = null;
      _isUsernameAvailable = null;
    });

    try {
      final available = await auth.checkUsernameAvailability(username);
      if (!mounted) return;
      setState(() {
        _isUsernameAvailable = available;
        _usernameErrorText = available ? null : 'Username is already taken';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
        });
      }
    }
  }

  void _onUsernameChanged(String _) {
    final pending = _pendingUsernameCheck;
    _pendingUsernameCheck = Future<void>.delayed(_usernameDebounce).then((_) async {
      if (!mounted) return;
      if (identical(_pendingUsernameCheck, pending)) {
        // Another keystroke replaced this one.
        return;
      }
      await _checkUsernameAvailability();
    });
  }

  bool _canSave() {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return false;
    if (_isSaving || _isCheckingUsername) return false;

    final nextFullName = _fullNameController.text.trim();
    final nextUsername = _normalizedUsernameInput(_usernameController.text);

    final changed = (nextFullName.isNotEmpty && nextFullName != user.fullName) ||
        (nextUsername.isNotEmpty && nextUsername != user.username);
    if (!changed) return false;

    if (nextUsername.isEmpty) return false;
    if (_usernameErrorText != null) return false;
    if (nextUsername != user.username && _isUsernameAvailable != true) return false;

    return true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_canSave()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      final auth = context.read<AuthProvider>();
      final nextFullName = _fullNameController.text.trim();
      final nextUsername = _normalizedUsernameInput(_usernameController.text);

      await auth.updateProfile(
        fullName: nextFullName,
        username: nextUsername,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );

      // Re-sync in case server normalizes further.
      _syncFromUser();
      setState(() {
        _didInitControllers = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;
    if (_isUploadingAvatar) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() {
        _isUploadingAvatar = true;
      });

      await auth.uploadAvatar(picked.path);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Avatar upload failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _confirmAndDeleteAvatar() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;
    if (_isDeletingAvatar || _isUploadingAvatar) return;
    if (user.avatar.trim().isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove photo'),
        content: const Text('Remove your profile photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() {
      _isDeletingAvatar = true;
    });

    try {
      await auth.deleteAvatar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar removed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remove failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingAvatar = false;
        });
      }
    }
  }

  Widget _buildProfileAvatar(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final radius = 50.0;

    return UserAvatar(
      username: user?.username ?? '',
      avatarUrl: user?.avatar ?? '',
      radius: radius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final themeProvider = context.watch<ThemeProvider>();

    if (!_didInitControllers && user != null) {
      _didInitControllers = true;
      _syncFromUser();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Profile section
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    GestureDetector(
                      onTap: user == null || _isUploadingAvatar
                          ? null
                          : _pickAndUploadAvatar,
                      child: _buildProfileAvatar(context),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        shape: const CircleBorder(),
                        child: IconButton(
                          iconSize: 20,
                          onPressed: user == null || _isUploadingAvatar
                              ? null
                              : _pickAndUploadAvatar,
                          icon: _isUploadingAvatar
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_camera_outlined),
                          tooltip: 'Change avatar',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if ((user?.avatar ?? '').trim().isNotEmpty)
                  TextButton(
                    onPressed: user == null || _isUploadingAvatar || _isDeletingAvatar
                        ? null
                        : _confirmAndDeleteAvatar,
                    child: _isDeletingAvatar
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Remove photo'),
                  ),
                Text(
                  user?.fullName ?? user?.username ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${user?.username ?? 'unknown'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Information editor
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Profile',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _fullNameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          hintText: 'Your name',
                        ),
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty) return null; // optional
                          if (v.length > 80) return 'Keep it under 80 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          prefixText: '@',
                          errorText: _usernameErrorText,
                          suffixIcon: _isCheckingUsername
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : _isUsernameAvailable == true
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : _isUsernameAvailable == false
                                      ? const Icon(Icons.cancel, color: Colors.red)
                                      : null,
                          helperText: 'This is what people can search for',
                        ),
                        onChanged: (v) {
                          // Keep UI responsive; check availability in the background.
                          setState(() {
                            _usernameErrorText = null;
                            _isUsernameAvailable = null;
                          });
                          _onUsernameChanged(v);
                        },
                        validator: (value) {
                          final v = _normalizedUsernameInput(value ?? '');
                          if (v.isEmpty) return 'Username is required';
                          if (v.length < 3) return 'At least 3 characters';
                          if (v.length > 32) return 'Keep it under 32 characters';
                          return null;
                        },
                        onFieldSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: user == null || _isSaving
                                  ? null
                                  : () {
                                      FocusScope.of(context).unfocus();
                                      setState(() {
                                        _syncFromUser();
                                      });
                                    },
                              child: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _canSave() ? _save : null,
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Theme section
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(
              themeProvider.themeMode == AppThemeMode.system
                  ? 'System'
                  : themeProvider.themeMode == AppThemeMode.dark
                      ? 'Dark'
                      : 'Light',
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const _ThemeDialog(),
              );
            },
          ),
          const Divider(height: 1),
          // Account section
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Account'),
            subtitle: Text(user?.email ?? ''),
          ),
          const Divider(height: 1),
          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        context.read<AuthProvider>().logout();
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: const Text('Logout', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeDialog extends StatelessWidget {
  const _ThemeDialog();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return AlertDialog(
      title: const Text('Choose Theme'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<AppThemeMode>(
            title: const Text('Light'),
            value: AppThemeMode.light,
            groupValue: themeProvider.themeMode,
            onChanged: (value) {
              if (value != null) {
                themeProvider.setThemeMode(value);
                Navigator.pop(context);
              }
            },
          ),
          RadioListTile<AppThemeMode>(
            title: const Text('Dark'),
            value: AppThemeMode.dark,
            groupValue: themeProvider.themeMode,
            onChanged: (value) {
              if (value != null) {
                themeProvider.setThemeMode(value);
                Navigator.pop(context);
              }
            },
          ),
          RadioListTile<AppThemeMode>(
            title: const Text('System'),
            value: AppThemeMode.system,
            groupValue: themeProvider.themeMode,
            onChanged: (value) {
              if (value != null) {
                themeProvider.setThemeMode(value);
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
