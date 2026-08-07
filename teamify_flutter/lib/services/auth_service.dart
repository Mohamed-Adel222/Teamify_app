import '../../core/cache/cache_manager.dart';
import '../../core/network/api_result.dart';
import '../../core/network/service_error_handler.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../core/session/session_controller.dart';

/// Service layer for authentication workflows.
///
/// Wraps [AuthRepository] to provide:
/// - Unified error handling via [ApiResult]
/// - Session state management
/// - Business logic for multi-step auth flows (OTP, OAuth, 2FA)
class AuthService with ServiceErrorHandler {
  final AuthRepository _repo;
  final SessionController _session;
  final CacheManager _cache;

  AuthService({
    required AuthRepository repo,
    required SessionController session,
    required CacheManager cache,
  })  : _repo = repo,
        _session = session,
        _cache = cache;

  // ── Core auth ────────────────────────────────────────────────────────────

  Future<ApiResult<ApiUser?>> login({
    required String email,
    required String password,
    String? totpCode,
  }) =>
      guard(() async {
        await _cache.clearAll();
        final result = await _session.login(
          email: email,
          password: password,
          totpCode: totpCode,
        );
        return result.user;
      });

  Future<ApiResult<ApiUser?>> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required String userType,
    Map<String, dynamic> extra = const {},
  }) =>
      guard(() async {
        final result = await _session.register(
          fullName: fullName,
          email: email,
          password: password,
          role: role,
          userType: userType,
          extra: extra,
        );
        return result.user;
      });

  Future<ApiResult<void>> logout() => guard(() async {
        await _session.logout();
        await _cache.clearAll();
      });

  // ── Password recovery (multi-step) ───────────────────────────────────────

  Future<ApiResult<void>> forgotPassword(String email) =>
      guard(() => _repo.forgotPassword(email));

  Future<ApiResult<String>> verifyOtp(String email, String otp) =>
      guard(() async {
        final data = await _repo.verifyOtp(email, otp);
        return data['reset_token']?.toString() ??
            data['token']?.toString() ??
            '';
      });

  Future<ApiResult<void>> resetPassword(String token, String newPassword) =>
      guard(() => _repo.resetPassword(token, newPassword));

  // ── OAuth ───────────────────────────────────────────────────────────────

  Future<ApiResult<ApiUser?>> loginWithGoogle(String idToken,
          {String? userType}) =>
      guard(() async {
        await _cache.clearAll();
        final result = await _repo.loginWithGoogle(idToken, userType: userType);
        await _session.completeOAuthLogin(result);
        return _session.currentUser;
      });

  Future<ApiResult<ApiUser?>> loginWithGithub(String code,
          {String? userType, String? redirectUri}) =>
      guard(() async {
        await _cache.clearAll();
        final result = await _repo.loginWithGithub(
          code,
          userType: userType,
          redirectUri: redirectUri,
        );
        await _session.completeOAuthLogin(result);
        return _session.currentUser;
      });

  // ── 2FA ─────────────────────────────────────────────────────────────────

  Future<ApiResult<Map<String, dynamic>>> setup2fa() =>
      guard(() => _repo.setup2fa());

  Future<ApiResult<ApiUser?>> verify2fa(String token) => guard(() async {
        final user = await _repo.verify2fa(token);
        _session.completeAdmin2fa(refreshedUser: user);
        return _session.currentUser;
      });

  Future<ApiResult<ApiUser?>> confirm2faLogin(String token) => guard(() async {
        final user = await _repo.confirm2faLogin(token);
        _session.completeAdmin2fa(refreshedUser: user);
        return _session.currentUser;
      });

  Future<ApiResult<void>> disable2fa(String token) =>
      guard(() => _repo.disable2fa(token));
}
