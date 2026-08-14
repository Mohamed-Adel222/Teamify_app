import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../core/network/api_client.dart';
import '../models/models.dart';
import 'repository_helpers.dart';

MediaType? _mediaTypeForFilename(String filename) {
  final name = filename.toLowerCase();
  const mapping = <String, String>{
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.heic': 'image/heic',
    '.pdf': 'application/pdf',
    '.txt': 'text/plain',
    '.csv': 'text/csv',
    '.zip': 'application/zip',
    '.doc': 'application/msword',
    '.docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xls': 'application/vnd.ms-excel',
    '.xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.ppt': 'application/vnd.ms-powerpoint',
    '.pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.mp3': 'audio/mpeg',
    '.wav': 'audio/wav',
    '.m4a': 'audio/mp4',
    '.ogg': 'audio/ogg',
    '.webm': 'audio/webm',
    '.mp4': 'video/mp4',
    '.mov': 'video/quicktime',
    '.avi': 'video/x-msvideo',
    '.mkv': 'video/x-matroska',
  };
  for (final entry in mapping.entries) {
    if (name.endsWith(entry.key)) {
      final parts = entry.value.split('/');
      return MediaType(parts[0], parts[1]);
    }
  }
  return null;
}

class FileRepository {
  final ApiClient _client;

  FileRepository(this._client);

  Future<List<ApiFile>> listFiles({String? projectId}) async {
    final response = await _client.get<dynamic>(
      '/api/files',
      queryParameters: projectId != null && projectId.isNotEmpty
          ? {'project_id': projectId}
          : null,
    );
    return responseList(response.data, ['files', 'data'])
        .map(ApiFile.fromJson)
        .toList();
  }

  Future<ApiFile> uploadFile({
    required String filePath,
    required String filename,
    String? projectId,
    List<int>? fileBytes,
  }) async {
    final MultipartFile filePayload;
    final mediaType = _mediaTypeForFilename(filename);
    if (fileBytes != null) {
      filePayload = MultipartFile.fromBytes(
        fileBytes,
        filename: filename,
        contentType: mediaType,
      );
    } else {
      filePayload = await MultipartFile.fromFile(
        filePath,
        filename: filename,
        contentType: mediaType,
      );
    }
    final data = FormData.fromMap({
      'file': filePayload,
      if (projectId != null) 'project_id': projectId,
    });
    final response = await _client.post<Map<String, dynamic>>(
      '/api/files',
      data: data,
      options: Options(contentType: 'multipart/form-data'),
    );
    final map = responseMap(response.data);
    final file = responseMap(map['file']);
    return ApiFile.fromJson(file.isNotEmpty ? file : map);
  }

  Future<List<int>> downloadFile(String id) async {
    final response = await _client.get<List<int>>(
      '/api/files/$id',
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {'Accept': '*/*'},
      ),
    );
    return response.data ?? <int>[];
  }

  Future<void> deleteFile(String id) async {
    await _client.delete<dynamic>('/api/files/$id');
  }
}
