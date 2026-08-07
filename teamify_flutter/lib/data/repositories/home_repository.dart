import '../../core/network/api_client.dart';
import '../../config/app_config.dart';
import 'repository_helpers.dart';

/// Central access point for the /api/dashboard consolidated endpoint.
class HomeRepository {
  final ApiClient _client;

  HomeRepository(this._client);

  /// GET /api/dashboard
  /// Returns task counts, active projects, recent activity, and at-risk tasks.
  Future<Map<String, dynamic>> getDashboard() async {
    if (AppConfig.isDemoMode) {
      return {
        'stats': {
          'active_projects_count': 3,
          'completed_tasks': 12,
          'in_progress_tasks': 4,
        },
        'at_risk_tasks': [],
        'unread_notifications': 0,
      };
    }
    final response = await _client.get<Map<String, dynamic>>('/api/dashboard');
    return responseMap(response.data);
  }

  /// GET /api/health — backend connectivity check.
  Future<Map<String, dynamic>> checkHealth() async {
    if (AppConfig.isDemoMode) {
      return {'status': 'ok', 'demo': true};
    }
    final response = await _client.get<Map<String, dynamic>>('/api/health');
    return responseMap(response.data);
  }
}
