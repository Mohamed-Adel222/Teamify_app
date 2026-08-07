import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/models.dart';
import 'repository_helpers.dart';

class CVRepository {
  final ApiClient _client;

  CVRepository(this._client);

  // GET /api/cv — list all CVs (with optional pagination)
  Future<List<ApiCV>> listCVs({int page = 1, int perPage = 20}) async {
    final response = await _client.get<dynamic>(
      '/api/cv',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    return responseList(response.data, ['cvs', 'cv', 'data'])
        .map(ApiCV.fromJson)
        .toList();
  }

  // POST /api/cv
  Future<ApiCV> createCV(Map<String, dynamic> payload) async {
    final response =
        await _client.post<Map<String, dynamic>>('/api/cv', data: payload);
    final data = responseMap(response.data);
    final cv = responseMap(data['cv']);
    return ApiCV.fromJson(cv.isNotEmpty ? cv : data);
  }

  // GET /api/cv/<id> — single CV by ID
  Future<ApiCV> getCV(String id) async {
    final response = await _client.get<Map<String, dynamic>>('/api/cv/$id');
    final data = responseMap(response.data);
    final cv = responseMap(data['cv']);
    return ApiCV.fromJson(cv.isNotEmpty ? cv : data);
  }

  // DELETE /api/cv/<id>
  Future<void> deleteCV(String id) async {
    await _client.delete<dynamic>('/api/cv/$id');
  }

  // PATCH /api/cv/<id>
  Future<ApiCV> updateCV(String id, Map<String, dynamic> payload) async {
    final response =
        await _client.patch<Map<String, dynamic>>('/api/cv/$id', data: payload);
    final data = responseMap(response.data);
    final cv = responseMap(data['cv']);
    return ApiCV.fromJson(cv.isNotEmpty ? cv : data);
  }

  // GET /api/cv/<id>/export/pdf — direct PDF download
  Future<Response<List<int>>> exportPdf(String id) {
    return _client.get<List<int>>(
      '/api/cv/$id/export/pdf',
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {'Accept': '*/*'},
      ),
    );
  }

  // POST /api/cv/<id>/export — generate a secure download token
  Future<String> generateExportToken(String id) async {
    final response =
        await _client.post<Map<String, dynamic>>('/api/cv/$id/export');
    final data = responseMap(response.data);
    return data['token']?.toString() ?? '';
  }

  // GET /api/cv/download/<token> — token-based download (no auth required)
  Future<Response<List<int>>> downloadByToken(String token) {
    return _client.get<List<int>>(
      '/api/cv/download/$token',
      options: Options(
        responseType: ResponseType.bytes,
        extra: {'skipAuth': true},
      ),
    );
  }

  // POST /api/ai/cv/build — build CV via AI
  Future<Map<String, dynamic>> buildWithAI({String? targetUserId}) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/cv/build',
      data: targetUserId == null ? const {} : {'target_user_id': targetUserId},
    );
    return responseMap(response.data);
  }
}
