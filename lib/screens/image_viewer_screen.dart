import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'dart:io';
import 'dart:math' as math;

class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final bool showRotateButton;

  const ImageViewerScreen({super.key, required this.imageUrl, this.showRotateButton = true});

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  static const _storage = FlutterSecureStorage();
  late final PhotoViewController _photoViewController;
  String? _accessToken;
  bool _isLoadingToken = true;
  double _rotation = 0.0;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    _loadToken();
  }

  @override
  void dispose() {
    _photoViewController.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (mounted) {
        setState(() {
          _accessToken = token;
          _isLoadingToken = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingToken = false;
        });
      }
    }
  }

  void _rotateImage() {
    _rotation += math.pi / 2;
    _photoViewController.rotation = _rotation;
  }

  Future<void> _saveImage() async {
    try {
      final headers = _accessToken != null ? <String, String>{'Authorization': 'Bearer $_accessToken'} : null;
      final response = await http.get(Uri.parse(widget.imageUrl), headers: headers);
      
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        
        if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
          final downloadsDir = await getDownloadsDirectory();
          if (downloadsDir != null) {
            final omDir = Directory('${downloadsDir.path}/OMMessenger');
            if (!await omDir.exists()) {
              await omDir.create(recursive: true);
            }
            final uri = Uri.parse(widget.imageUrl);
            final filename = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final file = File('${omDir.path}/$filename');
            await file.writeAsBytes(bytes);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Saved to Downloads/OMMessenger/$filename')),
              );
            }
          }
        } else if (Platform.isAndroid || Platform.isIOS) {
          final hasAccess = await Gal.hasAccess();
          if (!hasAccess) {
            await Gal.requestAccess();
          }
          await Gal.putImageBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Saved to Gallery')),
            );
          }
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (mounted) {
            Navigator.pop(context);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (widget.showRotateButton)
            IconButton(
              icon: const Icon(Icons.rotate_right),
              tooltip: 'Rotate',
              onPressed: _rotateImage,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'save') {
                _saveImage();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'save',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 20, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Save Image'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoadingToken
          ? const Center(child: CircularProgressIndicator())
          : PhotoView(
              controller: _photoViewController,
              imageProvider: CachedNetworkImageProvider(
                widget.imageUrl,
                headers: _accessToken != null ? {'Authorization': 'Bearer $_accessToken'} : null,
              ),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              heroAttributes: PhotoViewHeroAttributes(tag: widget.imageUrl),
              customSize: MediaQuery.of(context).size,
              basePosition: Alignment.center,
              backgroundDecoration: const BoxDecoration(
                color: Colors.black,
              ),
            ),
      ),
    );
  }
}
