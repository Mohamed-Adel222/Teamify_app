import '../core/cache/cache_manager.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../data/models/models.dart' show ApiFile;
import '../data/repositories/admin_repository.dart';
import '../models/models.dart';

class AdminService with ServiceErrorHandler {
  final AdminRepository _repo;
  final CacheManager _cache;

  CacheManager get cache => _cache;

  AdminService(this._repo, this._cache);

  final RequestDeduplicator _dedup = RequestDeduplicator();

  // ── 1. Admin Dashboard ──────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> getDashboardStats() =>
      _dedup.deduplicate(
          'admin_dashboard', () => guard(() => _repo.getDashboardStats()));

  // ── 2. User Management ──────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> listUsers({
    String search = '',
    String status = '',
    String type = '',
    int page = 1,
    int perPage = 20,
  }) =>
      _dedup.deduplicate(
        'admin_users_${search}_${status}_${type}_$page',
        () => guard(() => _repo.listUsers(
              search: search,
              status: status,
              type: type,
              page: page,
              perPage: perPage,
            )),
      );

  Future<ApiResult<void>> updateUserStatus(String id, String action,
          {String reason = ''}) =>
      guard(() => _repo.updateUserStatus(id, action, reason: reason));

  Future<ApiResult<void>> changeUserRole(String id, String role) =>
      guard(() => _repo.changeUserRole(id, role));

  Future<ApiResult<void>> resetUserPassword(String id, String password) =>
      guard(() => _repo.resetUserPassword(id, password));

  Future<ApiResult<void>> deleteUser(String id) =>
      guard(() => _repo.deleteUser(id));

  Future<ApiResult<Map<String, dynamic>>> createUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) =>
      guard(() => _repo.createUser(
            fullName: fullName,
            email: email,
            password: password,
            role: role,
          ));

  // ── 3. Project Management ───────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> listProjects({
    String search = '',
    String status = '',
    int page = 1,
    int perPage = 20,
  }) =>
      _dedup.deduplicate(
        'admin_projects_${search}_${status}_$page',
        () => guard(() => _repo.listProjects(
              search: search,
              status: status,
              page: page,
              perPage: perPage,
            )),
      );

  Future<ApiResult<void>> reassignProject(
          String projectId, String newOwnerId) =>
      guard(() => _repo.reassignProject(projectId, newOwnerId));

  Future<ApiResult<void>> deleteProject(String projectId) =>
      guard(() => _repo.deleteProject(projectId));

  // ── 4. Task Management ──────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> listTasks({
    String search = '',
    int? projectId,
    int? assignedTo,
    String priority = '',
    String status = '',
    int page = 1,
    int perPage = 20,
  }) =>
      _dedup.deduplicate(
        'admin_tasks_${search}_${projectId}_${assignedTo}_${priority}_${status}_$page',
        () => guard(() => _repo.listTasks(
              search: search,
              projectId: projectId,
              assignedTo: assignedTo,
              priority: priority,
              status: status,
              page: page,
              perPage: perPage,
            )),
      );

  Future<ApiResult<void>> updateTask(String taskId,
          {String? status, String? assignedTo}) =>
      guard(() =>
          _repo.updateTask(taskId, status: status, assignedTo: assignedTo));

  Future<ApiResult<void>> deleteTask(String taskId) =>
      guard(() => _repo.deleteTask(taskId));

  // ── 5. AI Monitor ───────────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> getAiMetrics() => _dedup.deduplicate(
      'admin_ai_metrics', () => guard(() => _repo.getAiMetrics()));

  // ── 6. Disputes ─────────────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> listDisputes({
    String status = '',
    String category = '',
    int page = 1,
    int perPage = 20,
  }) =>
      _dedup.deduplicate(
        'admin_disputes_${status}_${category}_$page',
        () => guard(() => _repo.listDisputes(
              status: status,
              category: category,
              page: page,
              perPage: perPage,
            )),
      );

  Future<ApiResult<void>> resolveDispute(
          String disputeId, String action, String resolution) =>
      guard(() => _repo.resolveDispute(disputeId, action, resolution));

  // ── 7. Notifications Center ─────────────────────────────────────────────────
  Future<ApiResult<void>> broadcastNotification(
          String target, String title, String body, {String? userId}) =>
      guard(() =>
          _repo.broadcastNotification(target, title, body, userId: userId));

  // ── 8. File Management ──────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> listFiles({
    String search = '',
    int? ownerId,
    int page = 1,
    int perPage = 20,
  }) =>
      _dedup.deduplicate(
        'admin_files_${search}_${ownerId}_$page',
        () => guard(() => _repo.listFiles(
              search: search,
              ownerId: ownerId,
              page: page,
              perPage: perPage,
            )),
      );

  Future<ApiResult<void>> deleteFile(String fileId) =>
      guard(() => _repo.deleteFile(fileId));

  /// All platform files (admin Secure Files / file management).
  Future<ApiResult<List<ApiFile>>> listAllFiles({
    String search = '',
    int page = 1,
    int perPage = 100,
  }) =>
      guard(() async {
        final data = await _repo.listFiles(
          search: search,
          page: page,
          perPage: perPage,
        );
        final items = data['items'] as List? ?? [];
        return items
            .map((raw) => ApiFile.fromJson(raw as Map<String, dynamic>))
            .toList();
      });

  // ── 9. Activity Logs ────────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> listLogs({
    String action = '',
    String entity = '',
    String search = '',
    int? userId,
    int page = 1,
    int perPage = 50,
  }) =>
      _dedup.deduplicate(
        'admin_logs_${action}_${entity}_${search}_${userId}_$page',
        () => guard(() => _repo.listLogs(
              action: action,
              entity: entity,
              search: search,
              userId: userId,
              page: page,
              perPage: perPage,
            )),
      );

  // ── 10. Security Center ─────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> getSecuritySummary() =>
      _dedup.deduplicate('admin_security_summary',
          () => guard(() => _repo.getSecuritySummary()));

  Future<ApiResult<void>> revokeSessions(String userId) => guard(() async {
        await _repo.revokeSessions(userId);
        _dedup.clear();
      });

  // ── 11. Analytics ───────────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> getAnalyticsDetails() =>
      _dedup.deduplicate('admin_analytics_details',
          () => guard(() => _repo.getAnalyticsDetails()));

  // ── 12. Settings ────────────────────────────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> getSettings() => _dedup.deduplicate(
      'admin_settings', () => guard(() => _repo.getSettings()));

  Future<ApiResult<Map<String, dynamic>>> updateSettings(
          Map<String, dynamic> settings) =>
      guard(() async {
        final result = await _repo.updateSettings(settings);
        _dedup.clear();
        final saved = result['settings'] as Map<String, dynamic>? ?? result;
        return saved;
      });

  // ── 13. Compatibility / Legacy Wrappers ─────────────────────────────────────

  Future<ApiResult<Map<String, dynamic>>> getReportSummary() =>
      guard(() => _repo.getReportSummary());

  Future<ApiResult<List<SecurityAlert>>> listAlerts() async {
    final secResult = await getSecuritySummary();
    if (secResult.isFailure) {
      return ApiResult.failure(secResult.error ?? 'Error',
          statusCode: secResult.statusCode);
    }
    final data = secResult.data ?? {};
    final alertsList = data['alerts'] as List? ?? [];

    final List<SecurityAlert> mappedAlerts = alertsList.map((a) {
      final map = a as Map<String, dynamic>;
      return SecurityAlert(
        id: map['id']?.toString() ?? '',
        title: map['type']?.toString() ?? 'Security Anomaly',
        user: map['user_name']?.toString() ?? 'User #${map['user_id']}',
        description:
            map['details']?.toString() ?? 'Suspicious activity detected',
        risk: map['risk_level']?.toString() ?? 'High',
        status: map['status']?.toString() ?? 'Active',
        time: map['timestamp']?.toString() ?? '',
      );
    }).toList();

    return ApiResult.success(mappedAlerts);
  }

  Future<ApiResult<Map<String, dynamic>>> getAnalyticsOverview() =>
      guard(() => _repo.getAnalyticsOverview());

  Future<ApiResult<List<LoginLog>>> listLoginLogs({int perPage = 100}) =>
      guard(() async {
        final data = await _repo.listLoginLogs(perPage: perPage);
        final items = data['items'] as List? ?? [];
        return items.map((raw) {
          final log = raw as Map<String, dynamic>;
          final timestamp = log['timestamp']?.toString() ?? '';
          final date =
              timestamp.contains('T') ? timestamp.split('T').first : timestamp;
          final time = timestamp.contains('T')
              ? timestamp
                  .split('T')
                  .last
                  .split('.')
                  .first
                  .split('+')
                  .first
                  .split('Z')
                  .first
              : '';
          final statusRaw = log['status']?.toString().toLowerCase() ?? '';
          final userId = log['user_id'];
          final userName = log['user_name']?.toString() ??
              (userId != null ? 'User #$userId' : 'Unknown');
          final ip = log['ip_address']?.toString();
          return LoginLog(
            id: log['id']?.toString() ?? '',
            userName: userName,
            status: statusRaw == 'success' ? 'Success' : 'Failed',
            time: time,
            date: date,
            device: _loginLogDevice(log['device_info']?.toString()),
            ip: (ip != null && ip.isNotEmpty) ? ip : '—',
          );
        }).toList();
      });

  static String _loginLogDevice(String? userAgent) {
    if (userAgent == null || userAgent.isEmpty) return '—';
    if (userAgent.length <= 60) return userAgent;
    return '${userAgent.substring(0, 57)}...';
  }

  Future<ApiResult<void>> resolveAlert(String id) async {
    return guard(() => _repo.resolveAlert(id));
  }

  Future<ApiResult<Map<String, dynamic>>> getDisputeDetail(String id) =>
      guard(() => _repo.getDisputeDetail(id));

  Future<ApiResult<Map<String, dynamic>>> getAnalyticsTimeSeries(
          {String metric = 'users', int days = 30}) =>
      guard(() => _repo.getAnalyticsTimeSeries(metric: metric, days: days));

  Future<ApiResult<Map<String, dynamic>>> listBroadcastHistory(
          {int page = 1}) =>
      guard(() => _repo.listBroadcastHistory(page: page));

  Future<ApiResult<Map<String, dynamic>>> listRolePermissions() =>
      guard(() => _repo.listRolePermissions());

  Future<ApiResult<void>> updateRolePermissions(
          String role, Map<String, dynamic> permissions) =>
      guard(() => _repo.updateRolePermissions(role, permissions));

  Future<ApiResult<Map<String, dynamic>>> getRatingsLeaderboard({
    int page = 1,
    String search = '',
    String category = 'Overall',
    String timePeriod = 'All Time',
    String sortBy = 'Rank',
  }) =>
      guard(() => _repo.getRatingsLeaderboard(
            page: page,
            search: search,
            category: category,
            timePeriod: timePeriod,
            sortBy: sortBy,
          ));

  Future<ApiResult<Map<String, dynamic>>> getFeedbackLeaderboard({
    int page = 1,
    String search = '',
    String category = 'Overall',
    String timePeriod = 'All Time',
    String sortBy = 'Rank',
  }) =>
      guard(() => _repo.getFeedbackLeaderboard(
            page: page,
            search: search,
            category: category,
            timePeriod: timePeriod,
            sortBy: sortBy,
          ));

  Future<ApiResult<List<int>>> exportAnalytics(String type) =>
      guard(() => _repo.exportAnalytics(type));

  Future<ApiResult<Map<String, dynamic>>> listAuditLogs({
    String action = '',
    String severity = '',
    String search = '',
    int page = 1,
  }) =>
      guard(() => _repo.listAuditLogs(
          action: action, severity: severity, search: search, page: page));

  Future<ApiResult<List<dynamic>>> getAdminActivity() async {
    final logsResult = await listLogs(perPage: 10);
    if (logsResult.isFailure) {
      return ApiResult.failure(logsResult.error ?? 'Error',
          statusCode: logsResult.statusCode);
    }
    final items = logsResult.data?['items'] as List? ?? [];
    return ApiResult.success(items);
  }

  // ── 14. AI Monitor & Limits Wrappers ──────────────────────────────────────
  Future<ApiResult<Map<String, dynamic>>> getAiUsageOverview() =>
      guard(() => _repo.getAiUsageOverview());

  Future<ApiResult<Map<String, dynamic>>> getAiPlans() =>
      guard(() => _repo.getAiPlans());

  Future<ApiResult<void>> updateAiPlanLimits(String planId, Map<String, dynamic> limits) =>
      guard(() => _repo.updateAiPlanLimits(planId, limits));

  Future<ApiResult<Map<String, dynamic>>> getUserAiUsage({
    String search = '',
    String planId = '',
    String status = '',
    String sortBy = 'Usage',
    int page = 1,
  }) =>
      guard(() => _repo.getUserAiUsage(search: search, planId: planId, status: status, sortBy: sortBy, page: page));

  Future<ApiResult<Map<String, dynamic>>> getUserAiUsageDetails(String userId) =>
      guard(() => _repo.getUserAiUsageDetails(userId));

  Future<ApiResult<void>> updateUserAiLimits(String userId, Map<String, dynamic> limits) =>
      guard(() => _repo.updateUserAiLimits(userId, limits));

  Future<ApiResult<void>> resetUserDailyUsage(String userId) =>
      guard(() => _repo.resetUserDailyUsage(userId));

  Future<ApiResult<void>> resetUserMonthlyUsage(String userId) =>
      guard(() => _repo.resetUserMonthlyUsage(userId));

  Future<ApiResult<void>> changeUserPlan(String userId, String planId) =>
      guard(() => _repo.changeUserPlan(userId, planId));

  Future<ApiResult<void>> suspendUserAiAccess(String userId) =>
      guard(() => _repo.suspendUserAiAccess(userId));

  Future<ApiResult<void>> restoreUserAiAccess(String userId) =>
      guard(() => _repo.restoreUserAiAccess(userId));

  Future<ApiResult<Map<String, dynamic>>> getAiRequestLogs({
    String search = '',
    String plan = '',
    String status = '',
    int page = 1,
  }) =>
      guard(() => _repo.getAiRequestLogs(search: search, plan: plan, status: status, page: page));

  Future<ApiResult<Map<String, dynamic>>> getAiUsageAlerts() =>
      guard(() => _repo.getAiUsageAlerts());

  Future<ApiResult<void>> resolveAiUsageAlert(String alertId) =>
      guard(() => _repo.resolveAiUsageAlert(alertId));
}
