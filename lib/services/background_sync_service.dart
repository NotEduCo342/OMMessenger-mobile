import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/message.dart';
import 'notification_prefs.dart';
import 'notification_service.dart';

class BackgroundSyncService {
  static const _storage = FlutterSecureStorage();

  static Future<bool> run() async {
    try {
      final accessToken = await _storage.read(key: 'access_token');
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (accessToken == null || refreshToken == null) return true;

      final isForeground = await NotificationPrefs.isAppForeground();
      if (isForeground) return true;

      var token = accessToken;
      final userId = await NotificationPrefs.getCurrentUserId();
      if (userId == null) return true;

      Future<http.Response> authedPost(String endpoint, Map<String, dynamic> body) async {
        return http.post(
          Uri.parse('${AppConstants.baseUrl}$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        );
      }

      Future<http.Response> authedGet(String endpoint) async {
        return http.get(
          Uri.parse('${AppConstants.baseUrl}$endpoint'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        );
      }

      Future<bool> refresh() async {
        try {
          final resp = await http.post(
            Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': 'om_refresh=$refreshToken',
            },
          );
          if (resp.statusCode != 200) return false;
          final data = jsonDecode(resp.body);
          final newAccess = data['access_token'] as String?;
          final newRefresh = data['refresh_token'] as String?;
          if (newAccess != null && newAccess.isNotEmpty) {
            token = newAccess;
            await _storage.write(key: 'access_token', value: newAccess);
          }
          if (newRefresh != null && newRefresh.isNotEmpty) {
            await _storage.write(key: 'refresh_token', value: newRefresh);
          }
          return newAccess != null;
        } catch (_) {
          return false;
        }
      }

      Future<http.Response> retryOn401(Future<http.Response> Function() request) async {
        final response = await request();
        if (response.statusCode == 401) {
          final ok = await refresh();
          if (!ok) return response;
          return request();
        }
        return response;
      }

      final conversationIds = await NotificationPrefs.getConversationIds();
      if (conversationIds.isEmpty) {
        // Seed cursors without notifying.
        final convoResp = await retryOn401(() => authedGet('/conversations'));
        if (convoResp.statusCode >= 200 && convoResp.statusCode < 300) {
          final data = jsonDecode(convoResp.body) as Map<String, dynamic>;
          final convos = (data['conversations'] as List?) ?? [];
          for (final item in convos) {
            if (item is Map<String, dynamic>) {
              final conversationId = item['conversation_id'] as String?;
              final lastMessage = item['last_message'] as Map<String, dynamic>?;
              final lastId = (lastMessage?['id'] as int?) ?? 0;
              if (conversationId != null) {
                await NotificationPrefs.setCursor(conversationId, lastId);
                final isGroup = conversationId.startsWith('group_');
                final title = isGroup
                    ? (item['group']?['name'] as String? ?? 'Group')
                    : (item['peer']?['full_name'] as String? ?? item['peer']?['username'] as String? ?? 'User');
                await NotificationPrefs.setConversationMeta(conversationId, title: title, isGroup: isGroup);
              }
            }
          }
        }
        return true;
      }

      final cursors = await NotificationPrefs.getAllCursors();
      final conversationStates = <Map<String, dynamic>>[];
      for (final cid in conversationIds) {
        conversationStates.add({
          'conversation_id': cid,
          'last_message_id': cursors[cid] ?? 0,
        });
      }

      final syncResp = await retryOn401(() => authedPost('/messages/sync', {
            'limit': 50,
            'conversations': conversationStates,
          }));
      if (syncResp.statusCode < 200 || syncResp.statusCode >= 300) return true;

      final payload = jsonDecode(syncResp.body) as Map<String, dynamic>;
      final results = (payload['results'] as List?) ?? [];

      for (final entry in results) {
        if (entry is! Map<String, dynamic>) continue;
        final conversationId = entry['conversation_id'] as String?;
        if (conversationId == null) continue;

        final muted = await NotificationPrefs.isMuted(conversationId);
        final messages = (entry['messages'] as List?) ?? [];
        if (messages.isEmpty) continue;

        int maxId = cursors[conversationId] ?? 0;
        final newMessages = <Message>[];
        for (final item in messages) {
          if (item is Map<String, dynamic>) {
            final msg = Message.fromJson(item);
            if (msg.id > maxId) maxId = msg.id;
            if (msg.senderId != userId) {
              newMessages.add(msg);
            }
          }
        }
        await NotificationPrefs.setCursor(conversationId, maxId);

        if (muted || newMessages.isEmpty) continue;

        final meta = await NotificationPrefs.getConversationMeta(conversationId);
        final title = (meta?['title'] as String?) ?? 'New messages';
        final isGroup = (meta?['is_group'] as bool?) ?? conversationId.startsWith('group_');

        final latest = newMessages.last;
        final body = isGroup && latest.sender != null
            ? '${latest.sender!.username}: ${latest.content}'
            : latest.content;

        if (newMessages.length == 1) {
          await NotificationService.instance.showMessage(
            conversationId: conversationId,
            messageId: latest.id,
            title: title,
            body: body,
          );
        } else {
          await NotificationService.instance.showConversationSummary(
            conversationId: conversationId,
            title: title,
            body: body,
            messageCount: newMessages.length,
          );
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BackgroundSync] error: $e');
      }
      return true;
    }
  }
}
