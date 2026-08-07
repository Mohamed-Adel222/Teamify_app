import '../core/cache/cache_manager.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../data/repositories/log_repository.dart';

/// Production-grade activity-log service.
///
/// All reads go through an SWR cache with a short TTL (3 minutes) so the
/// activity log feels live while still tolerating brief connectivity gaps.
/// Log entries are immutable (no mutations), so no offline queue is needed.
class LogService with ServiceErrorHandler {
  final LogRepository _repo;
  final CacheManager _cache;

  LogService({required LogRepository repo, required CacheManager cache})
      : _repo = repo,
        _cache = cache;

  final RequestDeduplicator _dedup = RequestDeduplicator();

  static const _box = 'logs';
  static const _keyMy = 'my_activity';
  static const _keyAll = 'all_logs';
  static const _staleAge = Duration(minutes: 3);

  // ── Reads (SWR) ────────────────────────────────────────────────────────────

  /// GET /api/logs/my — current user's activity log (last 50 events).
  ///
  /// Returns cached data instantly, revalidates in background when stale.
  /// Pass [forceRefresh] = true to bypass cache.
  Future<ApiResult<List<Map<String, dynamic>>>> getMyActivity({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) await _cache.invalidate(_box, _keyMy);

    final cached = await _cache.getList(_box, _keyMy, maxAge: _staleAge);
    if (cached != null && !forceRefresh) {
      // Revalidate in background
      _dedup.deduplicate('$_keyMy-bg', () async {
        final fresh = await _repo.getMyActivity();
        await _cache.putList(_box, _keyMy, fresh.cast<Map<String, dynamic>>());
        return ApiResult.success(fresh);
      });
      return ApiResult.success(cached.cast<Map<String, dynamic>>());
    }

    return _dedup.deduplicate(_keyMy, () async {
      final result = await guard(() => _repo.getMyActivity());
      if (result.isSuccess) {
        await _cache.putList(
          _box,
          _keyMy,
          result.data!.cast<Map<String, dynamic>>(),
        );
      }
      return result;
    });
  }

  /// GET /api/logs/all — admin-only: full system audit log.
  ///
  /// Cached separately from the per-user log. Short TTL since admin panels
  /// need near-real-time visibility.
  Future<ApiResult<List<Map<String, dynamic>>>> getAllLogs({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) await _cache.invalidate(_box, _keyAll);

    final cached = await _cache.getList(_box, _keyAll, maxAge: _staleAge);
    if (cached != null && !forceRefresh) {
      _dedup.deduplicate('$_keyAll-bg', () async {
        final fresh = await _repo.getAllLogs();
        await _cache.putList(_box, _keyAll, fresh.cast<Map<String, dynamic>>());
        return ApiResult.success(fresh);
      });
      return ApiResult.success(cached.cast<Map<String, dynamic>>());
    }

    return _dedup.deduplicate(_keyAll, () async {
      final result = await guard(() => _repo.getAllLogs());
      if (result.isSuccess) {
        await _cache.putList(
          _box,
          _keyAll,
          result.data!.cast<Map<String, dynamic>>(),
        );
      }
      return result;
    });
  }

  // ── Cache control ──────────────────────────────────────────────────────────

  /// Wipe all log caches (e.g. on logout or user switch).
  Future<void> clearCache() => _cache.invalidateBox(_box);
}
