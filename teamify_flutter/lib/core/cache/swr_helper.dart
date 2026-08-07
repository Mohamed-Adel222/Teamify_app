import 'dart:async';
import 'cache_manager.dart';
import '../network/api_result.dart';
import '../observability/app_logger.dart';

/// Reusable Stale-While-Revalidate (SWR) cache helper.
class SwrHelper {
  final CacheManager cache;

  SwrHelper(this.cache);

  /// Executes SWR strategy for a single map item.
  Future<ApiResult<T>> withSwrMap<T>({
    required String boxName,
    required String key,
    required Future<T> Function() fetcher,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    void Function(T)? onRefreshed,
    Duration staleAge = const Duration(minutes: 10),
  }) async {
    final cached =
        await cache.getMap(boxName, key, maxAge: const Duration(days: 30));
    final isStale = cached != null && cache.isExpired(boxName, key, staleAge);

    if (cached != null) {
      final data = fromJson(cached);
      if (isStale) {
        _revalidateMap(
          boxName: boxName,
          key: key,
          fetcher: fetcher,
          toJson: toJson,
          onRefreshed: onRefreshed,
        );
      }
      return ApiResult.success(data);
    }

    // No cache, fetch instantly
    try {
      final fresh = await fetcher();
      await cache.putMap(boxName, key, toJson(fresh));
      return ApiResult.success(fresh);
    } catch (e) {
      return ApiResult.failure(e.toString());
    }
  }

  /// Executes SWR strategy for a list of items.
  Future<ApiResult<List<T>>> withSwrList<T>({
    required String boxName,
    required String key,
    required Future<List<T>> Function() fetcher,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    void Function(List<T>)? onRefreshed,
    Duration staleAge = const Duration(minutes: 10),
  }) async {
    final cached =
        await cache.getList(boxName, key, maxAge: const Duration(days: 30));
    final isStale = cached != null && cache.isExpired(boxName, key, staleAge);

    if (cached != null) {
      final data = cached.map(fromJson).toList();
      if (isStale) {
        _revalidateList(
          boxName: boxName,
          key: key,
          fetcher: fetcher,
          toJson: toJson,
          onRefreshed: onRefreshed,
        );
      }
      return ApiResult.success(data);
    }

    // No cache, fetch instantly
    try {
      final fresh = await fetcher();
      await cache.putList(boxName, key, fresh.map(toJson).toList());
      return ApiResult.success(fresh);
    } catch (e) {
      return ApiResult.failure(e.toString());
    }
  }

  Future<void> _revalidateMap<T>({
    required String boxName,
    required String key,
    required Future<T> Function() fetcher,
    required Map<String, dynamic> Function(T) toJson,
    void Function(T)? onRefreshed,
  }) async {
    try {
      final fresh = await fetcher();
      await cache.putMap(boxName, key, toJson(fresh));
      onRefreshed?.call(fresh);
    } catch (e) {
      AppLogger.info('swr.revalidate.failed', data: {
        'box': boxName,
        'key': key,
        'error': e.toString(),
      });
    }
  }

  Future<void> _revalidateList<T>({
    required String boxName,
    required String key,
    required Future<List<T>> Function() fetcher,
    required Map<String, dynamic> Function(T) toJson,
    void Function(List<T>)? onRefreshed,
  }) async {
    try {
      final fresh = await fetcher();
      await cache.putList(boxName, key, fresh.map(toJson).toList());
      onRefreshed?.call(fresh);
    } catch (e) {
      AppLogger.info('swr.revalidate.failed', data: {
        'box': boxName,
        'key': key,
        'error': e.toString(),
      });
    }
  }
}
