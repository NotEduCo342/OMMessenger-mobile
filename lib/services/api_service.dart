import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/constants.dart';

class ApiService {
  final _storage = const FlutterSecureStorage();
  bool _isRefreshing = false;

  Future<Map<String, String>> _getHeaders() async {
    String? token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    String? token = await _storage.read(key: 'access_token');
    return {
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String endpoint) async {
    final response = await getResponse(endpoint);
    return _handleResponse(response);
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await _makeRequestResponse(() => http.post(
      Uri.parse('${AppConstants.baseUrl}$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    ));

    return _handleResponse(response);
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await _makeRequestResponse(() => http.put(
      Uri.parse('${AppConstants.baseUrl}$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    ));

    return _handleResponse(response);
  }

  Future<dynamic> delete(String endpoint) async {
    final headers = await _getHeaders();
    final response = await _makeRequestResponse(() => http.delete(
      Uri.parse('${AppConstants.baseUrl}$endpoint'),
      headers: headers,
    ));

    return _handleResponse(response);
  }

  /// Like [get] but returns the raw HTTP response so callers can inspect
  /// headers/status codes (e.g. ETag + 304 handling).
  Future<http.Response> getResponse(
    String endpoint, {
    Map<String, String>? extraHeaders,
  }) async {
    final headers = await _getHeaders();
    final merged = {
      ...headers,
      if (extraHeaders != null) ...extraHeaders,
    };

    return _makeRequestResponse(() => http.get(
          Uri.parse('${AppConstants.baseUrl}$endpoint'),
          headers: merged,
        ));
  }

  /// Upload a single file using multipart/form-data.
  ///
  /// Intended for endpoints like POST /users/me/avatar where the server
  /// validates content via magic bytes (so we don't need to pre-guess MIME).
  Future<dynamic> postMultipartFile(
    String endpoint, {
    required String fieldName,
    required String filePath,
    String? filename,
  }) async {
    final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');

    Future<http.Response> sendOnce() async {
      final authHeaders = await _getAuthHeaders();
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(authHeaders);

      final safeFilename =
          (filename != null && filename.trim().isNotEmpty)
              ? filename.trim()
              : filePath.split('/').last;

      request.files.add(await http.MultipartFile.fromPath(
        fieldName,
        filePath,
        filename: safeFilename,
      ));

      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    }

    final response = await _makeRequestResponse(sendOnce);
    return _handleResponse(response);
  }

  /// Wrapper that handles token refresh on 401
  Future<http.Response> _makeRequestResponse(
      Future<http.Response> Function() request) async {
    final response = await request();

    // Handle 401 - token expired
    if (response.statusCode == 401 && !_isRefreshing) {
      final refreshed = await _refreshToken();
      if (refreshed) {
        // Retry original request with new token
        return request();
      } else {
        throw Exception('Session expired. Please login again.');
      }
    }

    return response;
  }

  /// Refresh access token using refresh token
  Future<bool> _refreshToken() async {
    if (_isRefreshing) return false;

    _isRefreshing = true;

    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'om_refresh=$refreshToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Save new tokens
        if (data['access_token'] != null) {
          await _storage.write(key: 'access_token', value: data['access_token']);
        }
        if (data['refresh_token'] != null) {
          await _storage.write(key: 'refresh_token', value: data['refresh_token']);
        }

        return true;
      }

      return false;
    } catch (e) {
      print('Token refresh error: $e');
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw UnauthorizedException('Unauthorized');
    } else if (response.statusCode == 404) {
      throw NotFoundException('Resource not found');
    } else if (response.statusCode >= 500) {
      throw ServerException('Server error');
    } else {
      throw ApiException('API Error: ${response.statusCode} ${response.body}');
    }
  }
}

// Custom exceptions for better error handling
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  
  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(super.message);
}

class NotFoundException extends ApiException {
  NotFoundException(super.message);
}

class ServerException extends ApiException {
  ServerException(super.message);
}
