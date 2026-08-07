import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../models/models.dart';
import 'repository_helpers.dart';

class AuthResult {
  final ApiUser? user;
  final bool pendingApproval;
  final String message;
  final bool requires2faSetup;
  final bool requires2faLogin;

  const AuthResult({
    this.user,
    this.pendingApproval = false,
    this.message = '',
    this.requires2faSetup = false,
    this.requires2faLogin = false,
  });
}

class AuthRepository {
  final ApiClient _client;
  final TokenStorage _tokenStorage;

  AuthRepository({
    required ApiClient client,
    required TokenStorage tokenStorage,
  })  : _client = client,
        _tokenStorage = tokenStorage;

  // ── Core auth ────────────────────────────────────────────────────────────────

  Future<AuthResult> login({
    required String email,
    required String password,
    String? totpCode,
  }) async {
    final data = <String, dynamic>{
      'email': email,
      'password': password,
    };
    if (totpCode != null && totpCode.isNotEmpty) {
      data['totp_code'] = totpCode;
    }

    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: data,
      options: Options(extra: {'skipAuth': true}),
    );
    final payload = responseMap(response.data);
    await _saveTokens(payload.isEmpty ? null : payload);
    var user = _extractUser(payload.isEmpty ? null : payload);
    if (user == null && await hasSavedSession()) {
      user = await me();
    }
    return AuthResult(
      user: user,
      message: asString(payload['message']),
      requires2faSetup: payload['requires_2fa_setup'] == true,
      requires2faLogin: payload['requires_2fa_login'] == true,
    );
  }

  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required String userType,
    Map<String, dynamic> extra = const {},
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': role,
        'user_type': userType,
        ...extra,
      },
      options: Options(extra: {'skipAuth': true}),
    );
    await _saveTokens(response.data);
    final user = _extractUser(response.data);
    return AuthResult(
      user: user,
      pendingApproval: user?.isPending ?? false,
      message: asString(response.data?['message']),
    );
  }

  Future<ApiUser?> me() async {
    final response = await _client.get<Map<String, dynamic>>('/api/auth/me');
    return _extractUser(response.data);
  }

  Future<void> logout() async {
    try {
      await _client.post<Map<String, dynamic>>('/api/auth/logout');
    } finally {
      await _tokenStorage.clear();
    }
  }

  Future<bool> hasSavedSession() async {
    final token = await _tokenStorage.readAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── Password recovery ─────────────────────────────────────────────────────

  /// POST /api/auth/forgot-password
  Future<void> forgotPassword(String email) async {
    await _client.post<dynamic>(
      '/api/auth/forgot-password',
      data: {'email': email},
      options: Options(extra: {'skipAuth': true}),
    );
  }

  /// POST /api/auth/verify-otp
  Future<Map<String, dynamic>> verifyOtp(String email, String otp) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/verify-otp',
      data: {'email': email, 'otp': otp},
      options: Options(extra: {'skipAuth': true}),
    );
    return responseMap(response.data);
  }

  /// POST /api/auth/reset-password
  Future<void> resetPassword(String token, String newPassword) async {
    await _client.post<dynamic>(
      '/api/auth/reset-password',
      data: {'reset_token': token, 'new_password': newPassword},
      options: Options(extra: {'skipAuth': true}),
    );
  }

  // ── OAuth login ───────────────────────────────────────────────────────────

  /// POST /api/auth/google
  Future<AuthResult> loginWithGoogle(String idToken, {String? userType}) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/google',
      data: {
        'id_token': idToken,
        if (userType != null) 'user_type': userType,
      },
      options: Options(extra: {'skipAuth': true}),
    );
    await _saveTokens(response.data);
    var user = _extractUser(response.data);
    if (user == null && await hasSavedSession()) {
      user = await me();
    }
    return AuthResult(user: user, message: asString(response.data?['message']));
  }

  /// POST /api/auth/github
  Future<AuthResult> loginWithGithub(
    String code, {
    String? userType,
    String? redirectUri,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/github',
      data: {
        'code': code,
        if (userType != null) 'user_type': userType,
        if (redirectUri != null && redirectUri.isNotEmpty)
          'redirect_uri': redirectUri,
      },
      options: Options(extra: {'skipAuth': true}),
    );
    await _saveTokens(response.data);
    var user = _extractUser(response.data);
    if (user == null && await hasSavedSession()) {
      user = await me();
    }
    return AuthResult(user: user, message: asString(response.data?['message']));
  }

  // ── Two-Factor Authentication ─────────────────────────────────────────────

  /// POST /api/auth/2fa/setup
  /// Returns: { secret, qr_code (base64 PNG), message }
  Future<Map<String, dynamic>> setup2fa() async {
    final response =
        await _client.post<Map<String, dynamic>>('/api/auth/2fa/setup');
    return responseMap(response.data);
  }

  /// POST /api/auth/2fa/verify
  Future<ApiUser?> verify2fa(String token) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/2fa/verify',
      data: {'token': token},
    );
    await _saveTokens(response.data);
    return _extractUser(response.data);
  }

  /// POST /api/auth/2fa/confirm-login
  Future<ApiUser?> confirm2faLogin(String token) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/auth/2fa/confirm-login',
      data: {'token': token},
    );
    await _saveTokens(response.data);
    return _extractUser(response.data);
  }

  /// DELETE /api/auth/2fa/disable
  Future<void> disable2fa(String token) async {
    await _client.delete<dynamic>(
      '/api/auth/2fa/disable',
      data: {'token': token},
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _saveTokens(Map<String, dynamic>? data) async {
    if (data == null) return;
    final access = data['access_token']?.toString();
    final refresh = data['refresh_token']?.toString();
    if (access != null &&
        access.isNotEmpty &&
        refresh != null &&
        refresh.isNotEmpty) {
      await _tokenStorage.saveTokens(
          accessToken: access, refreshToken: refresh);
    }
  }

  ApiUser? _extractUser(Map<String, dynamic>? data) {
    if (data == null) return null;
    final userMap = responseMap(data['user']);
    if (userMap.isNotEmpty) return ApiUser.fromJson(userMap);
    if (data.containsKey('id') || data.containsKey('email')) {
      return ApiUser.fromJson(data);
    }
    return null;
  }
}
