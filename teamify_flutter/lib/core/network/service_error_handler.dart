import 'package:dio/dio.dart';

import '../offline/offline_manager.dart';
import '../offline/offline_mutation.dart';
import '../observability/app_logger.dart';
import 'api_exception.dart';
import 'api_result.dart';

/// Mixin providing standardised error-handling, retry logic, and
/// **offline mutation enqueuing** for all service classes.
///
/// Usage — mutations that should be queued when offline:
/// ```dart
/// Future<ApiResult<ApiTask>> createTask(Map<String, dynamic> payload) =>
///     guardWithOffline(
///       () => _repo.createTask(payload),
///       mutation: OfflineMutation(
///         id: const Uuid().v4(),
///         method: 'POST',
///         path: '/api/tasks',
///         data: payload,
///         tag: 'createTask',
///       ),
///       offlineManager: _offline,
///     );
/// ```
///
/// Read-only calls (GET) should continue using [guard] or [guardWithRetry].
mixin ServiceErrorHandler {
  // ── Core guard ─────────────────────────────────────────────────────────

  /// Wraps any async call in an [ApiResult], catching Dio and generic errors.
  ///
  /// Does NOT enqueue — use [guardWithOffline] for mutations.
  Future<ApiResult<T>> guard<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      return ApiResult.success(result);
    } on DioException catch (e) {
      final apiError = e.error;
      if (apiError is ApiException) {
        final detail = apiError.validationMessages.isNotEmpty
            ? apiError.validationMessages.join('; ')
            : apiError.message;
        return ApiResult.failure(
          detail,
          statusCode: apiError.statusCode,
          requires2fa: apiError.requires2fa,
          requires2faSetup: apiError.requires2faSetup,
        );
      }
      if (e.response?.data != null) {
        final parsed = ApiException.fromResponse(
          e.response?.statusCode,
          e.response?.data,
        );
        return ApiResult.failure(
          parsed.message,
          statusCode: parsed.statusCode,
          requires2fa: parsed.requires2fa,
          requires2faSetup: parsed.requires2faSetup,
        );
      }
      if (_isDioNetworkError(e)) {
        return ApiResult.failure(
          'Network error. Please check your connection.',
          isNetworkError: true,
        );
      }
      return ApiResult.failure(
        e.message ?? 'Request failed',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      return ApiResult.failure(e.toString());
    }
  }

  // ── Offline-aware guard ─────────────────────────────────────────────────

  /// Like [guard] but automatically enqueues [mutation] when the failure is
  /// a network-level error (no internet, timeout, socket drop, etc.).
  ///
  /// **Enqueuing rules** (to avoid infinite replay loops):
  ///  - ONLY if the error is a network error ([isNetworkError] == true)
  ///  - NEVER for 4xx/5xx HTTP errors, validation failures, or auth errors
  ///
  /// Returns [ApiResult.queued] (isOfflineQueued = true) so the UI can show
  /// a "pending sync" indicator instead of a hard error.
  Future<ApiResult<T>> guardWithOffline<T>(
    Future<T> Function() action, {
    required OfflineMutation mutation,
    required OfflineManager offlineManager,
  }) async {
    final result = await guard(action);

    if (result.isSuccess) return result;

    // Only capture true network failures — never 4xx/5xx
    if (result.isNetworkError) {
      await offlineManager.enqueue(mutation);

      AppLogger.offlineEvent(
        'offline.queue.add',
        id: mutation.id,
        tag: mutation.tag ?? mutation.path,
      );

      return ApiResult.queued(
        'No internet connection. Your action will sync when back online.',
      );
    }

    // Pass through all other errors (validation, auth, server errors)
    return result;
  }

  // ── Retry guard ─────────────────────────────────────────────────────────

  /// Retries [action] up to [maxRetries] times with jittered exponential backoff.
  Future<ApiResult<T>> guardWithRetry<T>(
    Future<T> Function() action, {
    int maxRetries = 2,
    bool Function(dynamic error)? shouldRetry,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final result = await guard(action);
      if (result.isSuccess) return result;

      final retryDecision = shouldRetry != null
          ? shouldRetry(result.error)
          : result.isNetworkError;
      if (!retryDecision) return result;

      if (attempt < maxRetries) {
        final baseDelay = 1000 * (1 << attempt); // 1s, 2s, 4s
        final jitter = DateTime.now().millisecondsSinceEpoch % 500;
        await Future.delayed(Duration(milliseconds: baseDelay + jitter));
      }
    }
    return ApiResult.failure('Request failed after retries',
        isNetworkError: true);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static bool _isDioNetworkError(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.unknown;
}
