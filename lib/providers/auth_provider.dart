import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final _storage = const FlutterSecureStorage();

  static const _meUserCacheKey = 'cache_me_user_json';
  static const _meUserEtagKey = 'cache_me_etag';
  
  User? _user;
  bool _isLoading = false;
  bool _isRestoring = false;
  bool _didRestoreAttempt = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  bool get isRestoring => _isRestoring;

  Future<User?> _loadCachedMeUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_meUserCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return User.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadCachedMeEtag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_meUserEtagKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedMe(User user, {String? etag}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_meUserCacheKey, jsonEncode(user.toJson()));
      if (etag != null && etag.trim().isNotEmpty) {
        await prefs.setString(_meUserEtagKey, etag);
      } else {
        await prefs.remove(_meUserEtagKey);
      }
    } catch (_) {
      // best-effort cache
    }
  }

  Future<void> _refreshMeAndCache() async {
    try {
      final response = await _apiService.getResponse('/users/me');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return;
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['user'] != null) {
          _user = User.fromJson(Map<String, dynamic>.from(decoded['user']));
          await _saveCachedMe(
            _user!,
            etag: response.headers['etag'],
          );
          notifyListeners();
        }
      }
    } catch (_) {
      // best-effort
    }
  }

  /// Attempt to restore an existing session (app restart).
  /// Safe to call multiple times; it will only run once.
  Future<void> restoreSession() async {
    if (_didRestoreAttempt) return;
    _didRestoreAttempt = true;

    _isRestoring = true;
    // Avoid notifying synchronously during widget build.
    Future.microtask(notifyListeners);

    User? cachedUser;
    try {
      final accessToken = await _storage.read(key: 'access_token');
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (accessToken == null || refreshToken == null) {
        _user = null;
        return;
      }

      // Warm-start: load cached profile immediately (best-effort), then
      // revalidate cheaply via ETag.
      cachedUser = await _loadCachedMeUser();
      if (cachedUser != null && _user == null) {
        _user = cachedUser;
        Future.microtask(notifyListeners);
      }

      final cachedEtag = await _loadCachedMeEtag();

      // Fetch current user; ApiService will refresh tokens on 401.
      final response = await _apiService.getResponse(
        '/users/me',
        extraHeaders: {
          if (cachedEtag != null && cachedEtag.trim().isNotEmpty)
            'If-None-Match': cachedEtag.trim(),
        },
      );

      if (response.statusCode == 304) {
        // Profile unchanged; keep cached user.
        if (_user == null) {
          _user = cachedUser;
        }
        return;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) {
          _user = null;
          return;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['user'] != null) {
          _user = User.fromJson(Map<String, dynamic>.from(decoded['user']));
          await _saveCachedMe(
            _user!,
            etag: response.headers['etag'],
          );
        } else {
          _user = null;
        }
        return;
      }

      // Any other status: keep cached user if we have one; otherwise log out.
      _user ??= cachedUser;
    } catch (_) {
      // If restoration fails, keep cached user if we have one.
      _user ??= cachedUser;
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.post('/auth/login', {
        'email': email,
        'password': password,
      });

      await _handleAuthResponse(response);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(String username, String email, String password, String fullName) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.post('/auth/register', {
        'username': username,
        'email': email,
        'password': password,
        'full_name': fullName,
      });

      await _handleAuthResponse(response);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> checkUsernameAvailability(String username) async {
    try {
      final response = await _apiService.get('/users/check-username?username=$username');
      return response['available'] ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<User?> updateProfile({String? username, String? fullName}) async {
    if (_user == null) return null;

    final nextUsername = username?.trim();
    final nextFullName = fullName?.trim();

    final Map<String, dynamic> body = {};
    if (nextUsername != null && nextUsername.isNotEmpty && nextUsername != _user!.username) {
      body['username'] = nextUsername;
    }
    if (nextFullName != null && nextFullName.isNotEmpty && nextFullName != _user!.fullName) {
      body['full_name'] = nextFullName;
    }

    if (body.isEmpty) return _user;

    _isLoading = true;
    notifyListeners();
    try {
      final response = await _apiService.put('/users/me', body);
      if (response is Map && response['user'] != null) {
        _user = User.fromJson(Map<String, dynamic>.from(response['user']));
        await _saveCachedMe(_user!, etag: null);
        await _refreshMeAndCache();
        return _user;
      }
      throw Exception('Invalid response from server');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _handleAuthResponse(dynamic response) async {
    // Save tokens
    await _storage.write(key: 'access_token', value: response['access_token']);
    await _storage.write(key: 'refresh_token', value: response['refresh_token']);
    
    // Set user
    _user = User.fromJson(response['user']);

    // Cache immediately (etag unknown until next /users/me GET)
    if (_user != null) {
      await _saveCachedMe(_user!, etag: null);
    }
  }

  Future<User?> uploadAvatar(String filePath) async {
    if (_user == null) return null;

    _isLoading = true;
    notifyListeners();
    try {
      final response = await _apiService.postMultipartFile(
        '/users/me/avatar',
        fieldName: 'avatar',
        filePath: filePath,
      );

      if (response is Map && response['user'] != null) {
        _user = User.fromJson(Map<String, dynamic>.from(response['user']));
        await _saveCachedMe(_user!, etag: null);
        await _refreshMeAndCache();
        return _user;
      }
      throw Exception('Invalid response from server');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<User?> deleteAvatar() async {
    if (_user == null) return null;

    _isLoading = true;
    notifyListeners();
    try {
      final response = await _apiService.delete('/users/me/avatar');
      if (response is Map && response['user'] != null) {
        _user = User.fromJson(Map<String, dynamic>.from(response['user']));
        await _saveCachedMe(_user!, etag: null);
        await _refreshMeAndCache();
        return _user;
      }
      throw Exception('Invalid response from server');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_meUserCacheKey);
      await prefs.remove(_meUserEtagKey);
    } catch (_) {
      // ignore
    }
    _user = null;
    notifyListeners();
  }
}
