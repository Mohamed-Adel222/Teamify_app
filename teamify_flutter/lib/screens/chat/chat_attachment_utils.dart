import 'dart:convert';

const int kChatMaxUploadBytes = 10 * 1024 * 1024;

const List<String> kChatDocumentExtensions = [
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'csv',
  'zip',
];

const List<String> kChatMediaExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'mp4',
  'mov',
  'webm',
  'avi',
  'mkv',
];

const Set<String> kChatVideoExtensions = {
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
};

String mimeForFilename(String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic')) return 'image/heic';
  if (n.endsWith('.txt')) return 'text/plain';
  if (n.endsWith('.csv')) return 'text/csv';
  if (n.endsWith('.zip')) return 'application/zip';
  if (n.endsWith('.mp3')) return 'audio/mpeg';
  if (n.endsWith('.wav')) return 'audio/wav';
  if (n.endsWith('.m4a')) return 'audio/mp4';
  if (n.endsWith('.ogg')) return 'audio/ogg';
  if (n.endsWith('.webm')) return 'audio/webm';
  if (n.endsWith('.mp4')) return 'video/mp4';
  if (n.endsWith('.mov')) return 'video/quicktime';
  return 'application/octet-stream';
}

bool isVideoFilename(String? name) {
  final ext = (name ?? '').toLowerCase().split('.').last;
  return kChatVideoExtensions.contains(ext);
}

Map<String, dynamic>? parseStructuredPayload({
  String? content,
  String? fileId,
}) {
  for (final raw in [content, fileId]) {
    if (raw == null) continue;
    final text = raw.trim();
    if (!text.startsWith('{') || !text.endsWith('}')) continue;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

int? parseNumericFileId(String? fileId) {
  if (fileId == null) return null;
  return int.tryParse(fileId.trim());
}
