import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserAvatar extends StatefulWidget {
  final String username;
  final String avatarUrl;
  final double radius;
  final bool showProgress;

  const UserAvatar({
    super.key,
    required this.username,
    required this.avatarUrl,
    required this.radius,
    this.showProgress = true,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  static const _storage = FlutterSecureStorage();
  String? _accessToken;
  final Set<String> _loggedErrorsForUrl = <String>{};

  void _dlog(String message) {
    if (!kDebugMode) return;
    debugPrint('[UserAvatar] $message');
  }

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (!mounted) return;
      setState(() {
        _accessToken = token;
      });
      _dlog('token loaded: ${token == null ? 'none' : 'len=${token.length}'}');
    } catch (_) {
      // best-effort
      _dlog('token load failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primary;
    final fallbackLetter =
        widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?';

    if (widget.avatarUrl.trim().isEmpty) {
      _dlog('no avatarUrl; showing fallback');
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg,
        child: Text(
          fallbackLetter,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: widget.radius * 0.85,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    // Avoid firing an unauthenticated request before we know if we have a token.
    if (_accessToken == null) {
      _dlog('avatarUrl present but token not loaded yet; waiting');
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg,
        child: widget.showProgress
            ? SizedBox(
                width: widget.radius * 0.55,
                height: widget.radius * 0.55,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : Text(
                fallbackLetter,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: widget.radius * 0.85,
                  fontWeight: FontWeight.w600,
                ),
              ),
      );
    }

    final headers = <String, String>{};
    if (_accessToken != null && _accessToken!.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_accessToken!}';
    }

    _dlog('loading image url=${widget.avatarUrl} authHeader=${headers.containsKey('Authorization')}');

    return CachedNetworkImage(
      imageUrl: widget.avatarUrl,
      httpHeaders: headers.isEmpty ? null : headers,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: widget.radius,
        backgroundImage: imageProvider,
        backgroundColor: bg,
      ),
      placeholder: !widget.showProgress
          ? null
          : (context, url) => CircleAvatar(
                radius: widget.radius,
                backgroundColor: bg,
                child: SizedBox(
                  width: widget.radius * 0.55,
                  height: widget.radius * 0.55,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
      errorWidget: (context, url, error) {
        if (_loggedErrorsForUrl.add(url)) {
          _dlog('image error url=$url error=$error');
        }
        return CircleAvatar(
          radius: widget.radius,
          backgroundColor: bg,
          child: Text(
            fallbackLetter,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontSize: widget.radius * 0.85,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
