import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import 'offline_mutation.dart';
import '../../config/app_config.dart';
import '../cache/cache_manager.dart';
import '../network/api_client.dart';
import '../observability/app_logger.dart';

/// Manages offline mutations with:
///  - Exponential backoff (1s → 2s → 4s → 8s → 16s → 30s cap)
///  - Permanent-failure detection after [_maxRetries] attempts
///  - Idempotency-Key header injected automatically on every replay
///  - Mutex guard to prevent concurrent replay storms
///  - Queue-depth and permanent-failure observability
///  - Serial replay (concurrency = 1) to preserve causality
class OfflineManager {
  final CacheManager cache;
  final ApiClient apiClient;
  final Connectivity connectivity;

  static const _box = '_offline_queue';
  static const _key = 'mutations';
  static const int _maxRetries = 5;

  /// Backoff schedule in seconds: index = retryCount (capped).
  static const _backoffSeconds = [1, 2, 4, 8, 16, 30];

  bool _isReplaying = false;
  bool _isPaused = false;
  StreamSubscription? _subscription;

  OfflineManager({
    required this.cache,
    required this.apiClient,
    Connectivity? connectivity,
  }) : connectivity = connectivity ?? Connectivity();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void init() {
    _subscription = connectivity.onConnectivityChanged.listen((results) {
      final isOnline = !results.contains(ConnectivityResult.none);
      AppLogger.log('[Offline] Connectivity changed — online=$isOnline');
      if (isOnline && !_isPaused) {
        replayQueue();
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
  }

  void pauseReplay() {
    _isPaused = true;
    AppLogger.log('[Offline] Replay paused');
  }

  void resumeReplay() {
    _isPaused = false;
    AppLogger.log('[Offline] Replay resumed');
    connectivity.checkConnectivity().then((results) {
      final isOnline = !results.contains(ConnectivityResult.none);
      if (isOnline) replayQueue();
    });
  }

  // ── Queue mutations ───────────────────────────────────────────────────────

  /// Enqueues [mutation], deduplicating by [mutation.id].
  ///
  /// The [Idempotency-Key] header is always injected here so every replay
  /// includes it, regardless of whether the caller supplied it.
  Future<void> enqueue(OfflineMutation mutation) async {
    final list = await _getQueue();

    // Idempotency: reject duplicates by id
    if (list.any((m) => m.id == mutation.id)) {
      AppLogger.log('[Offline] Duplicate enqueue ignored: ${mutation.id}');
      return;
    }

    // Merge Idempotency-Key into headers
    final merged = Map<String, String>.from(mutation.headers ?? {});
    merged['Idempotency-Key'] = mutation.id;

    final persisted = OfflineMutation(
      id: mutation.id,
      method: mutation.method,
      path: mutation.path,
      data: mutation.data,
      headers: merged,
      retryCount: 0,
      createdAt: mutation.createdAt,
      tag: mutation.tag,
      status: MutationStatus.pending,
    );

    list.add(persisted);
    await _saveQueue(list);

    AppLogger.recordMetric('offline.queue.add', 1, tags: {
      'tag': mutation.tag ?? mutation.path,
      'method': mutation.method,
      'id': mutation.id,
    });

    // Attempt immediate replay if we happen to be online
    final results = await connectivity.checkConnectivity();
    final isOnline = !results.contains(ConnectivityResult.none);
    if (isOnline && !_isPaused) {
      replayQueue();
    }
  }

  // ── Replay ────────────────────────────────────────────────────────────────

  /// Replays all pending, backoff-ready mutations serially.
  ///
  /// Guard: returns immediately if already replaying or paused.
  Future<void> replayQueue() async {
    if (AppConfig.isDemoMode) return;
    if (_isReplaying || _isPaused) return;
    _isReplaying = true;
    AppLogger.log('[Offline] Starting replay');

    try {
      final queue = await _getQueue();
      if (queue.isEmpty) return;

      final toKeep = <OfflineMutation>[];

      for (final mutation in queue) {
        if (_isPaused) break;

        // Skip permanently failed ones — they stay in toKeep for display
        if (mutation.isFailedPermanently) {
          toKeep.add(mutation);
          continue;
        }

        // Respect backoff window
        if (!mutation.isReadyForReplay) {
          toKeep.add(mutation);
          continue;
        }

        final replayStart = DateTime.now();

        try {
          final options = Options(
            headers: mutation.headers ?? {'Idempotency-Key': mutation.id},
          );

          switch (mutation.method.toUpperCase()) {
            case 'POST':
              await apiClient.post<dynamic>(mutation.path,
                  data: mutation.data, options: options);
              break;
            case 'PUT':
              await apiClient.put<dynamic>(mutation.path,
                  data: mutation.data, options: options);
              break;
            case 'PATCH':
              await apiClient.patch<dynamic>(mutation.path,
                  data: mutation.data, options: options);
              break;
            case 'DELETE':
              await apiClient.delete<dynamic>(mutation.path,
                  data: mutation.data, options: options);
              break;
            default:
              // Unknown method — drop permanently
              AppLogger.error(
                  '[Offline] Unknown method ${mutation.method} — dropping');
              AppLogger.recordMetric('offline.queue.permanent_failure', 1,
                  tags: {'id': mutation.id, 'reason': 'unknown_method'});
              continue;
          }

          final latency = DateTime.now().difference(replayStart);
          AppLogger.recordMetric('offline.queue.success', 1, tags: {
            'tag': mutation.tag ?? mutation.path,
            'id': mutation.id,
            'retries': mutation.retryCount.toString(),
            'latency_ms': latency.inMilliseconds.toString(),
          });
          AppLogger.log(
              '[Offline] ✓ Replayed ${mutation.id} (${mutation.tag})');
          // Success → do NOT add back to toKeep
        } on DioException catch (e) {
          final isNetworkError = _isDioNetworkError(e);

          if (isNetworkError) {
            // Still offline / flaky — apply backoff and keep
            final newRetryCount = mutation.retryCount + 1;

            if (newRetryCount >= _maxRetries) {
              // Permanent failure
              final failed = mutation.copyWith(
                retryCount: newRetryCount,
                lastError: e.message ?? e.type.name,
                status: MutationStatus.failedPermanently,
              );
              toKeep.add(failed);
              AppLogger.recordMetric('offline.queue.permanent_failure', 1,
                  tags: {
                    'id': mutation.id,
                    'tag': mutation.tag ?? mutation.path,
                    'retries': newRetryCount.toString(),
                  });
              AppLogger.error(
                  '[Offline] ✗ Permanent failure ${mutation.id}', e);
            } else {
              final backoffSec = _backoffSeconds[
                  newRetryCount.clamp(0, _backoffSeconds.length - 1)];
              final nextRetry =
                  DateTime.now().add(Duration(seconds: backoffSec));
              toKeep.add(mutation.copyWith(
                retryCount: newRetryCount,
                nextRetryAt: nextRetry,
                lastError: e.message ?? e.type.name,
              ));
              AppLogger.recordMetric('offline.queue.failure', 1, tags: {
                'id': mutation.id,
                'retry': newRetryCount.toString(),
                'backoff_s': backoffSec.toString(),
              });
              AppLogger.log(
                  '[Offline] ↻ Network failure ${mutation.id}, retry $newRetryCount in ${backoffSec}s');
            }
          } else {
            // 4xx or other non-retriable — permanent failure
            final failed = mutation.copyWith(
              retryCount: mutation.retryCount + 1,
              lastError: e.response?.statusCode != null
                  ? 'HTTP ${e.response!.statusCode}'
                  : (e.message ?? 'unknown'),
              status: MutationStatus.failedPermanently,
            );
            toKeep.add(failed);
            AppLogger.recordMetric('offline.queue.permanent_failure', 1, tags: {
              'id': mutation.id,
              'reason': 'api_error_${e.response?.statusCode ?? "unknown"}',
            });
            AppLogger.error(
                '[Offline] ✗ Non-retriable error ${mutation.id}', e);
          }
        } catch (e) {
          // Unknown error — permanent failure
          final failed = mutation.copyWith(
            lastError: e.toString(),
            status: MutationStatus.failedPermanently,
          );
          toKeep.add(failed);
          AppLogger.error('[Offline] ✗ Unknown replay error ${mutation.id}', e);
        }
      }

      await _saveQueue(toKeep);
      AppLogger.log('[Offline] Replay done. Remaining=${toKeep.length}');
    } finally {
      _isReplaying = false;
    }
  }

  // ── Observability ─────────────────────────────────────────────────────────

  /// Current number of pending (non-permanent) mutations.
  Future<int> get queueDepth async {
    final q = await _getQueue();
    return q.where((m) => m.isPending).length;
  }

  /// All permanently failed mutations (for display in a sync-error UI).
  Future<List<OfflineMutation>> get permanentFailures async {
    final q = await _getQueue();
    return q.where((m) => m.isFailedPermanently).toList();
  }

  /// Clears the permanent failures from the queue.
  Future<void> clearPermanentFailures() async {
    final q = await _getQueue();
    await _saveQueue(q.where((m) => !m.isFailedPermanently).toList());
  }

  /// Clears the entire queue (e.g. on logout).
  Future<void> clearAll() async {
    await _saveQueue([]);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<List<OfflineMutation>> _getQueue() async {
    final cached =
        await cache.getList(_box, _key, maxAge: const Duration(days: 365));
    if (cached == null) return [];
    return cached.map(OfflineMutation.fromJson).toList();
  }

  Future<void> _saveQueue(List<OfflineMutation> queue) async {
    await cache.putList(_box, _key, queue.map((m) => m.toJson()).toList());
  }

  static bool _isDioNetworkError(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.unknown;
}
