import '../core/cache/cache_manager.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../core/offline/mutation_id.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/offline_mutation.dart';
import '../data/repositories/dispute_repository.dart';

/// Production-grade service layer for dispute management.
///
/// Supported patterns:
///  - SWR caching with [forceRefresh] for all list reads
///  - [guardWithOffline] for all mutations (offline queue replay)
///  - [RequestDeduplicator] to collapse concurrent identical calls
///  - Full cache invalidation after writes
class DisputeService with ServiceErrorHandler {
  final DisputeRepository _repo;
  final CacheManager _cache;
  final OfflineManager _offline;

  DisputeService({
    required DisputeRepository repo,
    required CacheManager cache,
    required OfflineManager offline,
  })  : _repo = repo,
        _cache = cache,
        _offline = offline;

  final RequestDeduplicator _dedup = RequestDeduplicator();

  static const _box = 'disputes';
  static const _keyMy = 'my_disputes';
  static const _keyAll = 'all_disputes';
  static const _staleAge = Duration(minutes: 5);

  // ── Reads (SWR) ────────────────────────────────────────────────────────────

  /// GET /api/disputes/my — current user's disputes (filed + received).
  ///
  /// Returns cached data immediately then revalidates in background.
  /// Pass [forceRefresh] = true to bypass cache and fetch fresh data.
  Future<ApiResult<List<Map<String, dynamic>>>> getMyDisputes({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) await _cache.invalidate(_box, _keyMy);

    // Serve from cache if fresh
    final cached = await _cache.getList(_box, _keyMy, maxAge: _staleAge);
    if (cached != null && !forceRefresh) {
      // Background revalidate
      _dedup.deduplicate('$_keyMy-bg', () async {
        final fresh = await _repo.getMyDisputes();
        await _cache.putList(_box, _keyMy, fresh.cast<Map<String, dynamic>>());
        return ApiResult.success(fresh);
      });
      return ApiResult.success(cached.cast<Map<String, dynamic>>());
    }

    return _dedup.deduplicate(_keyMy, () async {
      final result = await guard(() => _repo.getMyDisputes());
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

  /// GET /api/disputes — admin: all disputes (paginated).
  Future<ApiResult<List<Map<String, dynamic>>>> getAllDisputes({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) await _cache.invalidate(_box, _keyAll);

    final cached = await _cache.getList(_box, _keyAll, maxAge: _staleAge);
    if (cached != null && !forceRefresh) {
      _dedup.deduplicate('$_keyAll-bg', () async {
        final fresh = await _repo.getAllDisputes();
        await _cache.putList(_box, _keyAll, fresh.cast<Map<String, dynamic>>());
        return ApiResult.success(fresh);
      });
      return ApiResult.success(cached.cast<Map<String, dynamic>>());
    }

    return _dedup.deduplicate(_keyAll, () async {
      final result = await guard(() => _repo.getAllDisputes());
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

  /// GET /api/disputes/<id>
  Future<ApiResult<Map<String, dynamic>>> getDispute(String id) =>
      _dedup.deduplicate(
        'dispute_$id',
        () => guard(() => _repo.getDispute(id)),
      );

  // ── Mutations (offline-first) ──────────────────────────────────────────────

  /// POST /api/disputes — file a new dispute.
  ///
  /// Required keys: accused_id, subject, description.
  /// Optional: project_id, category.
  Future<ApiResult<void>> fileDispute(Map<String, dynamic> payload) async {
    final result = await guardWithOffline(
      () => _repo.fileDispute(payload),
      mutation: OfflineMutation(
        id: MutationId.generate(),
        method: 'POST',
        path: '/api/disputes',
        data: payload,
        tag: 'fileDispute',
      ),
      offlineManager: _offline,
    );
    if (result.isSuccess || result.isOfflineQueued) {
      // Invalidate so next read fetches fresh data
      await _cache.invalidate(_box, _keyMy);
      await _cache.invalidate(_box, _keyAll);
    }
    return result;
  }

  /// PATCH /api/disputes/<id>/status — admin: resolve / reject / review.
  Future<ApiResult<void>> updateDisputeStatus(String id, String status) async {
    final result = await guardWithOffline(
      () => _repo.updateDisputeStatus(id, status),
      mutation: OfflineMutation(
        id: MutationId.generate(),
        method: 'PATCH',
        path: '/api/disputes/$id/status',
        data: {'status': status},
        tag: 'updateDisputeStatus',
      ),
      offlineManager: _offline,
    );
    if (result.isSuccess || result.isOfflineQueued) {
      await _cache.invalidate(_box, _keyAll);
      await _cache.invalidate(_box, 'dispute_$id');
    }
    return result;
  }

  // ── Cache control ──────────────────────────────────────────────────────────

  /// Force-clear all dispute caches (e.g. on logout).
  Future<void> clearCache() => _cache.invalidateBox(_box);
}
