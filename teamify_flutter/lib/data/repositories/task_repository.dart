import '../../core/network/api_client.dart';
import '../models/models.dart';
import 'repository_helpers.dart';

class TaskRepository {
  final ApiClient _client;

  TaskRepository(this._client);

  // GET /api/tasks
  Future<List<ApiTask>> listTasks({required String projectId}) async {
    final response = await _client.get<dynamic>(
      '/api/tasks',
      queryParameters: {'project_id': projectId},
    );
    return responseList(response.data, ['tasks', 'data'])
        .map(ApiTask.fromJson)
        .toList();
  }

  /// GET /api/tasks/accessible — all tasks across accessible projects (one call).
  Future<List<Map<String, dynamic>>> listAccessibleTasks(
      {int limit = 100}) async {
    final response = await _client.get<dynamic>(
      '/api/tasks/accessible',
      queryParameters: {'limit': limit},
    );
    return responseList(response.data, ['tasks', 'data'])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // POST /api/tasks
  Future<ApiTask> createTask(Map<String, dynamic> payload) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/tasks',
      data: payload,
    );
    final data = responseMap(response.data);
    final task = responseMap(data['task']);
    return ApiTask.fromJson(task.isNotEmpty ? task : data);
  }

  // GET /api/tasks/<id>
  Future<ApiTask> getTask(String id) async {
    final response = await _client.get<Map<String, dynamic>>('/api/tasks/$id');
    final data = responseMap(response.data);
    final task = responseMap(data['task']);
    return ApiTask.fromJson(task.isNotEmpty ? task : data);
  }

  // PUT /api/tasks/<id> — Full update
  Future<ApiTask> updateTask(String id, Map<String, dynamic> payload) async {
    final response = await _client.put<Map<String, dynamic>>(
      '/api/tasks/$id',
      data: payload,
    );
    final data = responseMap(response.data);
    final task = responseMap(data['task']);
    return ApiTask.fromJson(task.isNotEmpty ? task : data);
  }

  // PATCH /api/tasks/<id>/status — Status-only update
  Future<ApiTask> updateTaskStatus(String id, String status) async {
    final response = await _client.patch<Map<String, dynamic>>(
      '/api/tasks/$id/status',
      data: {'status': status},
    );
    final data = responseMap(response.data);
    final task = responseMap(data['task']);
    return ApiTask.fromJson(task.isNotEmpty ? task : data);
  }

  // DELETE /api/tasks/<id>
  Future<void> deleteTask(String id) async {
    await _client.delete<dynamic>('/api/tasks/$id');
  }
}
