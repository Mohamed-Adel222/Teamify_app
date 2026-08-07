import '../../core/network/api_client.dart';
import '../../config/app_config.dart';
import '../models/models.dart';
import 'repository_helpers.dart';

class NotificationRepository {
  final ApiClient _client;

  NotificationRepository(this._client);

  // GET /api/notifications
  Future<List<ApiNotification>> listNotifications() async {
    final response = await _client.get<dynamic>('/api/notifications');
    return responseList(response.data, ['notifications', 'data'])
        .map(ApiNotification.fromJson)
        .toList();
  }

  // GET /api/notifications/unread-count
  Future<int> getUnreadCount() async {
    if (AppConfig.isDemoMode) return 0;
    final response = await _client
        .get<Map<String, dynamic>>('/api/notifications/unread-count');
    final data = responseMap(response.data);
    return (data['unread_count'] as num?)?.toInt() ?? 0;
  }

  // PATCH /api/notifications/<id>/read
  Future<void> markRead(String id) async {
    await _client.patch<dynamic>(
      '/api/notifications/$id/read',
      data: const {},
    );
  }

  // POST /api/notifications/mark-all-read
  Future<void> markAllAsRead() async {
    await _client.post<dynamic>('/api/notifications/mark-all-read');
  }

  // GET /api/notifications/preferences
  Future<Map<String, dynamic>> getPreferences() async {
    final response = await _client
        .get<Map<String, dynamic>>('/api/notifications/preferences');
    return responseMap(responseMap(response.data)['preferences']);
  }

  // PUT /api/notifications/preferences
  Future<Map<String, dynamic>> updatePreferences(
      Map<String, dynamic> preferences) async {
    final response = await _client.put<Map<String, dynamic>>(
      '/api/notifications/preferences',
      data: preferences,
    );
    return responseMap(responseMap(response.data)['preferences']);
  }
}
