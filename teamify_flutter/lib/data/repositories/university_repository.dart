import '../../core/network/api_client.dart';
import '../models/university_option_model.dart';
import 'repository_helpers.dart';

class UniversityRepository {
  final ApiClient _client;

  UniversityRepository(this._client);

  /// GET /api/universities — built-in catalog plus custom entries other users
  /// registered, with the "Other" sentinel last.
  Future<List<UniversityOption>> list({String query = ''}) async {
    final response = await _client.get<dynamic>(
      '/api/universities',
      queryParameters: {if (query.isNotEmpty) 'q': query},
    );
    return responseList(response.data, ['universities', 'data'])
        .map(UniversityOption.fromJson)
        .toList();
  }
}
