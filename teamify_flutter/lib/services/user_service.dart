import '../core/cache/cache_manager.dart';
import '../core/network/api_result.dart';
import '../core/network/service_error_handler.dart';
import '../core/network/request_deduplicator.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/offline_mutation.dart';
import '../core/offline/mutation_id.dart';
import '../data/models/models.dart';
import '../core/cache/swr_helper.dart';
import '../data/repositories/user_repository.dart';

/// Service layer for user profile operations.
///
/// Wraps [UserRepository] with:
/// - Unified error handling via [ApiResult]
/// - SWR caching for profile reads
/// - Offline mutation queuing for profile updates
class UserService with ServiceErrorHandler {
  final UserRepository _repo;
  final CacheManager _cache;
  final OfflineManager _offline;
  final _dedup = RequestDeduplicator();

  static const _ttl = Duration(minutes: 5);

  static String _profileKeyFor(String? userId) =>
      userId != null && userId.isNotEmpty
          ? 'user_profile_$userId'
          : 'user_profile';

  late final SwrHelper _swr;

  UserService({
    required UserRepository repo,
    required CacheManager cache,
    required OfflineManager offline,
  })  : _repo = repo,
        _cache = cache,
        _offline = offline {
    _swr = SwrHelper(_cache);
  }

  /// GET /api/users/profile — SWR-cached per [userId].
  Future<ApiResult<ApiUser?>> getProfile({
    String? userId,
    bool forceRefresh = false,
  }) {
    final key = _profileKeyFor(userId);
    if (forceRefresh) {
      return _dedup.deduplicate(
        '${key}_force',
        () async {
          await _cache.invalidate('users', key);
          try {
            final fresh = await _repo.getProfile();
            if (fresh != null) {
              await _cache.putMap('users', key, fresh.toJson());
            }
            return ApiResult.success(fresh);
          } catch (e) {
            return ApiResult.failure(e.toString());
          }
        },
      );
    }
    return _dedup.deduplicate(
      key,
      () => _swr
          .withSwrMap<ApiUser?>(
            boxName: 'users',
            key: key,
            fetcher: () => _repo.getProfile(),
            fromJson: (json) => ApiUser.fromJson(json),
            toJson: (user) => user?.toJson() ?? {},
            staleAge: _ttl,
          )
          .then((res) => res.isSuccess
              ? res
              : ApiResult.failure(res.error ?? 'Unknown error')),
    );
  }

  /// Drop all cached profile/stats for the current session (call on logout).
  Future<void> clearProfileCache() => _cache.invalidateBox('users');

  /// PUT /api/users/profile — offline-queued on network failure.
  Future<ApiResult<ApiUser?>> updateProfile(Map<String, dynamic> payload) =>
      guardWithOffline(
        () async {
          final updated = await _repo.updateProfile(payload);
          if (updated != null) {
            await _cache.invalidate('users', _profileKeyFor(updated.id));
          }
          return updated;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'PUT',
          path: '/api/users/profile',
          data: payload,
          tag: 'updateProfile',
        ),
        offlineManager: _offline,
      );

  /// GET /api/users/<id>/stats — SWR-cached per user.
  Future<ApiResult<Map<String, dynamic>>> getUserStats(
    String userId, {
    bool forceRefresh = false,
    void Function(Map<String, dynamic>)? onRefreshed,
  }) {
    final key = 'user_stats_$userId';
    if (forceRefresh) {
      return _dedup.deduplicate(
        '${key}_force',
        () async {
          await _cache.invalidate('users', key);
          try {
            final fresh = await _repo.getUserStats(userId);
            await _cache.putMap('users', key, fresh);
            onRefreshed?.call(fresh);
            return ApiResult.success(fresh);
          } catch (e) {
            return ApiResult.failure(e.toString());
          }
        },
      );
    }
    return _dedup.deduplicate(
      key,
      () => _swr
          .withSwrMap<Map<String, dynamic>>(
            boxName: 'users',
            key: key,
            fetcher: () => _repo.getUserStats(userId),
            fromJson: (json) => json,
            toJson: (data) => data,
            staleAge: _ttl,
            onRefreshed: onRefreshed,
          )
          .then((res) => res.isSuccess
              ? res
              : ApiResult.failure(res.error ?? 'Unknown error')),
    );
  }

  Future<void> invalidateUserStats(String userId) async {
    await _cache.invalidate('users', 'user_stats_$userId');
  }

  /// GET /api/users/<id>/profile — public view of another user.
  Future<ApiResult<ApiUser?>> getPublicProfile(String userId) {
    final key = 'user_pub_$userId';
    return _dedup.deduplicate(
      key,
      () => _swr
          .withSwrMap<ApiUser?>(
            boxName: 'users',
            key: key,
            fetcher: () => _repo.getPublicProfile(userId),
            fromJson: (json) => ApiUser.fromJson(json),
            toJson: (user) => user?.toJson() ?? {},
            staleAge: _ttl,
          )
          .then((res) => res.isSuccess
              ? res
              : ApiResult.failure(res.error ?? 'Unknown error')),
    );
  }
}
