import '../models/group.dart';
import 'api_service.dart';

class GroupService {
  final ApiService _api = ApiService();

  Future<Group> createGroup({
    required String name,
    String? description,
    bool isPublic = false,
    String? handle,
  }) async {
    final body = {
      'name': name.trim(),
      'description': (description ?? '').trim(),
      'is_public': isPublic,
      if (isPublic) 'handle': (handle ?? '').trim(),
    };

    final response = await _api.post('/groups', body);
    if (response is Map<String, dynamic>) {
      return Group.fromJson(response);
    }
    throw Exception('Failed to create group');
  }

  Future<Group> joinByHandle(String handle) async {
    final response = await _api.post('/groups/handle/${handle.trim()}/join', {});
    if (response is Map<String, dynamic>) {
      return Group.fromJson(response);
    }
    throw Exception('Failed to join group by handle');
  }

  Future<Group> joinByInviteToken(String token) async {
    final response = await _api.post('/join/${token.trim()}', {});
    if (response is Map<String, dynamic>) {
      return Group.fromJson(response);
    }
    throw Exception('Failed to join group by invite');
  }

  Future<List<Group>> searchPublicGroups(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final response = await _api.get('/groups/public/search?q=$trimmed&limit=$limit');
    if (response is Map && response['groups'] is List) {
      final list = response['groups'] as List;
      return list.map((json) => Group.fromJson(Map<String, dynamic>.from(json))).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> previewInviteToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw Exception('Invalid invite token');
    }
    final response = await _api.get('/join/$trimmed');
    if (response is Map<String, dynamic>) {
      return response;
    }
    throw Exception('Failed to preview invite');
  }

  Future<List<dynamic>> getGroupMembers(int groupId) async {
    final response = await _api.get('/groups/$groupId/members');
    if (response is List) return response;
    if (response is Map && response['members'] is List) {
      return response['members'] as List;
    }
    return [];
  }

  Future<void> leaveGroup(int groupId) async {
    await _api.post('/groups/$groupId/leave', {});
  }

  Future<Map<String, dynamic>> createInviteLink(
    int groupId, {
    bool singleUse = false,
    int? expiresInSeconds,
  }) async {
    final body = {
      'single_use': singleUse,
      if (expiresInSeconds != null && expiresInSeconds > 0)
        'expires_in_seconds': expiresInSeconds,
    };
    final response = await _api.post('/groups/$groupId/invite-links', body);
    if (response is Map<String, dynamic>) {
      return response;
    }
    throw Exception('Failed to create invite link');
  }
}
