import '../core/cache/cache_manager.dart';
import '../core/cache/swr_helper.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../core/offline/mutation_id.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/offline_mutation.dart';
import '../data/repositories/feedback_repository.dart';

/// Service layer for peer feedback operations.
///
/// submitFeedback uses guardWithOffline() so feedback can be queued
/// when the device is offline.
class FeedbackService with ServiceErrorHandler {
  final FeedbackRepository _repo;
  final CacheManager _cache;
  final OfflineManager _offline;
  final _dedup = RequestDeduplicator();
  late final SwrHelper _swr;
  static const _box = 'feedback';

  FeedbackService({
    required FeedbackRepository repo,
    required CacheManager cache,
    required OfflineManager offline,
  })  : _repo = repo,
        _cache = cache,
        _offline = offline {
    _swr = SwrHelper(_cache);
  }

  static const _ttl = Duration(minutes: 3);

  /// GET /api/feedback/user/<userId>
  Future<ApiResult<List<Map<String, dynamic>>>> getUserFeedback(
    String userId, {
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      await _cache.invalidate(_box, 'user_$userId');
      return guard(() => _repo.getUserFeedback(userId));
    }
    return _dedup.deduplicate(
      'feedback_user_$userId',
      () => _swr
          .withSwrList<Map<String, dynamic>>(
            boxName: _box,
            key: 'user_$userId',
            fetcher: () => _repo.getUserFeedback(userId),
            fromJson: (json) => json,
            toJson: (data) => data,
            staleAge: _ttl,
          )
          .then((res) => res.isSuccess
              ? res
              : ApiResult.failure(res.error ?? 'Unknown error')),
    );
  }

  /// POST /api/feedback — submit peer feedback.
  ///
  /// Uses [guardWithOffline] so submissions are queued when the device is
  /// offline and replayed automatically when connectivity returns.
  /// Busts the receiver's feedback cache on success.
  Future<ApiResult<void>> submitFeedback({
    required String targetUserId,
    required String projectId,
    required int rating,
    String comment = '',
  }) {
    final payload = {
      'user_id': int.tryParse(targetUserId) ?? targetUserId,
      'project_id': int.tryParse(projectId) ?? projectId,
      'avg_rating': rating,
      'quality_score': rating,
      'teamwork_score': rating,
      if (comment.isNotEmpty) 'feedback_text': comment,
    };

    return guardWithOffline(
      () async {
        await _repo.submitFeedback(payload);
        await _cache.invalidate(_box, 'user_$targetUserId');
        await _cache.invalidate('users', 'user_stats_$targetUserId');
      },
      mutation: OfflineMutation(
        id: MutationId.generate(),
        method: 'POST',
        path: '/api/feedback',
        data: payload,
        tag: 'submitFeedback',
      ),
      offlineManager: _offline,
    );
  }
}
