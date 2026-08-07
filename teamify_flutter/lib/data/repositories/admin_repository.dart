import 'package:dio/dio.dart';

import '../../config/app_config.dart';
import '../../core/network/api_client.dart';
import 'repository_helpers.dart';

class _MockAdminData {
  static List<Map<String, dynamic>> projects = [
    {'id': 'proj_1', 'name': 'Teamify Mobile', 'status': 'active', 'category': 'Mobile App', 'owner_id': 1},
    {'id': 'proj_2', 'name': 'Backend API', 'status': 'completed', 'category': 'Web', 'owner_id': 2},
  ];
  static List<Map<String, dynamic>> tasks = [
    {'id': 'task_1', 'title': 'Design UI', 'status': 'pending', 'priority': 'high', 'project_id': 'proj_1', 'assigned_to': 1},
    {'id': 'task_2', 'title': 'Setup DB', 'status': 'done', 'priority': 'medium', 'project_id': 'proj_2', 'assigned_to': 2},
  ];
  static List<Map<String, dynamic>> disputes = [
    {'id': 'disp_1', 'title': 'Payment issue', 'status': 'open', 'category': 'billing', 'resolution': ''},
  ];
  static List<Map<String, dynamic>> files = [
    {'id': 'file_1', 'name': 'design_v1.pdf', 'status': 'pending', 'owner_id': 1},
  ];
  static List<Map<String, dynamic>> logs = [
    {'id': 'log_1', 'action': 'login', 'entity': 'user', 'user_id': 1, 'timestamp': '2023-10-01T10:00:00Z'},
  ];
  static List<Map<String, dynamic>> notifications = [];
  static List<Map<String, dynamic>> users = [
    {
      'id': 'demo_user_1',
      'full_name': 'Alex Chen',
      'email': 'alex.chen@example.com',
      'role': 'freelancer',
      'user_type': 'freelancer',
      'status': 'active',
      'skills': 'Flutter, Dart',
      'avg_rating': 4.9,
      'rating_count': 120,
      'avg_score': 98.5,
      'feedback_count': 45,
      'completed_projects': 34,
      'completed_tasks': 210,
      'activity_score': 95,
      'created_at': '2023-01-15T00:00:00Z',
    },
    {
      'id': 'demo_user_2',
      'full_name': 'Sarah Miller',
      'email': 'sarah.m@example.com',
      'role': 'student',
      'user_type': 'student',
      'status': 'active',
      'skills': 'Python, Data Science',
      'avg_rating': 4.7,
      'rating_count': 85,
      'avg_score': 92.0,
      'feedback_count': 30,
      'completed_projects': 15,
      'completed_tasks': 110,
      'activity_score': 88,
      'created_at': '2023-05-20T00:00:00Z',
    },
    {
      'id': 'demo_user_3',
      'full_name': 'Marcus Johnson',
      'email': 'marcus.j@example.com',
      'role': 'team_leader',
      'user_type': 'team_leader',
      'status': 'active',
      'skills': 'Agile, Management',
      'avg_rating': 4.8,
      'rating_count': 210,
      'avg_score': 95.5,
      'feedback_count': 120,
      'completed_projects': 56,
      'completed_tasks': 400,
      'activity_score': 99,
      'created_at': '2022-11-10T00:00:00Z',
    },
    {
      'id': 'demo_user_4',
      'full_name': 'Elena Rodriguez',
      'email': 'elena.r@example.com',
      'role': 'freelancer',
      'user_type': 'freelancer',
      'status': 'active',
      'skills': 'UI/UX Design, Figma',
      'avg_rating': 5.0,
      'rating_count': 300,
      'avg_score': 99.5,
      'feedback_count': 150,
      'completed_projects': 80,
      'completed_tasks': 520,
      'activity_score': 92,
      'created_at': '2024-02-01T00:00:00Z',
    },
  ];
  
  static Map<String, dynamic> settings = {
    'ai_model': 'gpt-4',
    'daily_limit': 1000,
    'maintenance_mode': false,
  };

  static List<Map<String, dynamic>> aiPlans = [
    {
      'id': 'plan_free',
      'name': 'Free',
      'daily_limit': 10,
      'monthly_limit': 100,
      'token_limit': 10000,
      'features': ['Basic Chat', 'Code Completion'],
      'subscribers': 1200,
      'estimated_cost': 0.50,
    },
    {
      'id': 'plan_premium',
      'name': 'Premium',
      'daily_limit': 100,
      'monthly_limit': 1000,
      'token_limit': 100000,
      'features': ['Basic Chat', 'Code Completion', 'Advanced Generation', 'Priority Support'],
      'subscribers': 300,
      'estimated_cost': 5.00,
    },
    {
      'id': 'plan_business',
      'name': 'Business',
      'daily_limit': 1000,
      'monthly_limit': 10000,
      'token_limit': 1000000,
      'features': ['Basic Chat', 'Code Completion', 'Advanced Generation', 'Priority Support', 'Custom Models'],
      'subscribers': 50,
      'estimated_cost': 50.00,
    }
  ];

