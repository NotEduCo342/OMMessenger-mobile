import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPrefs {
  static const _cursorsKey = 'sync_cursors';
  static const _conversationsKey = 'sync_conversations';
  static const _conversationMetaKey = 'sync_conversation_meta';
  static const _mutedKey = 'muted_conversations';
  static const _currentUserIdKey = 'current_user_id';
  static const _appForegroundKey = 'app_foreground';

  static Future<void> setCurrentUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentUserIdKey, userId);
  }

  static Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentUserIdKey);
  }

  static Future<void> setCursor(String conversationId, int lastMessageId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap(prefs, _cursorsKey);
    final existing = map[conversationId] as int? ?? 0;
    if (lastMessageId > existing) {
      map[conversationId] = lastMessageId;
      await prefs.setString(_cursorsKey, jsonEncode(map));
    }
  }

  static Future<int> getCursor(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap(prefs, _cursorsKey);
    return (map[conversationId] as int?) ?? 0;
  }

  static Future<Map<String, int>> getAllCursors() async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap(prefs, _cursorsKey);
    return map.map((key, value) => MapEntry(key, (value as int?) ?? 0));
  }

  static Future<void> setConversationMeta(
    String conversationId, {
    required String title,
    required bool isGroup,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap(prefs, _conversationMetaKey);
    map[conversationId] = {
      'title': title,
      'is_group': isGroup,
    };
    await prefs.setString(_conversationMetaKey, jsonEncode(map));

    final convos = await _loadList(prefs, _conversationsKey);
    if (!convos.contains(conversationId)) {
      convos.add(conversationId);
      await prefs.setString(_conversationsKey, jsonEncode(convos));
    }
  }

  static Future<Map<String, dynamic>?> getConversationMeta(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap(prefs, _conversationMetaKey);
    final meta = map[conversationId];
    if (meta is Map) {
      return Map<String, dynamic>.from(meta);
    }
    return null;
  }

  static Future<List<String>> getConversationIds() async {
    final prefs = await SharedPreferences.getInstance();
    return await _loadList(prefs, _conversationsKey);
  }

  static Future<void> setMuted(String conversationId, bool muted) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap(prefs, _mutedKey);
    if (muted) {
      map[conversationId] = true;
    } else {
      map.remove(conversationId);
    }
    await prefs.setString(_mutedKey, jsonEncode(map));
  }

  static Future<bool> isMuted(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap(prefs, _mutedKey);
    return map[conversationId] == true;
  }

  static Future<Map<String, bool>> getMutedMap() async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _loadMap(prefs, _mutedKey);
    return map.map((key, value) => MapEntry(key, value == true));
  }

  static Future<void> setAppForeground(bool isForeground) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appForegroundKey, isForeground);
  }

  static Future<bool> isAppForeground() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_appForegroundKey) ?? false;
  }

  static Future<Map<String, dynamic>> _loadMap(SharedPreferences prefs, String key) async {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  static Future<List<String>> _loadList(SharedPreferences prefs, String key) async {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String>[];
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
    return <String>[];
  }
}
