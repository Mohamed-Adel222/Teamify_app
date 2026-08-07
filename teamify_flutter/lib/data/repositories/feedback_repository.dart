import '../../core/network/api_client.dart';
import 'repository_helpers.dart';

class FeedbackRepository {
  final ApiClient _client;

  FeedbackRepository(this._client);

  /// POST /api/feedback
  /// Payload keys: target_user_id, project_id, rating, content
  Future<void> submitFeedback(Map<String, dynamic> payload) async {
    await _client.post<dynamic>('/api/feedback', data: payload);
  }

  /// GET /api/feedback/user/<userId>
  Future<List<Map<String, dynamic>>> getUserFeedback(String userId) async {
    final response = await _client.get<dynamic>('/api/feedback/user/$userId');
    return responseList(response.data, ['feedback', 'data'])
        .cast<Map<String, dynamic>>();
  }

  /// GET /api/feedback/project/<projectId>
  Future<List<Map<String, dynamic>>> getProjectFeedback(
      String projectId) async {
    final response =
        await _client.get<dynamic>('/api/feedback/project/$projectId');
    return responseList(response.data, ['feedback', 'data'])
        .cast<Map<String, dynamic>>();
  }

  /// GET /api/feedback/<id>
  Future<Map<String, dynamic>> getFeedbackDetail(String id) async {
    final response =
        await _client.get<Map<String, dynamic>>('/api/feedback/$id');
    return responseMap(response.data);
  }

  /// PUT /api/feedback/<id>
  Future<void> updateFeedback(String id, Map<String, dynamic> payload) async {
    await _client.put<dynamic>('/api/feedback/$id', data: payload);
  }

  /// DELETE /api/feedback/<id>
  Future<void> deleteFeedback(String id) async {
    await _client.delete<dynamic>('/api/feedback/$id');
  }
}