  static List<Map<String, dynamic>> aiUsage = users.map((u) {
    bool isFree = u['id'] == 'demo_user_1' || u['id'] == 'demo_user_2';
    String planId = isFree ? 'plan_free' : 'plan_premium';
    int dailyLimit = isFree ? 10 : 100;
    int monthlyLimit = isFree ? 100 : 1000;
    int tokenLimit = isFree ? 10000 : 100000;
    
    int usedToday = isFree ? 9 : 10;
    int usedMonth = isFree ? 95 : 150;
    int tokensUsed = isFree ? 8500 : 15000;
    
    String status = 'Normal';
    if (usedToday >= dailyLimit || usedMonth >= monthlyLimit || tokensUsed >= tokenLimit) {
      status = 'Limit Reached';
    } else if (usedToday >= dailyLimit * 0.8 || usedMonth >= monthlyLimit * 0.8 || tokensUsed >= tokenLimit * 0.8) {
      status = 'Near Limit';
    }

    return {
      'user_id': u['id'],
      'user_name': u['full_name'],
      'username': u['email'],
      'role': u['role'],
      'plan_id': planId,
      'plan_name': isFree ? 'Free' : 'Premium',
      'daily_limit': dailyLimit,
      'monthly_limit': monthlyLimit,
      'token_limit': tokenLimit,
      'used_today': usedToday,
      'used_month': usedMonth,
      'tokens_used': tokensUsed,
      'estimated_cost': tokensUsed * 0.00002,
      'status': status,
      'features': isFree ? ['Basic Chat', 'Code Completion'] : ['Basic Chat', 'Code Completion', 'Advanced Generation', 'Priority Support'],
      'recent_requests': [
        {'id': 'req_1', 'feature': 'Basic Chat', 'timestamp': '2023-10-01T10:05:00Z', 'status': 'success', 'tokens': 150},
      ]
    };
  }).toList();

  static List<Map<String, dynamic>> aiLogs = [
    {
      'id': 'log_1',
      'user_name': 'Alex Chen',
      'plan_name': 'Premium',
      'feature': 'Advanced Generation',
      'timestamp': '2023-10-01T10:05:00Z',
      'status': 'success',
      'tokens': 150,
      'latency': 1.2,
      'cost': 0.003,
      'error': null,
    },
    {
      'id': 'log_2',
      'user_name': 'Sarah Miller',
      'plan_name': 'Free',
      'feature': 'Code Completion',
      'timestamp': '2023-10-01T10:15:00Z',
      'status': 'failed',
      'tokens': 0,
      'latency': 0.5,
      'cost': 0.0,
      'error': 'Rate limit exceeded',
    },
  ];

  static List<Map<String, dynamic>> aiAlerts = [
    {
      'id': 'alert_1',
      'type': 'Limit Reached',
      'message': 'Sarah Miller reached their daily AI limit.',
      'resolved': false,
      'timestamp': '2023-10-01T10:15:00Z',
    },
    {
      'id': 'alert_2',
      'type': 'High Latency',
      'message': 'Average response time exceeds 3 seconds globally.',
      'resolved': false,
      'timestamp': '2023-10-01T09:00:00Z',
    }
  ];
}

class AdminRepository {
  final ApiClient _client;

  AdminRepository(this._client);

  // ── 1. Admin Dashboard ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getDashboardStats() async {
    if (AppConfig.isDemoMode) {
      return {
        'cards': {
          'system_health': 99,
          'storage_usage_mb': 124.5,
          'total_users': _MockAdminData.users.length,
          'active_projects': _MockAdminData.projects.length,
          'resolved_disputes': 18,
          'security_score': 95,
        },
        'charts': {
          'user_growth': [
            {'month': 'Jan', 'count': 40},
            {'month': 'Feb', 'count': 65},
            {'month': 'Mar', 'count': 90},
            {'month': 'Apr', 'count': 120},
            {'month': 'May', 'count': 156},
          ],
        },
      };
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/dashboard');
    return responseMap(response.data);
  }

