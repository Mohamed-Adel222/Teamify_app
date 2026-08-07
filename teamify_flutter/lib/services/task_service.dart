import 'dart:async';

import '../core/cache/cache_manager.dart';
import '../core/network/api_result.dart';
import '../core/network/service_error_handler.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/offline_mutation.dart';
import '../core/offline/mutation_id.dart';
import '../data/models/models.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/comment_repository.dart';
import '../core/network/request_deduplicator.dart';
import '../core/cache/swr_helper.dart';
import '../core/network/websocket_manager.dart';

/// Service layer for task management — now offline-first.
///
/// All write mutations (create / update / delete) are automatically queued
/// when a network error is detected, and replayed when connectivity returns.
class TaskService with ServiceErrorHandler {
  final TaskRepository _repo;
  final CommentRepository _comments;
  final CacheManager _cache;
  final OfflineManager _offline;
  final WebSocketManager? _ws;

  static const _box = 'tasks';

  TaskService({
    required TaskRepository repo,
    required CommentRepository comments,
    required CacheManager cache,
    required OfflineManager offline,
    WebSocketManager? ws,
  })  : _repo = repo,
        _comments = comments,
        _cache = cache,
        _offline = offline,
        _ws = ws {
    _swr = SwrHelper(_cache);
    _subscribeToWebSocket();
  }

  final RequestDeduplicator _dedup = RequestDeduplicator();
  late final SwrHelper _swr;

  StreamSubscription<SocketPayload>? _wsSub;
  final _taskUpdateController = StreamController<void>.broadcast();
  Stream<void> get taskUpdateStream => _taskUpdateController.stream;

  void _subscribeToWebSocket() {
    if (_ws == null) return;
    _wsSub = _ws!.stream.listen((payload) {
      if (payload.event == SocketEvent.taskUpdate) {
        _invalidateTaskCaches();
        _taskUpdateController.add(null);
      }
    });
  }

  Future<void> _invalidateTaskCaches() async {
    await _cache.invalidate(_box, 'accessible');
    await _cache.invalidateBox(_box);
    await _cache.invalidateBox('home');
  }

  // ── Cached reads ────────────────────────────────────────────────────────

  Future<ApiResult<List<ApiTask>>> listTasks({
    required String projectId,
    bool forceRefresh = false,
    void Function(List<ApiTask>)? onRefreshed,
  }) =>
      _dedup.deduplicate(
          'list_tasks_$projectId',
          () => guard(() async {
                if (forceRefresh) {
                  final tasks = await _repo.listTasks(projectId: projectId);
                  await _cache.putList(_box, 'project_$projectId',
                      tasks.map((t) => t.toJson()).toList());
                  return tasks;
                }

                return _swr
                    .withSwrList<ApiTask>(
                      boxName: _box,
                      key: 'project_$projectId',
                      fetcher: () => _repo.listTasks(projectId: projectId),
                      fromJson: ApiTask.fromJson,
                      toJson: (t) => t.toJson(),
                      onRefreshed: onRefreshed,
                    )
                    .then((res) =>
                        res.isSuccess ? res.data! : throw Exception(res.error));
              }));

  /// All tasks across accessible projects — single API round-trip for AI Hub screens.
  Future<ApiResult<List<Map<String, dynamic>>>> listAccessibleTasks({
    int limit = 100,
    bool forceRefresh = false,
  }) =>
      _dedup.deduplicate(
          'accessible_tasks',
          () => guard(() async {
                const cacheKey = 'accessible';
                if (!forceRefresh) {
                  final cached = await _cache.getList(_box, cacheKey);
                  if (cached != null && cached.isNotEmpty) {
                    _repo.listAccessibleTasks(limit: limit).then((fresh) async {
                      await _cache.putList(_box, cacheKey, fresh);
                    }).catchError((_) {});
                    return cached
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                  }
                }
                final tasks = await _repo.listAccessibleTasks(limit: limit);
                await _cache.putList(_box, cacheKey, tasks);
                return tasks;
              }));

  Future<ApiResult<ApiTask>> getTask(String id) => _dedup.deduplicate(
      'get_task_$id', () => guardWithRetry(() => _repo.getTask(id)));

  // ── Offline-first mutations ──────────────────────────────────────────────

  /// Creates a task.  On network failure, queues for later replay.
  Future<ApiResult<ApiTask>> createTask(Map<String, dynamic> payload) =>
      guardWithOffline(
        () async {
          final task = await _repo.createTask(payload);
          await _invalidateTaskCaches();
          return task;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/tasks',
          data: payload,
          tag: 'createTask',
        ),
        offlineManager: _offline,
      );

  /// Updates a task (full PUT).  On network failure, queues for later replay.
  Future<ApiResult<ApiTask>> updateTask(
    String id,
    Map<String, dynamic> payload,
  ) =>
      guardWithOffline(
        () async {
          final task = await _repo.updateTask(id, payload);
          await _invalidateTaskCaches();
          return task;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'PUT',
          path: '/api/tasks/$id',
          data: payload,
          tag: 'updateTask',
        ),
        offlineManager: _offline,
      );

  /// Updates only the status of a task.  Queued offline when needed.
  Future<ApiResult<ApiTask>> updateStatus(String id, String status) =>
      guardWithOffline(
        () async {
          final task = await _repo.updateTaskStatus(id, status);
          await _invalidateTaskCaches();
          return task;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'PATCH',
          path: '/api/tasks/$id/status',
          data: {'status': status},
          tag: 'updateTaskStatus',
        ),
        offlineManager: _offline,
      );

  /// Deletes a task.  Queued offline when needed.
  Future<ApiResult<void>> deleteTask(String id) => guardWithOffline(
        () async {
          await _repo.deleteTask(id);
          await _invalidateTaskCaches();
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'DELETE',
          path: '/api/tasks/$id',
          tag: 'deleteTask',
        ),
        offlineManager: _offline,
      );

  // ── Comments ─────────────────────────────────────────────────────────────

  Future<ApiResult<List<Map<String, dynamic>>>> getComments(String taskId) =>
      guard(() => _comments.getTaskComments(taskId));

  Future<ApiResult<void>> addComment(String taskId, String content) =>
      guardWithOffline(
        () => _comments.addComment(taskId, content),
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/tasks/$taskId/comments',
          data: {'content': content},
          tag: 'addComment',
        ),
        offlineManager: _offline,
      );

  // ── Combined fetch ────────────────────────────────────────────────────────

  Future<ApiResult<TaskWithComments>> getTaskWithComments(String id) =>
      guard(() async {
        final results = await Future.wait([
          _repo.getTask(id),
          _comments.getTaskComments(id),
        ]);
        return TaskWithComments(
          task: results[0] as ApiTask,
          comments: results[1] as List<Map<String, dynamic>>,
        );
      });

  void dispose() {
    _wsSub?.cancel();
    _taskUpdateController.close();
  }
}

class TaskWithComments {
  final ApiTask task;
  final List<Map<String, dynamic>> comments;

  const TaskWithComments({required this.task, required this.comments});
}
