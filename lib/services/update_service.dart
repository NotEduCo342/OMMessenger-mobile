import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/constants.dart';

/// Service to check for app updates
/// Compares current app version with server's latest version
class UpdateService {
  /// Check if a new version is available
  /// Returns: {needsUpdate: bool, latestVersion: String, currentVersion: String, updateUrl: String?, isForceUpdate: bool}
  Future<Map<String, dynamic>> checkForUpdate() async {
    try {
      // Get current app version from package info
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      // Call backend API to get latest version info
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/version'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final latestVersion = data['version'] as String;
        final latestBuildNumber = data['build_number'] as int;
        final downloadUrl = data['download_url'] as String?;
        final isForceUpdate = data['force_update'] as bool? ?? false;
        final changeLog = data['changelog'] as String?;

        // Compare build numbers (more reliable than version strings)
        final needsUpdate = latestBuildNumber > currentBuildNumber;

        return {
          'needsUpdate': needsUpdate,
          'latestVersion': latestVersion,
          'currentVersion': currentVersion,
          'latestBuildNumber': latestBuildNumber,
          'currentBuildNumber': currentBuildNumber,
          'downloadUrl': downloadUrl,
          'isForceUpdate': isForceUpdate,
          'changelog': changeLog,
        };
      }

      return _noUpdateResponse(currentVersion, currentBuildNumber);
    } catch (e) {
      print('Update check failed: $e');
      // If check fails, assume no update (fail silently)
      final packageInfo = await PackageInfo.fromPlatform();
      return _noUpdateResponse(
        packageInfo.version,
        int.tryParse(packageInfo.buildNumber) ?? 0,
      );
    }
  }

  Map<String, dynamic> _noUpdateResponse(String version, int buildNumber) {
    return {
      'needsUpdate': false,
      'latestVersion': version,
      'currentVersion': version,
      'latestBuildNumber': buildNumber,
      'currentBuildNumber': buildNumber,
      'downloadUrl': null,
      'isForceUpdate': false,
      'changelog': null,
    };
  }
}
