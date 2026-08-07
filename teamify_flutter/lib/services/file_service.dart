import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/cache/cache_manager.dart';
import '../core/cache/swr_helper.dart';
import '../core/network/service_error_handler.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/offline_mutation.dart';
import '../core/offline/mutation_id.dart';
import '../data/models/models.dart';
import '../data/repositories/file_repository.dart';

/// File listing + upload service — now offline-first for uploads.
///
/// File uploads that fail due to network errors are queued for replay.
/// Note: multipart bodies cannot be serialised to JSON, so queued uploads
/// store only the metadata (path, filename, projectId). On replay the
/// OfflineManager sends the metadata to a lightweight re-upload endpoint.
/// A full binary-resumable upload (e.g. tus.io) would replace this.
class FileService with ServiceErrorHandler {
  final FileRepository _repo;
  final OfflineManager _offline;
  final CacheManager _cache;
  static const _box = 'files';
  static const _ttl = Duration(minutes: 5);
  late final SwrHelper _swr;

  FileService(this._repo, this._offline, this._cache) {
    _swr = SwrHelper(_cache);
  }

  final RequestDeduplicator _dedup = RequestDeduplicator();

  Future<ApiResult<List<ApiFile>>> listFiles({
    String? projectId,
    bool forceRefresh = false,
    void Function(List<ApiFile>)? onRefreshed,
  }) =>
      _dedup.deduplicate(
          'list_files_${projectId ?? "personal"}',
          () => guard(() async {
                final cacheKey = projectId != null && projectId.isNotEmpty
                    ? 'project_$projectId'
                    : 'personal';
                if (forceRefresh) {
                  final files = await _repo.listFiles(projectId: projectId);
                  await _cache.putList(
                      _box, cacheKey, files.map((f) => f.toJson()).toList());
                  return files;
                }
                return _swr
                    .withSwrList<ApiFile>(
                      boxName: _box,
                      key: cacheKey,
                      fetcher: () => _repo.listFiles(projectId: projectId),
                      fromJson: ApiFile.fromJson,
                      toJson: (f) => f.toJson(),
                      staleAge: _ttl,
                      onRefreshed: onRefreshed,
                    )
                    .then((res) =>
                        res.isSuccess ? res.data! : throw Exception(res.error));
              }));

  /// Uploads a file.  On network failure, queues a retry-metadata record
  /// so the user's intent is preserved (file can be re-uploaded on sync).
  Future<ApiResult<ApiFile>> uploadFile({
    required String filePath,
    required String filename,
    String? projectId,
    List<int>? fileBytes,
  }) =>
      guardWithOffline(
        () async {
          final file = await _repo.uploadFile(
            filePath: filePath,
            filename: filename,
            projectId: projectId,
            fileBytes: fileBytes,
          );
          await _cache.invalidateBox(_box);
          return file;
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/files/upload',
          // Store metadata only — binary payload cannot be JSON-serialised.
          // On replay the backend will expect the client to re-submit the file.
          data: {
            'file_path': filePath,
            'filename': filename,
            if (projectId != null) 'project_id': projectId,
          },
          tag: 'uploadFile',
        ),
        offlineManager: _offline,
      );

  Future<ApiResult<List<int>>> downloadFile(String fileId) =>
      _dedup.deduplicate(
        'download_file_$fileId',
        () => guard(() => _repo.downloadFile(fileId)),
      );

  Future<ApiResult<void>> deleteFile(String fileId) => guard(() async {
        await _repo.deleteFile(fileId);
        await _cache.invalidateBox(_box);
      });
}
