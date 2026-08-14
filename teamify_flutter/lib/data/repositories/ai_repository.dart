import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import 'repository_helpers.dart';

class AIRepository {
  final ApiClient _client;

  AIRepository(this._client);

  Future<Map<String, dynamic>> summarizeChat(String text,
      {int topN = 3}) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/chat/summarize',
      data: {'text': text, 'top_n': topN},
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> classifyTask(String text) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/classify-task',
      data: {'text': text},
      options: Options(
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    return responseMap(response.data);
  }

  /// POST /api/ai/feedback-assist — draft peer-feedback text
  Future<Map<String, dynamic>> feedbackAssist({
    required int rating,
    String teammateName = '',
    String projectName = '',
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/feedback-assist',
      data: {
        'rating': rating,
        'teammate_name': teammateName,
        'project_name': projectName,
      },
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> assignMember(String projectId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/assign',
      data: {'project_id': projectId},
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> suggestPriority({
    required String projectId,
    String title = '',
    String description = '',
    String? dueDate,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/suggest-priority',
      data: {
        'project_id': projectId,
        'title': title,
        'description': description,
        if (dueDate != null) 'due_date': dueDate,
      },
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> suggestDeadline({
    required String projectId,
    String priority = 'medium',
    String title = '',
    String description = '',
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/suggest-deadline',
      data: {
        'project_id': projectId,
        'priority': priority,
        'title': title,
        'description': description,
      },
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> predictDelay(
      {String? taskId, String? projectId}) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/delay',
      data: {
        if (taskId != null) 'task_id': taskId,
        if (projectId != null) 'project_id': projectId,
      },
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getDelayModelStatus() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/delay-model/status',
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> getModelsStatus() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/models/status',
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> workload({String? userId}) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/workload',
      queryParameters: {if (userId != null) 'user_id': userId},
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> mentorRecommendations(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/mentor/recommendations/$userId',
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> mentorPerformance(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/mentor/performance/$userId',
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> mentorCourses(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/mentor/courses/$userId',
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> predictRating(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/predict-rating/$userId',
    );
    return responseMap(response.data);
  }

  Future<Map<String, dynamic>> recommendTeammates(
    Map<String, dynamic> userStats, {
    int topN = 5,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/recommend-teammates',
      data: {
        'user_stats': userStats,
        'top_n': topN,
      },
    );
    return responseMap(response.data);
  }

  /// POST /api/ai/transcribe — speech-to-text via Whisper STT microservice
  Future<Map<String, dynamic>> transcribe(
    List<int> audioBytes, {
    String filename = 'audio.wav',
    String language = 'en',
  }) async {
    final formData = FormData.fromMap({
      'audio': MultipartFile.fromBytes(audioBytes, filename: filename),
    });
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/transcribe',
      data: formData,
      queryParameters: {'language': language},
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    return responseMap(response.data);
  }

  /// POST /api/ai/detect-anomaly — security anomaly detection (admin)
  Future<Map<String, dynamic>> detectAnomaly(
      Map<String, dynamic> payload) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/detect-anomaly',
      data: payload,
    );
    return responseMap(response.data);
  }

  /// GET /api/ai/mentor/insights/<id> — combined hub payload (one ML run)
  Future<Map<String, dynamic>> mentorInsights(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/mentor/insights/$userId',
    );
    return responseMap(response.data);
  }

  /// GET /api/ai/mentor/status — mentor pipeline + course catalog
  Future<Map<String, dynamic>> mentorStatus() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/mentor/status',
    );
    return responseMap(response.data);
  }

  /// GET /api/ai/mentor/analyse/<id> — full mentor analysis
  Future<Map<String, dynamic>> mentorAnalyse(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/ai/mentor/analyse/$userId',
    );
    return responseMap(response.data);
  }

  /// GET /api/ai/mentor/chat/history
  Future<List<Map<String, dynamic>>> mentorChatHistory({
    int limit = 50,
    String threadKey = 'general',
  }) async {
    final response = await _client.get<dynamic>(
      '/api/ai/mentor/chat/history',
      queryParameters: {'limit': limit, 'thread_key': threadKey},
    );
    return responseList(response.data, ['messages', 'data'])
        .cast<Map<String, dynamic>>();
  }

  /// POST /api/ai/mentor/chat — conversational AI mentor
  ///
  /// [question]   — the user's message
  /// [history]    — previous turns [{role, content}]
  /// [taskContext] — optional active task context
  Future<Map<String, dynamic>> mentorChat({
    required String question,
    List<Map<String, dynamic>> history = const [],
    Map<String, dynamic>? taskContext,
    Map<String, dynamic>? userContext,
    bool persistHistory = true,
    String threadKey = 'general',
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/ai/mentor/chat',
      data: {
        'question': question,
        'history': history,
        if (taskContext != null) 'task_context': taskContext,
        if (userContext != null) 'user_context': userContext,
        'persist_history': persistHistory,
        'thread_key': threadKey,
      },
    );
    return responseMap(response.data);
  }
}
