import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primary;
    final fallbackLetter = username.isNotEmpty ? username[0].toUpperCase() : '?';

    if (avatarUrl.trim().isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          fallbackLetter,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: radius * 0.85,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: avatarUrl,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
        backgroundColor: bg,
      ),
      placeholder: !showProgress
          ? null
          : (context, url) => CircleAvatar(
                radius: radius,
                backgroundColor: bg,
                child: SizedBox(
                  width: radius * 0.55,
                  height: radius * 0.55,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
      errorWidget: (context, url, error) => CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          fallbackLetter,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: radius * 0.85,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
