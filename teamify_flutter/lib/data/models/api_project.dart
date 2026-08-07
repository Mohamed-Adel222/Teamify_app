import '../../models/models.dart';
import 'api_helpers.dart';
import 'api_task.dart';
import 'api_user.dart';

class ApiProject {
  final String id;
  final String name;
  final String description;
  final String status;
  final int progress;
  final String ownerId;
  final String ownerName;
  final ApiUser? owner;
  final String category;
  final int memberCount;
  final String startDate;
  final String endDate;
  final List<ApiTask> tasks;
  final List<String> members;

  const ApiProject({
    required this.id,
    required this.name,
    this.description = '',
    this.status = 'active',
    this.progress = 0,
    this.ownerId = '',
    this.ownerName = '',
    this.owner,
    this.category = '',
    this.memberCount = 0,
    this.startDate = '',
    this.endDate = '',
    this.tasks = const [],
    this.members = const [],
  });

  factory ApiProject.fromJson(Map<String, dynamic> json) {
    // Parse the nested owner object if present
    final ownerJson = json['owner'];
    final ApiUser? parsedOwner =
        ownerJson is Map<String, dynamic> ? ApiUser.fromJson(ownerJson) : null;

    // Derive ownerName: prefer nested owner, fall back to flat string
    final flatOwnerName = asString(json['owner_name']);
    final resolvedOwnerName = parsedOwner != null
        ? (parsedOwner.displayName.isNotEmpty
            ? parsedOwner.displayName
            : parsedOwner.fullName)
        : flatOwnerName;

    return ApiProject(
      id: asString(json['id']),
      name: asString(json['name'] ?? json['title'], 'Untitled Project'),
      description: asString(json['description']),
      status: asString(json['status'], 'active'),
      progress: asInt(json['progress']),
      ownerId: asString(json['user_id'] ?? json['owner_id']),
      ownerName: resolvedOwnerName,
      owner: parsedOwner,
      category: asString(json['category']),
      memberCount: asInt(json['member_count']),
      startDate: asString(json['start_date']),
      endDate: asString(json['end_date']),
      tasks: asMapList(json['tasks']).map(ApiTask.fromJson).toList(),
      members: asStringList(json['members'] ?? json['member_ids']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'status': status,
        'progress': progress,
        'user_id': ownerId,
        'owner_name': ownerName,
        if (owner != null) 'owner': owner!.toJson(),
        'category': category,
        'start_date': startDate,
        'end_date': endDate,
      };

  /// Strips [Visibility:...] metadata prefix from description.
  static String _cleanDescription(String raw) {
    var text = raw.trim();
    if (text.startsWith('[Visibility:')) {
      final end = text.indexOf(']');
      if (end != -1 && end + 1 < text.length) {
        text = text.substring(end + 1).trim();
      }
    }
    return text;
  }

  /// Format an ISO date string (YYYY-MM-DD) to DD/MM/YYYY for display.
  static String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
    } catch (_) {
      return iso;
    }
  }

  ProjectModel toDisplayModel() {
    return ProjectModel(
      id: id,
      name: name,
      company: category.isNotEmpty ? category : 'Teamify',
      description: _cleanDescription(description),
      status: status,
      delayRisk: 'Unknown',
      progress: progress,
      ownerId: ownerId,
      ownerName: ownerName,
      startDate: _fmtDate(startDate),
      endDate: _fmtDate(endDate),
      tasks: tasks.map((task) => task.toDisplayModel()).toList(),
      members: members,
    );
  }
}
