import '../../core/network/api_client.dart';
import 'repository_helpers.dart';

class RatingRepository {
  final ApiClient _client;

  RatingRepository(this._client);

  /// POST /api/ratings
  /// Payload keys: target_id, type, score, comment
  Future<void> submitRating(Map<String, dynamic> payload) async {
    await _client.post<dynamic>('/api/ratings', data: payload);
  }

  /// GET /api/ratings/user/<userId>
  Future<List<Map<String, dynamic>>> getUserRatings(String userId) async {
    final response = await _client.get<dynamic>('/api/ratings/user/$userId');
    return responseList(response.data, ['ratings', 'data'])
        .cast<Map<String, dynamic>>();
  }

  /// GET /api/ratings/user/<userId>/avg
  Future<double> getUserAverageRating(String userId) async {
    final response = await _client
        .get<Map<String, dynamic>>('/api/ratings/user/$userId/avg');
    final data = responseMap(response.data);
    return (data['average_rating'] as num?)?.toDouble() ?? 0.0;
  }

  /// PUT /api/ratings/<id>
  Future<void> updateRating(String id, double score, String comment) async {
    await _client.put<dynamic>(
      '/api/ratings/$id',
      data: {'score': score, 'comment': comment},
    );
  }

  /// DELETE /api/ratings/<id>
  Future<void> deleteRating(String id) async {
    await _client.delete<dynamic>('/api/ratings/$id');
  }
}
