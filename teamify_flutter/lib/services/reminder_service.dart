import '../core/cache/cache_manager.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../data/repositories/reminder_repository.dart';

/// Production-grade reminder service.
///
/// Reminders are derived from task due-dates on the backend and are
/// read-only (no create/update/delete surface). The cache TTL is
/// deliberately short (2 min) so the user sees timely task reminders.
class ReminderService with ServiceErrorHandler {
  final ReminderRepository _repo;
  final CacheManager _cache;

  ReminderService({
    required ReminderRepository repo,
    required CacheManager cache,
  })  : _repo = repo,
        _cache = cache;

  final RequestDeduplicator _dedup = RequestDeduplicator();

  static const _box = 'reminders';
  static const _key = 'reminders_list';
  // Short TTL — reminders are time-sensitive
  static const _staleAge = Duration(minutes: 2);

  // ── Reads (SWR) ────────────────────────────────────────────────────────────

  /// GET /api/reminders — list all due/overdue reminders for the current user.
  ///
  /// Returns stale cache instantly, then revalidates in background.
  /// Pass [forceRefresh] = true to skip cache and pull from server directly.
  Future<ApiResult<List<Map<String, dynamic>>>> getReminders({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) await _cache.invalidate(_box, _key);

    final cached = await _cache.getList(_box, _key, maxAge: _staleAge);
    if (cached != null && !forceRefresh) {
      // Background revalidation so next call gets fresh data
      _dedup.deduplicate('$_key-bg', () async {
        final fresh = await _repo.getReminders();
        await _cache.putList(_box, _key, fresh.cast<Map<String, dynamic>>());
        return ApiResult.success(fresh);
      });
      return ApiResult.success(cached.cast<Map<String, dynamic>>());
    }

    return _dedup.deduplicate(_key, () async {
      final result = await guard(() => _repo.getReminders());
      if (result.isSuccess) {
        await _cache.putList(
          _box,
          _key,
          result.data!.cast<Map<String, dynamic>>(),
        );
      }
      return result;
    });
  }

  // ── Cache control ──────────────────────────────────────────────────────────

  /// Wipe reminder cache. Call when a task's due-date changes.
  Future<void> invalidate() => _cache.invalidate(_box, _key);

  /// Wipe all reminder caches (e.g. on logout).
  Future<void> clearCache() => _cache.invalidateBox(_box);
}
