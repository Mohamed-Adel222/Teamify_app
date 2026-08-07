import '../core/cache/cache_manager.dart';
import '../core/cache/swr_helper.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/mutation_id.dart';
import '../core/offline/offline_mutation.dart';
import '../data/repositories/rating_repository.dart';

/// Service layer for peer ratings.
///
/// SWR cache TTLs:
///   User ratings list — 5 minutes
///   User average rating — 5 minutes
///
/// Mutations (submitRating, updateRating, deleteRating) are queued
/// via [OfflineManager] so they survive connectivity loss.
class RatingService with ServiceErrorHandler {
  final RatingRepository _repo;
  final CacheManager _cache;
  final OfflineManager _offline;

  static const _box = 'ratings';
  static const _ttl = Duration(minutes: 5);

  RatingService(this._repo, this._cache, this._offline) {
    _swr = SwrHelper(_cache);
  }

  final RequestDeduplicator _dedup = RequestDeduplicator();
  late final SwrHelper _swr;

  Future<ApiResult<double>> getUserAverageRating(String userId) =>
      _dedup.deduplicate(
        'rating_avg_$userId',
        () => guard(() => _repo.getUserAverageRating(userId)),
      );

  Future<ApiResult<List<Map<String, dynamic>>>> getUserRatings(
    String userId, {
    bool forceRefresh = false,
    void Function(List<Map<String, dynamic>>)? onRefreshed,
  }) =>
      _dedup.deduplicate(
          'rating_list_$userId',
          () => guard(() async {
                if (forceRefresh) {
                  final list = await _repo.getUserRatings(userId);
                  await _cache.putList(_box, 'user_$userId',
                      list.map((r) => Map<String, dynamic>.from(r)).toList());
                  return list;
                }
                return _swr
                    .withSwrList<Map<String, dynamic>>(
                      boxName: _box,
                      key: 'user_$userId',
                      fetcher: () => _repo.getUserRatings(userId),
                      fromJson: (j) => j,
                      toJson: (r) => r,
                      staleAge: _ttl,
                      onRefreshed: onRefreshed,
                    )
                    .then((res) =>
                        res.isSuccess ? res.data! : throw Exception(res.error));
              }));

  Future<ApiResult<void>> submitRating(Map<String, dynamic> payload) =>
      guardWithOffline(
        () async {
          await _repo.submitRating(payload);
          final rateeId = payload['ratee_id']?.toString();
          if (rateeId != null) await _cache.invalidate(_box, 'user_$rateeId');
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/ratings',
          data: payload,
          tag: 'submitRating',
        ),
        offlineManager: _offline,
      );

  Future<ApiResult<void>> updateRating(
          String id, double score, String comment) =>
      guardWithOffline(
        () => _repo.updateRating(id, score, comment),
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'PUT',
          path: '/api/ratings/$id',
          data: {'score': score, 'comment': comment},
          tag: 'updateRating',
        ),
        offlineManager: _offline,
      );

  Future<ApiResult<void>> deleteRating(String id) => guardWithOffline(
        () => _repo.deleteRating(id),
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'DELETE',
          path: '/api/ratings/$id',
          data: {},
          tag: 'deleteRating',
        ),
        offlineManager: _offline,
      );
}
