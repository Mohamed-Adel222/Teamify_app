// ── User ──────────────────────────────────────────────────────────────────────
class UserModel {
  final String id, name, email, role, avatar;
  final double rating;
  final int projectsCount;
  final List<String> skills;
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatar = '',
    this.rating = 4.8,
    this.projectsCount = 0,
    this.skills = const [],
  });
  String get initials {
    final p = name.split(' ');
    return p.length >= 2 ? '${p[0][0]}${p[1][0]}' : name[0];
  }
}

// ── Task ──────────────────────────────────────────────────────────────────────
class TaskModel {
  final String id, title, assignee, assigneeInitials, status, priority, dueDate;
  final String description;
  final String assigneeId;
  final String assigneeEmail;
  final String assigneeDisplayName;

  const TaskModel({
    required this.id,
    required this.title,
    required this.assignee,
    required this.assigneeInitials,
    required this.status,
    required this.priority,
    required this.dueDate,
    this.description = '',
    this.assigneeId = '',
    this.assigneeEmail = '',
    this.assigneeDisplayName = '',
  });
}

// ── Project ───────────────────────────────────────────────────────────────────
class ProjectModel {
  final String id, name, company, description, status, delayRisk;
  final String ownerId;
  final String ownerName;
  final String startDate;
  final String endDate;
  final int progress;
  final List<TaskModel> tasks;
  final List<String> members;
  const ProjectModel({
    required this.id,
    required this.name,
    required this.company,
    this.description = '',
    required this.status,
    required this.delayRisk,
    required this.progress,
    this.ownerId = '',
    this.ownerName = '',
    this.startDate = '',
    this.endDate = '',
    this.tasks = const [],
    this.members = const [],
  });

  ProjectModel copyWith({
    String? id,
    String? name,
    String? company,
    String? description,
    String? status,
    String? delayRisk,
    String? ownerId,
    String? ownerName,
    String? startDate,
    String? endDate,
    int? progress,
    List<TaskModel>? tasks,
    List<String>? members,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      name: name ?? this.name,
      company: company ?? this.company,
      description: description ?? this.description,
      status: status ?? this.status,
      delayRisk: delayRisk ?? this.delayRisk,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      progress: progress ?? this.progress,
      tasks: tasks ?? this.tasks,
      members: members ?? this.members,
    );
  }
}

// ── Chat ──────────────────────────────────────────────────────────────────────
class ChatMessage {
  final String id, senderId, senderName, senderInitials, message, time;
  final bool isMe;
  final bool isPending;

  /// text | image | file
  final String messageType;
  final String? fileId;
  final String? fileName;
  final String? mimeType;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderInitials,
    required this.message,
    required this.time,
    this.isMe = false,
    this.isPending = false,
    this.messageType = 'text',
    this.fileId,
    this.fileName,
    this.mimeType,
    this.createdAt,
  });

  bool get isImage => messageType == 'image';
  bool get isFile => messageType == 'file';
  bool get hasAttachment => fileId != null && fileId!.isNotEmpty;
}

class ChatRoom {
  final String id, name, lastMessage, time, initials;
  final int unread;
  final bool isGroup;
  final String? projectId;
  const ChatRoom({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.initials,
    this.unread = 0,
    this.isGroup = false,
    this.projectId,
  });
}

// ── Security ──────────────────────────────────────────────────────────────────
class SecurityAlert {
  final String id, title, user, description, risk, status, time;
  const SecurityAlert({
    required this.id,
    required this.title,
    required this.user,
    required this.description,
    required this.risk,
    required this.status,
    required this.time,
  });
  bool get isResolved => status == 'Resolved';
}

class LoginLog {
  final String id, userName, status, time, date, device, ip;
  const LoginLog({
    required this.id,
    required this.userName,
    required this.status,
    required this.time,
    required this.date,
    required this.device,
    required this.ip,
  });
  bool get isSuccess => status == 'Success';
}

class FileItem {
  final String id, name, size, type, uploadedBy, date, status;
  const FileItem({
    required this.id,
    required this.name,
    required this.size,
    required this.type,
    required this.uploadedBy,
    required this.date,
    this.status = 'Verified',
  });
}

class TeamModel {
  final String id, name, description;
  final List<String> memberIds;
  final int projectsCount;
  const TeamModel({
    required this.id,
    required this.name,
    required this.description,
    required this.memberIds,
    required this.projectsCount,
  });
}
