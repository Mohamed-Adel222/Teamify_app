import 'api_helpers.dart';

class ApiNotification {
  final String id;
  final String title;
  final String body;
  final bool isRead;
  final String createdAt;
  final String type;
  final String entityType;
  final String entityId;

  const ApiNotification({
    required this.id,
    required this.title,
    this.body = '',
    this.isRead = false,
    this.createdAt = '',
    this.type = 'general',
    this.entityType = '',
    this.entityId = '',
  });

  factory ApiNotification.fromJson(Map<String, dynamic> json) {
    return ApiNotification(
      id: asString(json['id']),
      title: asString(json['title']),
      body: asString(json['body'] ?? json['message']),
      isRead: asBool(json['is_read'] ?? json['isRead']),
      createdAt: asString(json['created_at'] ?? json['createdAt']),
      type: asString(json['type'] ?? 'general'),
      entityType: asString(json['entity_type'] ?? json['entityType']),
      entityId: asString(json['entity_id'] ?? json['entityId']),
    );
  }

  bool get hasLinkedEntity => entityType.isNotEmpty && entityId.isNotEmpty;

  ApiNotification copyWith({
    String? id,
    String? title,
    String? body,
    bool? isRead,
    String? createdAt,
    String? type,
    String? entityType,
    String? entityId,
  }) {
    return ApiNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'is_read': isRead,
        'created_at': createdAt,
        'type': type,
        'entity_type': entityType,
        'entity_id': entityId,
      };
}

class ApiFile {
  final String id;
  final String name;
  final String size;
  final String type;
  final String uploadedBy;
  final String projectId;
  final String createdAt;
  final String sha256;

  const ApiFile({
    required this.id,
    required this.name,
    this.size = '',
    this.type = '',
    this.uploadedBy = '',
    this.projectId = '',
    this.createdAt = '',
    this.sha256 = '',
  });

  factory ApiFile.fromJson(Map<String, dynamic> json) {
    final bytes = asInt(json['size_bytes']);
    final size = asString(json['size'] ?? json['file_size']);
    return ApiFile(
      id: asString(json['id'] ?? json['file_id']),
      name: asString(
          json['filename'] ?? json['original_filename'] ?? json['name']),
      size: size.isNotEmpty ? size : _formatBytes(bytes),
      type: asString(json['mime_type'] ?? json['type']),
      uploadedBy: asString(
        json['owner_name'] ?? json['uploaded_by'] ?? json['owner_id'],
      ),
      projectId: asString(json['project_id'] ?? json['projectId']),
      createdAt: asString(json['created_at'] ?? json['uploaded_at']),
      sha256: asString(json['sha256'] ?? json['sha256_hash']),
    );
  }

  /// Whether the file has a verified integrity hash.
  bool get hasIntegrityHash => sha256.isNotEmpty;

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final decimals = unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': name,
        'size': size,
        'mime_type': type,
        'uploaded_by': uploadedBy,
        'created_at': createdAt,
        'sha256': sha256,
      };
}

class ApiCV {
  final String id;
  final String userId;
  final Map<String, dynamic> data;

  const ApiCV({
    required this.id,
    required this.userId,
    required this.data,
  });

  factory ApiCV.fromJson(Map<String, dynamic> json) {
    return ApiCV(
      id: asString(json['id'] ?? json['cv_id']),
      userId: asString(json['user_id']),
      data: json,
    );
  }

  Map<String, dynamic> toJson() => data;
}
