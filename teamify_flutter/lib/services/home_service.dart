import '../core/cache/cache_manager.dart';
import '../core/cache/swr_helper.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../data/repositories/home_repository.dart';

/// Consolidated `/api/dashboard` + health checks for home shells.
///
/// Dashboard data is SWR-cached with a 2-minute TTL so the home screen
/// renders instantly from cache while a background refresh runs.
class HomeService with ServiceErrorHandler {
  final HomeRepository _repo;
  final CacheManager _cache;

  static const _box = 'home';
  static const _ttl = Duration(minutes: 2);

  HomeService(this._repo, this._cache) {
    _swr = SwrHelper(_cache);
  }

  final RequestDeduplicator _dedup = RequestDeduplicator();
  late final SwrHelper _swr;

  static String _cacheKey(String? userId) =>
      userId != null && userId.isNotEmpty ? 'dashboard_$userId' : 'dashboard';

  /// Drop cached dashboard payload (call after project/task mutations).
  Future<void> invalidateDashboard({String? userId}) async {
    await _cache.invalidate(_box, _cacheKey(userId));
    // Legacy key used before per-user scoping
    await _cache.invalidate(_box, 'dashboard');
  }

  /// Clear every cached dashboard snapshot (e.g. after notification read changes).
  Future<void> invalidateAllDashboards() async {
    await _cache.invalidateBox(_box);
  }

  Future<ApiResult<Map<String, dynamic>>> getDashboard({
    String? userId,
    bool forceRefresh = false,
    void Function(Map<String, dynamic>)? onRefreshed,
  }) =>
      _dedup.deduplicate(
          'dashboard_${userId ?? 'anon'}',
          () => guard(() async {
                final cacheKey = _cacheKey(userId);
                if (forceRefresh) {
                  final data = await _repo.getDashboard();
                  await _cache.putMap(_box, cacheKey, data);
                  return data;
                }
                return _swr
                    .withSwrMap<Map<String, dynamic>>(
                      boxName: _box,
                      key: cacheKey,
                      fetcher: () => _repo.getDashboard(),
                      fromJson: (j) => j,
                      toJson: (d) => d,
                      staleAge: _ttl,
                      onRefreshed: onRefreshed,
                    )
                    .then((res) =>
                        res.isSuccess ? res.data! : throw Exception(res.error));
              }));

  Future<ApiResult<Map<String, dynamic>>> checkHealth() =>
      _dedup.deduplicate('health', () => guard(() => _repo.checkHealth()));
}
