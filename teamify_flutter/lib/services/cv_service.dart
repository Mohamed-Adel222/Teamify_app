import 'dart:typed_data';

import '../core/cache/cache_manager.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../core/offline/mutation_id.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/offline_mutation.dart';
import '../data/models/models.dart';
import '../data/repositories/cv_repository.dart';

/// Service layer for managing CVs and Resumes
class CVService with ServiceErrorHandler {
  final CVRepository _repo;
  final CacheManager _cache;
  final OfflineManager _offlineManager;
  final RequestDeduplicator _dedup = RequestDeduplicator();

  static const _box = 'cvs';
  static const _staleAge = Duration(minutes: 10);

  CVService({
    required CVRepository repo,
    required CacheManager cache,
    required OfflineManager offlineManager,
  })  : _repo = repo,
        _cache = cache,
        _offlineManager = offlineManager;

  Future<void> invalidateCVs() => _cache.invalidate(_box, 'my_cvs');

  // ── Reads (SWR) ────────────────────────────────────────────────────────────

  Future<ApiResult<List<ApiCV>>> listCVs({bool forceRefresh = false}) async {
    const key = 'my_cvs';
    if (forceRefresh) await _cache.invalidate(_box, key);

    final cached = await _cache.getList(_box, key, maxAge: _staleAge);
    if (cached != null && !forceRefresh) {
      _dedup.deduplicate('$key-bg', () async {
        final fresh = await _repo.listCVs();
        await _cache.putList(
            _box, key, fresh.map((cv) => cv.toJson()).toList());
        return ApiResult.success(fresh);
      });
      return ApiResult.success(cached
          .map((e) => ApiCV.fromJson(e.cast<String, dynamic>()))
          .toList());
    }

    return _dedup.deduplicate(key, () async {
      final result = await guard(() => _repo.listCVs());
      if (result.isSuccess) {
        await _cache.putList(
            _box, key, result.data!.map((cv) => cv.toJson()).toList());
      }
      return result;
    });
  }

  Future<ApiResult<ApiCV>> getCV(String id) =>
      _dedup.deduplicate('cv_$id', () => guard(() => _repo.getCV(id)));

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<ApiResult<ApiCV>> createCV(Map<String, dynamic> payload) async {
    final result = await guardWithOffline(
      () => _repo.createCV(payload),
      mutation: OfflineMutation(
        id: MutationId.generate(),
        method: 'POST',
        path: '/api/cv',
        data: payload,
        tag: 'createCV',
      ),
      offlineManager: _offlineManager,
    );
    if (result.isSuccess || result.isOfflineQueued) {
      await _cache.invalidate(_box, 'my_cvs');
    }
    return result;
  }

  Future<ApiResult<void>> deleteCV(String id) async {
    final result = await guard(() => _repo.deleteCV(id));
    if (result.isSuccess) {
      await _cache.invalidate(_box, 'my_cvs');
      await _cache.invalidate(_box, 'cv_$id');
    }
    return result;
  }

  Future<ApiResult<ApiCV>> updateCV(
      String id, Map<String, dynamic> payload) async {
    final result = await guardWithOffline(
      () => _repo.updateCV(id, payload),
      mutation: OfflineMutation(
        id: MutationId.generate(),
        method: 'PATCH',
        path: '/api/cv/$id',
        data: payload,
        tag: 'updateCV_$id',
      ),
      offlineManager: _offlineManager,
    );
    if (result.isSuccess || result.isOfflineQueued) {
      await _cache.invalidate(_box, 'my_cvs');
      await _cache.invalidate(_box, 'cv_$id');
    }
    return result;
  }

  // ── Exports ────────────────────────────────────────────────────────────────

  Future<ApiResult<String>> generateExportToken(String id) =>
      guard(() => _repo.generateExportToken(id));

  Future<ApiResult<({Uint8List bytes, String filename})>> exportPdf(
    String id, {
    String filename = 'resume.pdf',
  }) =>
      guard(() async {
        final response = await _repo.exportPdf(id);
        final dynamic raw = response.data;
        final Uint8List bytes;
        if (raw is Uint8List) {
          bytes = raw;
        } else if (raw is List<int>) {
          bytes = Uint8List.fromList(raw);
        } else if (raw is String && raw.isNotEmpty) {
          // Dio on web may return binary PDF bodies as a Latin-1 string.
          bytes = Uint8List.fromList(raw.codeUnits);
        } else {
          bytes = Uint8List(0);
        }
        if (bytes.isEmpty) {
          throw Exception('PDF export returned empty file');
        }
        if (bytes.length < 4 || String.fromCharCodes(bytes.take(4)) != '%PDF') {
          throw Exception('Server did not return a valid PDF');
        }
        var name = filename;
        final cd = response.headers.value('content-disposition');
        if (cd != null) {
          final match = RegExp(r'filename="?([^";\n]+)"?').firstMatch(cd);
          if (match != null) {
            name = match.group(1)!.trim();
          }
        }
        return (bytes: bytes, filename: name);
      });
}
