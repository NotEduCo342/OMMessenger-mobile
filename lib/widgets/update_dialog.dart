import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateDialog extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? changelog;
  final bool isForceUpdate;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    this.downloadUrl,
    this.changelog,
    this.isForceUpdate = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isForceUpdate, // Prevent dismissal if force update
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              isForceUpdate ? Icons.warning : Icons.system_update,
              color: isForceUpdate ? Colors.orange : Colors.blue,
            ),
            const SizedBox(width: 8),
            Text(isForceUpdate ? 'Update Required' : 'Update Available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of OM Messenger is available!',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Version:',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                Text(
                  currentVersion,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Latest Version:',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                Text(
                  latestVersion,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            if (changelog != null) ...[
              const SizedBox(height: 16),
              const Text(
                'What\'s New:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  changelog!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ],
            if (isForceUpdate) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This update is required to continue using the app.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!isForceUpdate)
            TextButton(
              onPressed: () async {
                // Store reminder timestamp (remind in 24 hours)
                final prefs = await SharedPreferences.getInstance();
                final remindAt = DateTime.now().add(const Duration(hours: 24));
                await prefs.setString('update_remind_at', remindAt.toIso8601String());
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Remind Me Later'),
            ),
          ElevatedButton(
            onPressed: () async {
              if (downloadUrl != null) {
                try {
                  final uri = Uri.parse(downloadUrl!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                    
                    // Clear reminder after successful download
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('update_remind_at');
                    
                    if (!isForceUpdate && context.mounted) {
                      Navigator.pop(context);
                    }
                  } else {
                    // URL cannot be launched
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cannot open download link. Please contact support.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  // Error launching URL
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error opening download: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } else {
                // No download URL provided
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Download URL not available. Please check later.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isForceUpdate ? Colors.orange : null,
            ),
            child: const Text('Download Update'),
          ),
        ],
      ),
    );
  }
}
