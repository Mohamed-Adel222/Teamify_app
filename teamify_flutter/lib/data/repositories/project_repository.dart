import '../../core/network/api_client.dart';
import '../models/models.dart';
import 'repository_helpers.dart';

class ProjectRepository {
  final ApiClient _client;

  ProjectRepository(this._client);

  // GET /api/projects
  Future<List<ApiProject>> listProjects() async {
    final response = await _client.get<dynamic>('/api/projects');
    return responseList(response.data, ['projects', 'data'])
        .map(ApiProject.fromJson)
        .toList();
  }

  // POST /api/projects
  Future<ApiProject> createProject(Map<String, dynamic> payload) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/projects',
      data: payload,
    );
    final data = responseMap(response.data);
    final project = responseMap(data['project']);
    return ApiProject.fromJson(project.isNotEmpty ? project : data);
  }

  // GET /api/projects/<id>
  Future<ApiProject> getProject(String id) async {
    final response =
        await _client.get<Map<String, dynamic>>('/api/projects/$id');
    final data = responseMap(response.data);
    final project = responseMap(data['project']);
    return ApiProject.fromJson(project.isNotEmpty ? project : data);
  }

  // PUT /api/projects/<id>
  Future<ApiProject> updateProject(
      String id, Map<String, dynamic> payload) async {
    final response = await _client.put<Map<String, dynamic>>(
      '/api/projects/$id',
      data: payload,
    );
    final data = responseMap(response.data);
    final project = responseMap(data['project']);
    return ApiProject.fromJson(project.isNotEmpty ? project : data);
  }

  // DELETE /api/projects/<id>
  Future<void> deleteProject(String id) async {
    await _client.delete<dynamic>('/api/projects/$id');
  }

  // GET /api/projects/completed
  Future<List<ApiProject>> listCompletedProjects(
      {int page = 1, String search = ''}) async {
    final response = await _client.get<dynamic>(
      '/api/projects/completed',
      queryParameters: {
        'page': page,
        if (search.isNotEmpty) 'search': search,
      },
    );
    return responseList(response.data, ['projects', 'data'])
        .map(ApiProject.fromJson)
        .toList();
  }

  // POST /api/projects/<id>/complete
  Future<ApiProject> completeProject(String id) async {
    final response =
        await _client.post<Map<String, dynamic>>('/api/projects/$id/complete');
    final data = responseMap(response.data);
    final project = responseMap(data['project']);
    return ApiProject.fromJson(project.isNotEmpty ? project : data);
  }

  // POST /api/projects/<id>/reopen
  Future<ApiProject> reopenProject(String id) async {
    final response =
        await _client.post<Map<String, dynamic>>('/api/projects/$id/reopen');
    final data = responseMap(response.data);
    final project = responseMap(data['project']);
    return ApiProject.fromJson(project.isNotEmpty ? project : data);
  }

  // GET /api/projects/<id>/members
  Future<List<ApiUser>> listProjectMembers(String id) async {
    final response = await _client.get<dynamic>('/api/projects/$id/members');
    return responseList(response.data, ['members', 'data'])
        .map(ApiUser.fromJson)
        .toList();
  }

  // POST /api/projects/<id>/members
  Future<void> addProjectMember(
      {required String projectId, required String userId}) async {
    await _client.post<dynamic>(
      '/api/projects/$projectId/members',
      data: {'user_id': userId},
    );
  }

  // DELETE /api/projects/<id>/members/<uid>
  Future<void> removeProjectMember(
      {required String projectId, required String userId}) async {
    await _client.delete<dynamic>('/api/projects/$projectId/members/$userId');
  }

  // GET /api/projects/<id>/invitations
  Future<List<ApiProjectInvitation>> listProjectInvitations(
    String projectId, {
    String status = '',
  }) async {
    final response = await _client.get<dynamic>(
      '/api/projects/$projectId/invitations',
      queryParameters: {if (status.isNotEmpty) 'status': status},
    );
    return responseList(response.data, ['invitations', 'data'])
        .whereType<Map<String, dynamic>>()
        .map(ApiProjectInvitation.fromJson)
        .toList();
  }

  // GET /api/projects/invitations
  Future<List<Map<String, dynamic>>> listMyInvitations({
    String status = 'pending',
  }) async {
    final response = await _client.get<dynamic>(
      '/api/projects/invitations',
      queryParameters: {if (status.isNotEmpty) 'status': status},
    );
    return responseList(response.data, ['invitations', 'data'])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  // POST /api/projects/invitations/<id>/accept
  Future<Map<String, dynamic>> acceptInvitation(String invitationId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/projects/invitations/$invitationId/accept',
    );
    return responseMap(response.data);
  }

  // POST /api/projects/invitations/<id>/decline
  Future<void> declineInvitation(String invitationId) async {
    await _client.post<dynamic>(
      '/api/projects/invitations/$invitationId/decline',
    );
  }

  // GET /api/projects/available-members (also /api/users/available-members)
  Future<List<ApiUser>> getAvailableMembers({String search = ''}) async {
    final params = {if (search.isNotEmpty) 'search': search};
    try {
      final response = await _client.get<dynamic>(
        '/api/projects/available-members',
        queryParameters: params,
      );
      return _parseAvailableMembers(response.data);
    } catch (_) {
      final response = await _client.get<dynamic>(
        '/api/users/available-members',
        queryParameters: params,
      );
      return _parseAvailableMembers(response.data);
    }
  }

  List<ApiUser> _parseAvailableMembers(dynamic raw) {
    final data = responseMap(raw);
    final list = (data['users'] as List?)?.cast<dynamic>() ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ApiUser.fromJson)
        .where((u) => !u.isAdmin)
        .toList();
  }
}
