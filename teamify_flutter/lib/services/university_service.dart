import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../data/models/university_option_model.dart';
import '../data/repositories/university_repository.dart';

/// Serves the university catalog. The full list is small and static enough to
/// keep in memory for the lifetime of the app session.
class UniversityService with ServiceErrorHandler {
  final UniversityRepository _repo;
  final RequestDeduplicator _dedup = RequestDeduplicator();

  List<UniversityOption>? _cached;

  UniversityService(this._repo);

  Future<ApiResult<List<UniversityOption>>> list(
      {bool forceRefresh = false}) async {
    final cached = _cached;
    if (!forceRefresh && cached != null) {
      return ApiResult.success(cached);
    }
    final result = await _dedup.deduplicate(
      'universities',
      () => guard(() => _repo.list()),
    );
    if (result.isSuccess) _cached = result.data;
    return result;
  }
}