  // ── 2. User Management ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listUsers({
    String search = '',
    String status = '',
    String type = '',
    int page = 1,
    int perPage = 20,
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = _MockAdminData.users;
      if (search.isNotEmpty) filtered = filtered.where((u) => (u['full_name'] as String).toLowerCase().contains(search.toLowerCase())).toList();
      if (status.isNotEmpty) filtered = filtered.where((u) => u['status'] == status).toList();
      if (type.isNotEmpty) filtered = filtered.where((u) => u['user_type'] == type).toList();
      return {'users': filtered, 'total': filtered.length};
    }
    final response = await _client.get<Map<String, dynamic>>(
      '/admin/users',
      queryParameters: {
        'search': search, 'status': status, 'user_type': type, 'page': page, 'per_page': perPage,
      },
    );
    return responseMap(response.data);
  }

  Future<void> updateUserStatus(String id, String action, {String reason = ''}) async {
    if (AppConfig.isDemoMode) {
      final idx = _MockAdminData.users.indexWhere((u) => u['id'] == id);
      if (idx != -1) _MockAdminData.users[idx]['status'] = action;
      return;
    }
    await _client.patch<dynamic>('/admin/users/$id/status', data: {'action': action, 'reason': reason});
  }

  Future<void> changeUserRole(String id, String role) async {
    if (AppConfig.isDemoMode) {
      final idx = _MockAdminData.users.indexWhere((u) => u['id'] == id);
      if (idx != -1) _MockAdminData.users[idx]['role'] = role;
      return;
    }
    await _client.patch<dynamic>('/admin/users/$id/role', data: {'role': role});
  }

  Future<void> resetUserPassword(String id, String password) async {
    if (AppConfig.isDemoMode) return;
    await _client.patch<dynamic>('/admin/users/$id/reset-password', data: {'password': password});
  }

  Future<void> deleteUser(String id) async {
    if (AppConfig.isDemoMode) {
      _MockAdminData.users.removeWhere((u) => u['id'] == id);
      return;
    }
    await _client.delete<dynamic>('/admin/users/$id');
  }

  Future<Map<String, dynamic>> createUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    if (AppConfig.isDemoMode) {
      final user = {'id': 'user_${DateTime.now().millisecondsSinceEpoch}', 'full_name': fullName, 'email': email, 'role': role, 'user_type': role, 'status': 'active'};
      _MockAdminData.users.add(user);
      return user;
    }
    final response = await _client.post<Map<String, dynamic>>('/admin/users', data: {'full_name': fullName, 'email': email, 'password': password, 'role': role});
    return responseMap(response.data);
  }

  // ── 3. Project Management ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> listProjects({
    String search = '',
    String status = '',
    int page = 1,
    int perPage = 20,
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = _MockAdminData.projects;
      if (search.isNotEmpty) filtered = filtered.where((p) => (p['name'] as String).toLowerCase().contains(search.toLowerCase())).toList();
      if (status.isNotEmpty) filtered = filtered.where((p) => p['status'] == status).toList();
      return {'items': filtered, 'total': filtered.length, 'pages': 1}; // Note: project screen expects 'items' and 'pages'
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/projects', queryParameters: {'search': search, 'status': status, 'page': page, 'per_page': perPage});
    return responseMap(response.data);
  }

  Future<void> reassignProject(String projectId, String newOwnerId) async {
    if (AppConfig.isDemoMode) {
      final idx = _MockAdminData.projects.indexWhere((p) => p['id'] == projectId);
      if (idx != -1) _MockAdminData.projects[idx]['owner_id'] = newOwnerId;
      return;
    }
    await _client.patch<dynamic>('/admin/projects/$projectId/reassign', data: {'owner_id': int.tryParse(newOwnerId)});
  }

  Future<void> deleteProject(String projectId) async {
    if (AppConfig.isDemoMode) {
      _MockAdminData.projects.removeWhere((p) => p['id'] == projectId);
      return;
    }
    await _client.delete<dynamic>('/admin/projects/$projectId');
  }

  // ── 4. Task Management ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listTasks({
    String search = '',
    int? projectId,
    int? assignedTo,
    String priority = '',
    String status = '',
    int page = 1,
    int perPage = 20,
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = _MockAdminData.tasks;
      if (search.isNotEmpty) filtered = filtered.where((t) => (t['title'] as String).toLowerCase().contains(search.toLowerCase())).toList();
      if (status.isNotEmpty) filtered = filtered.where((t) => t['status'] == status).toList();
      if (priority.isNotEmpty) filtered = filtered.where((t) => t['priority'] == priority).toList();
      return {'items': filtered, 'total': filtered.length, 'pages': 1};
    }
    final Map<String, dynamic> qParams = {'search': search, 'priority': priority, 'status': status, 'page': page, 'per_page': perPage};
    if (projectId != null) qParams['project_id'] = projectId;
    if (assignedTo != null) qParams['assigned_to'] = assignedTo;
    final response = await _client.get<Map<String, dynamic>>('/admin/tasks', queryParameters: qParams);
    return responseMap(response.data);
  }

  Future<void> updateTask(String taskId, {String? status, String? assignedTo}) async {
    if (AppConfig.isDemoMode) {
      final idx = _MockAdminData.tasks.indexWhere((t) => t['id'] == taskId);
      if (idx != -1) {
        if (status != null) _MockAdminData.tasks[idx]['status'] = status;
        if (assignedTo != null) _MockAdminData.tasks[idx]['assigned_to'] = assignedTo;
      }
      return;
    }
    final Map<String, dynamic> data = {};
    if (status != null) data['status'] = status;
    if (assignedTo != null) data['assigned_to'] = int.tryParse(assignedTo);
    await _client.patch<dynamic>('/admin/tasks/$taskId', data: data);
  }

  Future<void> deleteTask(String taskId) async {
    if (AppConfig.isDemoMode) {
      _MockAdminData.tasks.removeWhere((t) => t['id'] == taskId);
      return;
    }
    await _client.delete<dynamic>('/admin/tasks/$taskId');
  }

  // ── 5. AI Monitor ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getAiMetrics() async {
    if (AppConfig.isDemoMode) {
      return {
        'total_requests': 15024,
        'average_latency_ms': 250,
        'success_rate': 99.8,
        'active_models': ['gpt-4', 'gpt-3.5', 'claude-3'],
        'recent_failures': 12
      };
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/ai/metrics');
    return responseMap(response.data);
  }

  // ── 6. Disputes ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listDisputes({
    String status = '',
    String category = '',
    int page = 1,
    int perPage = 20,
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = _MockAdminData.disputes;
      if (status.isNotEmpty) filtered = filtered.where((d) => d['status'] == status).toList();
      if (category.isNotEmpty) filtered = filtered.where((d) => d['category'] == category).toList();
      return {'items': filtered, 'total': filtered.length, 'pages': 1};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/disputes', queryParameters: {'status': status, 'category': category, 'page': page, 'per_page': perPage});
    return responseMap(response.data);
  }

  Future<void> resolveDispute(String disputeId, String action, String resolution) async {
    if (AppConfig.isDemoMode) {
      final idx = _MockAdminData.disputes.indexWhere((d) => d['id'] == disputeId);
      if (idx != -1) {
        _MockAdminData.disputes[idx]['status'] = action; // 'resolved' or 'rejected'
        _MockAdminData.disputes[idx]['resolution'] = resolution;
      }
      return;
    }
    await _client.patch<dynamic>('/admin/disputes/$disputeId/resolve', data: {'action': action, 'resolution': resolution});
  }

  // ── 7. Notifications Center ─────────────────────────────────────────────────
  Future<void> broadcastNotification(String target, String title, String body, {String? userId}) async {
    if (AppConfig.isDemoMode) {
      _MockAdminData.notifications.add({
        'id': 'notif_${DateTime.now().millisecondsSinceEpoch}',
        'target': target,
        'title': title,
        'body': body,
        'user_id': userId,
        'sent_at': DateTime.now().toIso8601String()
      });
      return;
    }
    final Map<String, dynamic> data = {'target': target, 'title': title, 'body': body};
    if (userId != null) data['user_id'] = int.tryParse(userId);
    await _client.post<dynamic>('/admin/notifications', data: data);
  }

  // ── 8. File Management ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listFiles({
    String search = '',
    int? ownerId,
    int page = 1,
    int perPage = 20,
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = _MockAdminData.files;
      if (search.isNotEmpty) filtered = filtered.where((f) => (f['name'] as String).toLowerCase().contains(search.toLowerCase())).toList();
      return {'items': filtered, 'total': filtered.length, 'pages': 1};
    }
    final Map<String, dynamic> qParams = {'search': search, 'page': page, 'per_page': perPage};
    if (ownerId != null) qParams['owner_id'] = ownerId;
    final response = await _client.get<Map<String, dynamic>>('/admin/files', queryParameters: qParams);
    return responseMap(response.data);
  }

  Future<void> deleteFile(String fileId) async {
    if (AppConfig.isDemoMode) {
      _MockAdminData.files.removeWhere((f) => f['id'] == fileId);
      return;
    }
    await _client.delete<dynamic>('/admin/files/$fileId');
  }

  // ── 9. Activity Logs ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> listLogs({
    String action = '',
    String entity = '',
    String search = '',
    int? userId,
    int page = 1,
    int perPage = 50,
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = _MockAdminData.logs;
      if (action.isNotEmpty) filtered = filtered.where((l) => l['action'] == action).toList();
      if (entity.isNotEmpty) filtered = filtered.where((l) => l['entity'] == entity).toList();
      return {'items': filtered, 'total': filtered.length, 'pages': 1};
    }
    final Map<String, dynamic> qParams = {'action': action, 'entity': entity, 'search': search, 'page': page, 'per_page': perPage};
    if (userId != null) qParams['user_id'] = userId;
    final response = await _client.get<Map<String, dynamic>>('/admin/logs', queryParameters: qParams);
    return responseMap(response.data);
  }

  Future<void> resolveAlert(String id) async {
    if (AppConfig.isDemoMode) return;
    await _client.patch<dynamic>('/admin/alerts/$id/resolve');
  }

  Future<Map<String, dynamic>> listAuditLogs({
    String action = '',
    String severity = '',
    String search = '',
    int page = 1,
    int perPage = 50,
  }) async {
    if (AppConfig.isDemoMode) {
      return {'items': _MockAdminData.logs, 'total': _MockAdminData.logs.length, 'pages': 1};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/audit-logs', queryParameters: {'action': action, 'severity': severity, 'search': search, 'page': page, 'per_page': perPage});
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getDisputeDetail(String id) async {
    if (AppConfig.isDemoMode) {
      final d = _MockAdminData.disputes.firstWhere((d) => d['id'] == id, orElse: () => {});
      return d;
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/disputes/$id');
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getAnalyticsTimeSeries({String metric = 'users', int days = 30}) async {
    if (AppConfig.isDemoMode) {
      return {'series': []};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/analytics/time-series', queryParameters: {'metric': metric, 'days': days});
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> listBroadcastHistory({int page = 1, int perPage = 20}) async {
    if (AppConfig.isDemoMode) {
      return {'items': _MockAdminData.notifications, 'total': _MockAdminData.notifications.length, 'pages': 1};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/notifications/history', queryParameters: {'page': page, 'per_page': perPage});
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> listRolePermissions() async {
    if (AppConfig.isDemoMode) return {'roles': []};
    final response = await _client.get<Map<String, dynamic>>('/admin/roles');
    return responseMap(response.data);
  }

  Future<void> updateRolePermissions(String role, Map<String, dynamic> permissions) async {
    if (AppConfig.isDemoMode) return;
    await _client.put<dynamic>('/admin/roles/$role', data: {'permissions': permissions});
  }

  Future<Map<String, dynamic>> getRatingsLeaderboard({
    int page = 1,
    String search = '',
    String category = 'Overall',
    String timePeriod = 'All Time',
    String sortBy = 'Rank',
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = List<Map<String, dynamic>>.from(_MockAdminData.users);
      if (search.isNotEmpty) {
        final s = search.toLowerCase();
        filtered = filtered.where((u) => 
          (u['full_name']?.toString().toLowerCase().contains(s) ?? false) ||
          (u['skills']?.toString().toLowerCase().contains(s) ?? false) ||
          (u['role']?.toString().toLowerCase().contains(s) ?? false)
        ).toList();
      }
      
      if (category == 'Freelancers') {
        filtered = filtered.where((u) => u['role'] == 'freelancer').toList();
      } else if (category == 'Students') {
        filtered = filtered.where((u) => u['role'] == 'student').toList();
      } else if (category == 'Team Leaders') {
        filtered = filtered.where((u) => u['role'] == 'team_leader').toList();
      } else if (category == 'Top Rated') {
        filtered = filtered.where((u) => (u['avg_rating'] ?? 0) >= 4.8).toList();
      } else if (category == 'Most Active') {
        filtered = filtered.where((u) => (u['activity_score'] ?? 0) >= 90).toList();
      }

      // Time period mock filtering (simplified)
      final now = DateTime.now();
      if (timePeriod == 'This Week') {
        filtered = filtered.where((u) => DateTime.parse(u['created_at']).isAfter(now.subtract(const Duration(days: 7)))).toList();
      } else if (timePeriod == 'This Month') {
        filtered = filtered.where((u) => DateTime.parse(u['created_at']).isAfter(now.subtract(const Duration(days: 30)))).toList();
      } else if (timePeriod == 'This Year') {
        filtered = filtered.where((u) => DateTime.parse(u['created_at']).isAfter(now.subtract(const Duration(days: 365)))).toList();
      }

      // Sorting
      if (sortBy == 'Rating') {
        filtered.sort((a, b) => (b['avg_rating'] as num).compareTo(a['avg_rating'] as num));
      } else if (sortBy == 'Completed projects') {
        filtered.sort((a, b) => (b['completed_projects'] as num).compareTo(a['completed_projects'] as num));
      } else if (sortBy == 'Activity') {
        filtered.sort((a, b) => (b['activity_score'] as num).compareTo(a['activity_score'] as num));
      } else {
        // Rank (default: combination of rating and activity)
        filtered.sort((a, b) => ((b['avg_rating'] * 10 + b['activity_score']) as num).compareTo((a['avg_rating'] * 10 + a['activity_score']) as num));
      }

      return {'items': filtered, 'total': filtered.length, 'pages': 1};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/ratings/leaderboard', queryParameters: {
      'page': page, 'search': search, 'category': category, 'time_period': timePeriod, 'sort_by': sortBy
    });
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getFeedbackLeaderboard({
    int page = 1,
    String search = '',
    String category = 'Overall',
    String timePeriod = 'All Time',
    String sortBy = 'Rank',
  }) async {
    if (AppConfig.isDemoMode) {
      // Reuse the same mock filtering logic but sort primarily by avg_score
      var filtered = List<Map<String, dynamic>>.from(_MockAdminData.users);
      if (search.isNotEmpty) {
        final s = search.toLowerCase();
        filtered = filtered.where((u) => 
          (u['full_name']?.toString().toLowerCase().contains(s) ?? false) ||
          (u['skills']?.toString().toLowerCase().contains(s) ?? false) ||
          (u['role']?.toString().toLowerCase().contains(s) ?? false)
        ).toList();
      }
      if (category == 'Freelancers') filtered = filtered.where((u) => u['role'] == 'freelancer').toList();
      else if (category == 'Students') filtered = filtered.where((u) => u['role'] == 'student').toList();
      else if (category == 'Team Leaders') filtered = filtered.where((u) => u['role'] == 'team_leader').toList();

      if (sortBy == 'Rating') {
        filtered.sort((a, b) => (b['avg_score'] as num).compareTo(a['avg_score'] as num));
      } else {
        filtered.sort((a, b) => ((b['avg_score'] * 10 + b['activity_score']) as num).compareTo((a['avg_score'] * 10 + a['activity_score']) as num));
      }

      return {'items': filtered, 'total': filtered.length, 'pages': 1};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/feedback/leaderboard', queryParameters: {
      'page': page, 'search': search, 'category': category, 'time_period': timePeriod, 'sort_by': sortBy
    });
    return responseMap(response.data);
  }

  Future<List<int>> exportAnalytics(String type) async {
    if (AppConfig.isDemoMode) return [0, 1, 2];
    final response = await _client.get<List<int>>('/admin/analytics/export', queryParameters: {'type': type, 'format': 'csv'}, options: Options(responseType: ResponseType.bytes, headers: const {'Accept': 'text/csv'}));
    return response.data ?? <int>[];
  }

  // ── 10. Security Center ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSecuritySummary() async {
    if (AppConfig.isDemoMode) return {'score': 95};
    final response = await _client.get<Map<String, dynamic>>('/admin/security');
    return responseMap(response.data);
  }

  Future<void> revokeSessions(String userId) async {
    if (AppConfig.isDemoMode) return;
    await _client.post<dynamic>('/admin/security/revoke-session/$userId');
  }

  Future<Map<String, dynamic>> listLoginLogs({
    String status = '',
    String ip = '',
    int? userId,
    int page = 1,
    int perPage = 100,
  }) async {
    if (AppConfig.isDemoMode) return {'items': [], 'total': 0, 'pages': 1};
    final Map<String, dynamic> qParams = {'page': page, 'per_page': perPage};
    if (status.isNotEmpty) qParams['status'] = status;
    if (ip.isNotEmpty) qParams['ip'] = ip;
    if (userId != null) qParams['user_id'] = userId;
    final response = await _client.get<Map<String, dynamic>>('/admin/login-logs', queryParameters: qParams);
    return responseMap(response.data);
  }

  // ── 11. Analytics ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getAnalyticsOverview() async {
    if (AppConfig.isDemoMode) {
      return {
        'users': {'total': 1205, 'active': 950},
        'projects': {'total': 340, 'active': 112, 'by_status': {'active': 112, 'completed': 200, 'pending': 28}},
        'tasks': {'total': 1500, 'done': 1200, 'overdue': 45, 'completion_rate': 80.0},
      };
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/analytics/overview');
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getReportSummary() async {
    if (AppConfig.isDemoMode) return {};
    final response = await _client.get<Map<String, dynamic>>('/admin/reports/summary');
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getAnalyticsDetails() async {
    if (AppConfig.isDemoMode) return {};
    final response = await _client.get<Map<String, dynamic>>('/admin/analytics');
    return responseMap(response.data);
  }

  // ── 12. Settings ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSettings() async {
    if (AppConfig.isDemoMode) {
      return _MockAdminData.settings;
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/settings');
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> settings) async {
    if (AppConfig.isDemoMode) {
      _MockAdminData.settings.addAll(settings);
      return _MockAdminData.settings;
    }
    final response = await _client.put<Map<String, dynamic>>('/admin/settings', data: settings);
    return responseMap(response.data);
  }

  // ── 13. AI Monitor & Limits ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> getAiUsageOverview() async {
    if (AppConfig.isDemoMode) {
      return {
        'metrics': {
          'total_ai_requests': 1250,
          'total_ai_requests_month': 35000,
          'active_ai_users': 45,
          'users_reached_limits': 5,
          'failed_ai_calls': 12,
          'average_response_time': 1.2,
          'estimated_ai_cost': 45.50,
          'token_usage': 2500000,
        }
      };
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/ai/overview');
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getAiPlans() async {
    if (AppConfig.isDemoMode) return {'items': _MockAdminData.aiPlans};
    final response = await _client.get<Map<String, dynamic>>('/admin/ai/plans');
    return responseMap(response.data);
  }

  Future<void> updateAiPlanLimits(String planId, Map<String, dynamic> limits) async {
    if (AppConfig.isDemoMode) {
      final index = _MockAdminData.aiPlans.indexWhere((p) => p['id'] == planId);
      if (index != -1) {
        _MockAdminData.aiPlans[index] = {..._MockAdminData.aiPlans[index], ...limits};
      }
      return;
    }
    await _client.put<dynamic>('/admin/ai/plans/$planId', data: limits);
  }

  Future<Map<String, dynamic>> getUserAiUsage({
    String search = '',
    String planId = '',
    String status = '',
    String sortBy = 'Usage',
    int page = 1,
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = List<Map<String, dynamic>>.from(_MockAdminData.aiUsage);
      if (search.isNotEmpty) {
        filtered = filtered.where((u) => 
          (u['user_name']?.toString().toLowerCase().contains(search.toLowerCase()) ?? false) ||
          (u['username']?.toString().toLowerCase().contains(search.toLowerCase()) ?? false)
        ).toList();
      }
      if (planId.isNotEmpty && planId != 'All') filtered = filtered.where((u) => u['plan_name'] == planId).toList();
      if (status.isNotEmpty && status != 'All') filtered = filtered.where((u) => u['status'] == status).toList();

      if (sortBy == 'Tokens') {
        filtered.sort((a, b) => (b['tokens_used'] as num).compareTo(a['tokens_used'] as num));
      } else if (sortBy == 'Cost') {
        filtered.sort((a, b) => (b['estimated_cost'] as num).compareTo(a['estimated_cost'] as num));
      } else if (sortBy == 'Remaining') {
        filtered.sort((a, b) => ((a['monthly_limit'] as num) - (a['used_month'] as num)).compareTo((b['monthly_limit'] as num) - (b['used_month'] as num)));
      } else {
        filtered.sort((a, b) => (b['used_month'] as num).compareTo(a['used_month'] as num));
      }
      return {'items': filtered, 'total': filtered.length, 'pages': 1};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/ai/users', queryParameters: {
      'search': search, 'plan_id': planId, 'status': status, 'sort_by': sortBy, 'page': page
    });
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getUserAiUsageDetails(String userId) async {
    if (AppConfig.isDemoMode) {
      return _MockAdminData.aiUsage.firstWhere((u) => u['user_id'] == userId, orElse: () => {});
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/ai/users/$userId');
    return responseMap(response.data);
  }

  Future<void> updateUserAiLimits(String userId, Map<String, dynamic> limits) async {
    if (AppConfig.isDemoMode) {
      final index = _MockAdminData.aiUsage.indexWhere((u) => u['user_id'] == userId);
      if (index != -1) _MockAdminData.aiUsage[index] = {..._MockAdminData.aiUsage[index], ...limits};
      return;
    }
    await _client.put<dynamic>('/admin/ai/users/$userId/limits', data: limits);
  }

  Future<void> resetUserDailyUsage(String userId) async {
    if (AppConfig.isDemoMode) {
      final index = _MockAdminData.aiUsage.indexWhere((u) => u['user_id'] == userId);
      if (index != -1) {
        _MockAdminData.aiUsage[index]['used_today'] = 0;
        _MockAdminData.aiUsage[index]['status'] = 'Normal';
      }
      return;
    }
    await _client.post<dynamic>('/admin/ai/users/$userId/reset-daily');
  }

  Future<void> resetUserMonthlyUsage(String userId) async {
    if (AppConfig.isDemoMode) {
      final index = _MockAdminData.aiUsage.indexWhere((u) => u['user_id'] == userId);
      if (index != -1) {
        _MockAdminData.aiUsage[index]['used_month'] = 0;
        _MockAdminData.aiUsage[index]['tokens_used'] = 0;
        _MockAdminData.aiUsage[index]['status'] = 'Normal';
      }
      return;
    }
    await _client.post<dynamic>('/admin/ai/users/$userId/reset-monthly');
  }

  Future<void> changeUserPlan(String userId, String planId) async {
    if (AppConfig.isDemoMode) {
      final index = _MockAdminData.aiUsage.indexWhere((u) => u['user_id'] == userId);
      final plan = _MockAdminData.aiPlans.firstWhere((p) => p['id'] == planId || p['name'] == planId, orElse: () => _MockAdminData.aiPlans.first);
      if (index != -1) {
        _MockAdminData.aiUsage[index]['plan_id'] = plan['id'];
        _MockAdminData.aiUsage[index]['plan_name'] = plan['name'];
        _MockAdminData.aiUsage[index]['daily_limit'] = plan['daily_limit'];
        _MockAdminData.aiUsage[index]['monthly_limit'] = plan['monthly_limit'];
        _MockAdminData.aiUsage[index]['token_limit'] = plan['token_limit'];
        _MockAdminData.aiUsage[index]['features'] = plan['features'];
        _MockAdminData.aiUsage[index]['status'] = 'Normal';
      }
      return;
    }
    await _client.put<dynamic>('/admin/ai/users/$userId/plan', data: {'plan_id': planId});
  }

  Future<void> suspendUserAiAccess(String userId) async {
    if (AppConfig.isDemoMode) {
      final index = _MockAdminData.aiUsage.indexWhere((u) => u['user_id'] == userId);
      if (index != -1) _MockAdminData.aiUsage[index]['status'] = 'Suspended';
      return;
    }
    await _client.post<dynamic>('/admin/ai/users/$userId/suspend');
  }

  Future<void> restoreUserAiAccess(String userId) async {
    if (AppConfig.isDemoMode) {
      final index = _MockAdminData.aiUsage.indexWhere((u) => u['user_id'] == userId);
      if (index != -1) {
        _MockAdminData.aiUsage[index]['status'] = 'Normal';
      }
      return;
    }
    await _client.post<dynamic>('/admin/ai/users/$userId/restore');
  }

  Future<Map<String, dynamic>> getAiRequestLogs({
    String search = '',
    String plan = '',
    String status = '',
    int page = 1,
  }) async {
    if (AppConfig.isDemoMode) {
      var filtered = List<Map<String, dynamic>>.from(_MockAdminData.aiLogs);
      if (search.isNotEmpty) {
        filtered = filtered.where((l) => 
          (l['user_name']?.toString().toLowerCase().contains(search.toLowerCase()) ?? false) ||
          (l['feature']?.toString().toLowerCase().contains(search.toLowerCase()) ?? false)
        ).toList();
      }
      if (plan.isNotEmpty && plan != 'All') filtered = filtered.where((l) => l['plan_name'] == plan).toList();
      if (status.isNotEmpty && status != 'All') filtered = filtered.where((l) => l['status'] == status).toList();
      return {'items': filtered, 'total': filtered.length, 'pages': 1};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/ai/logs', queryParameters: {
      'search': search, 'plan': plan, 'status': status, 'page': page
    });
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getAiUsageAlerts() async {
    if (AppConfig.isDemoMode) {
      var filtered = _MockAdminData.aiAlerts.where((a) => a['resolved'] != true).toList();
      return {'items': filtered, 'total': filtered.length};
    }
    final response = await _client.get<Map<String, dynamic>>('/admin/ai/alerts');
    return responseMap(response.data);
  }

  Future<void> resolveAiUsageAlert(String alertId) async {
    if (AppConfig.isDemoMode) {
      final index = _MockAdminData.aiAlerts.indexWhere((a) => a['id'] == alertId);
      if (index != -1) _MockAdminData.aiAlerts[index]['resolved'] = true;
      return;
    }
    await _client.patch<dynamic>('/admin/ai/alerts/$alertId/resolve');
  }
}
