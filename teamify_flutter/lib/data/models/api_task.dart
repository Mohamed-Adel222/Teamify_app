import '../../models/models.dart';
import 'api_helpers.dart';

class ApiTask {
  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final String projectId;
  final String assignedTo;
  final String assigneeDisplayName;
  final String assigneeFullName;
  final String assigneeEmail;
  final String assigneeUserType;
  final String dueDate;
  final String aiDelayRisk;

  const ApiTask({
    required this.id,
    required this.title,
    this.description = '',
    this.status = 'pending',
    this.priority = 'medium',
    this.projectId = '',
    this.assignedTo = '',
    this.assigneeDisplayName = '',
    this.assigneeFullName = '',
    this.assigneeEmail = '',
    this.assigneeUserType = '',
    this.dueDate = '',
    this.aiDelayRisk = '',
  });

  String get assigneePrimaryName {
    if (assigneeFullName.isNotEmpty) return assigneeFullName;
    if (assigneeDisplayName.isNotEmpty) return assigneeDisplayName;
    return '';
  }

  static String initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  factory ApiTask.fromJson(Map<String, dynamic> json) {
    return ApiTask(
      id: asString(json['id']),
      title: asString(json['title'], 'Untitled Task'),
      description: asString(json['description']),
      status: asString(json['status'], 'pending'),
      priority: asString(json['priority'], 'medium'),
      projectId: asString(json['project_id'] ?? json['projectId']),
      assignedTo: asString(json['assigned_to'] ?? json['assignedTo']),
      assigneeDisplayName: asString(
        json['assignee_display_name'] ?? json['assigneeDisplayName'],
      ),
      assigneeFullName: asString(
        json['assignee_full_name'] ?? json['assigneeFullName'],
      ),
      assigneeEmail: asString(json['assignee_email'] ?? json['assigneeEmail']),
      assigneeUserType: asString(
        json['assignee_user_type'] ?? json['assigneeUserType'],
      ),
      dueDate: asString(json['due_date'] ?? json['dueDate']),
      aiDelayRisk: asString(json['ai_delay_risk'] ?? json['delay_risk']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status,
        'priority': priority,
        'project_id': projectId,
        'assigned_to': assignedTo.isEmpty ? null : assignedTo,
        'due_date': dueDate.isEmpty ? null : dueDate,
      };

  TaskModel toDisplayModel() {
    final name = assigneePrimaryName;
    final label = name.isNotEmpty
        ? name
        : (assigneeDisplayName.isNotEmpty ? assigneeDisplayName : 'Unassigned');
    return TaskModel(
      id: id,
      title: title,
      description: description,
      assignee: label,
      assigneeId: assignedTo,
      assigneeEmail: assigneeEmail,
      assigneeDisplayName: assigneeDisplayName,
      assigneeInitials: name.isNotEmpty ? initialsFrom(name) : '?',
      status: status,
      priority: priority,
      dueDate: dueDate,
    );
  }
}
