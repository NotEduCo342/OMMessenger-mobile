import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const AuthImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  static const _storage = FlutterSecureStorage();
  static String? _cachedToken;
  static bool _tokenLoaded = false;

  String? _accessToken;

  @override
  void initState() {
    super.initState();
    _accessToken = _cachedToken;
    if (!_tokenLoaded) {
      _loadToken();
    }
  }

  Future<void> _loadToken() async {
    try {
      final token = await _storage.read(key: 'access_token');
      _cachedToken = token;
      _tokenLoaded = true;
      if (!mounted) return;
      setState(() {
        _accessToken = token;
      });
    } catch (_) {
      _tokenLoaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.trim().isEmpty) {
      return widget.errorWidget ?? const Icon(Icons.broken_image, size: 100);
    }

    if (_accessToken == null && !_tokenLoaded) {
      return widget.placeholder ??
          const Center(child: CircularProgressIndicator());
    }

    final headers = <String, String>{};
    if (_accessToken != null && _accessToken!.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_accessToken!}';
    }

    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      httpHeaders: headers.isEmpty ? null : headers,
      fit: widget.fit,
      placeholder: (context, url) =>
          widget.placeholder ??
          const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) =>
          widget.errorWidget ?? const Icon(Icons.broken_image, size: 100),
    );
  }
}
