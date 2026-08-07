import '../../core/network/api_client.dart';
import 'repository_helpers.dart';

class CommentRepository {
  final ApiClient _client;

  CommentRepository(this._client);

  /// GET /api/tasks/<taskId>/comments
  Future<List<Map<String, dynamic>>> getTaskComments(String taskId) async {
    final response = await _client.get<dynamic>('/api/tasks/$taskId/comments');
    return responseList(response.data, ['comments', 'data'])
        .cast<Map<String, dynamic>>();
  }

  /// POST /api/tasks/<taskId>/comments
  Future<void> addComment(String taskId, String content) async {
    await _client.post<dynamic>(
      '/api/tasks/$taskId/comments',
      data: {'content': content},
    );
  }
}
