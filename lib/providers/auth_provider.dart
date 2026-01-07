import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final _storage = const FlutterSecureStorage();
  
  User? _user;
  bool _isLoading = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

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

  Future<void> _handleAuthResponse(dynamic response) async {
    // Save tokens
    await _storage.write(key: 'access_token', value: response['access_token']);
    await _storage.write(key: 'refresh_token', value: response['refresh_token']);
    
    // Set user
    _user = User.fromJson(response['user']);
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    _user = null;
    notifyListeners();
  }
}
