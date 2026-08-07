import 'dart:async';

import '../core/cache/cache_manager.dart';
import '../core/network/websocket_manager.dart';
import '../core/network/api_result.dart';
import '../core/network/service_error_handler.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/offline_mutation.dart';
import '../core/offline/mutation_id.dart';
import '../data/models/models.dart';
import '../data/repositories/project_repository.dart' show ProjectRepository;
import '../data/repositories/stats_repository.dart';
import '../core/network/request_deduplicator.dart';
import '../core/cache/swr_helper.dart';

/// Service layer for project lifecycle management — now offline-first.
///
/// Writes (create / update / delete / member mutations) are queued when offline.
/// Reads use SWR cache-first strategy unchanged.
class ProjectService with ServiceErrorHandler {
  final ProjectRepository _repo;
  final StatsRepository _stats;
  final CacheManager _cache;
  final OfflineManager _offline;
  final WebSocketManager? _ws;

  static const _box = 'projects';

  ProjectService({
    required ProjectRepository repo,
    required StatsRepository stats,
    required CacheManager cache,
    required OfflineManager offline,
    WebSocketManager? ws,
  })  : _repo = repo,
        _stats = stats,
        _cache = cache,
        _offline = offline,
        _ws = ws {
    _swr = SwrHelper(_cache);
    _subscribeToWebSocket();
  }

  final RequestDeduplicator _dedup = RequestDeduplicator();
  late final SwrHelper _swr;
  StreamSubscription<SocketPayload>? _wsSub;

  void _subscribeToWebSocket() {
    if (_ws == null) return;
    _wsSub = _ws!.stream.listen((payload) {
      if (payload.event == SocketEvent.projectUpdate) {
        _invalidateProjectCaches();
      }
    });
  }

  Future<void> _invalidateProjectCaches() async {
    await _cache.invalidateBox(_box);
    await _cache.invalidateBox('home');
  }

  // ── Cached reads ──────────────────────────────────────────────────────────

  Future<ApiResult<List<ApiProject>>> listCompletedProjects() =>
      _dedup.deduplicate('list_completed_projects',
          () => guard(() => _repo.listCompletedProjects()));

  Future<ApiResult<List<ApiProject>>> listProjects({
    bool forceRefresh = false,
    void Function(List<ApiProject>)? onRefreshed,
  }) =>
      _dedup.deduplicate(
          'list_projects',
          () => guard(() async {
                if (forceRefresh) {
                  final projects = await _repo.listProjects();
                  await _cache.putList(
                      _box, 'all', projects.map((p) => p.toJson()).toList());
                  return projects;
                }

                return _swr
                    .withSwrList<ApiProject>(
                      boxName: _box,
                      key: 'all',
                      fetcher: () => _repo.listProjects(),
                      fromJson: ApiProject.fromJson,
                      toJson: (p) => p.toJson(),
                      onRefreshed: onRefreshed,
                    )
                    .then((res) =>
                        res.isSuccess ? res.data! : throw Exception(res.error));
              }));

  Future<ApiResult<ApiProject>> getProject(String id) => _dedup.deduplicate(
      'get_project_$id', () => guardWithRetry(() => _repo.getProject(id)));

  // ── Offline-first mutations ───────────────────────────────────────────────

  /// Creates a project. On network failure, queues for later replay.
  Future<ApiResult<ApiProject>> createProject(Map<String, dynamic> payload) =>
      guardWithOffline(
        () async {
          final project = await _repo.createProject(payload);
          await _invalidateProjectCaches();
          return project;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/projects',
          data: payload,
          tag: 'createProject',
        ),
        offlineManager: _offline,
      );

  /// Updates a project (PUT). On network failure, queues for later replay.
  Future<ApiResult<ApiProject>> updateProject(
          String id, Map<String, dynamic> payload) =>
      guardWithOffline(
        () async {
          final project = await _repo.updateProject(id, payload);
          await _invalidateProjectCaches();
          return project;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'PUT',
          path: '/api/projects/$id',
          data: payload,
          tag: 'updateProject',
        ),
        offlineManager: _offline,
      );

  /// Deletes a project. On network failure, queues for later replay.
  Future<ApiResult<void>> deleteProject(String id) => guardWithOffline(
        () async {
          await _repo.deleteProject(id);
          await _invalidateProjectCaches();
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'DELETE',
          path: '/api/projects/$id',
          tag: 'deleteProject',
        ),
        offlineManager: _offline,
      );

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<ApiResult<ApiProject>> completeProject(String id) => guardWithOffline(
        () async {
          final project = await _repo.completeProject(id);
          await _invalidateProjectCaches();
          return project;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/projects/$id/complete',
          tag: 'completeProject',
        ),
        offlineManager: _offline,
      );

  Future<ApiResult<ApiProject>> reopenProject(String id) => guardWithOffline(
        () async {
          final project = await _repo.reopenProject(id);
          await _invalidateProjectCaches();
          return project;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/projects/$id/reopen',
          tag: 'reopenProject',
        ),
        offlineManager: _offline,
      );

  // ── Members ────────────────────────────────────────────────────────────────

  Future<ApiResult<List<ApiUser>>> listMembers(String projectId) =>
      guard(() => _repo.listProjectMembers(projectId));

  Future<ApiResult<List<ApiProjectInvitation>>> listProjectInvitations(
    String projectId, {
    String status = '',
  }) =>
      guard(() => _repo.listProjectInvitations(projectId, status: status));

  Future<ApiResult<void>> addMember(String projectId, String userId) =>
      guardWithOffline(
        () => _repo.addProjectMember(projectId: projectId, userId: userId),
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/projects/$projectId/members',
          data: {'user_id': userId},
          tag: 'addMember',
        ),
        offlineManager: _offline,
      );

  Future<ApiResult<bool>> acceptInvitation(String invitationId) =>
      guard(() async {
        await _repo.acceptInvitation(invitationId);
        await _invalidateProjectCaches();
        return true;
      });

  Future<ApiResult<bool>> declineInvitation(String invitationId) =>
      guard(() async {
        await _repo.declineInvitation(invitationId);
        return true;
      });

  Future<ApiResult<void>> removeMember(String projectId, String userId) =>
      guardWithOffline(
        () async {
          await _repo.removeProjectMember(projectId: projectId, userId: userId);
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'DELETE',
          path: '/api/projects/$projectId/members/$userId',
          tag: 'removeMember',
        ),
        offlineManager: _offline,
      );

  /// Fetches all approved, non-guest users eligible to be added as project members.
  /// Results are not cached — always fresh so the list reflects current DB state.
  Future<ApiResult<List<ApiUser>>> getAvailableMembers({
    String search = '',
  }) =>
      guard(() => _repo.getAvailableMembers(search: search));

  // ── Combined data ──────────────────────────────────────────────────────────

  Future<ApiResult<ProjectWithStats>> getProjectWithStats(String id) =>
      guard(() async {
        final results = await Future.wait([
          _repo.getProject(id),
          _stats.getProjectStats(id),
        ]);
        return ProjectWithStats(
          project: results[0] as ApiProject,
          stats: results[1] as Map<String, dynamic>,
        );
      });

  void dispose() {
    _wsSub?.cancel();
  }
}

class ProjectWithStats {
  final ApiProject project;
  final Map<String, dynamic> stats;

  const ProjectWithStats({required this.project, required this.stats});
}
