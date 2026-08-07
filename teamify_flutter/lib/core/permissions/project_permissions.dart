import 'package:flutter/foundation.dart';

/// Project-level roles for fine-grained access control within a project context.
enum ProjectRole {
  owner,
  admin,
  member,
  viewer,
}

/// Immutable permission engine for project-level role-based access control.
@immutable
class ProjectPermissions {
  final ProjectRole role;

  const ProjectPermissions(this.role);

  /// Factory constructor to create permission instance from role.
  factory ProjectPermissions.forRole(ProjectRole role) =>
      ProjectPermissions(role);

  // ── Project Level ─────────────────────────────────────────────────────────
  bool get canEditProject =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  bool get canDeleteProject => role == ProjectRole.owner;

  bool get canManageMembers =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  bool get canInviteMembers =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  bool get canChangeMemberRoles =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  bool get canTransferOwnership => role == ProjectRole.owner;

  // ── Tasks ─────────────────────────────────────────────────────────────────
  bool get canCreateTasks =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  bool get canEditAnyTask =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  bool get canDeleteTasks =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  bool get canAssignTasks =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  bool get canUpdateAssignedTask =>
      role == ProjectRole.owner ||
      role == ProjectRole.admin ||
      role == ProjectRole.member;

  /// Helper to check if a specific user can update a task based on assignment.
  bool canUpdateTask({
    required String currentUserId,
    required String? assigneeId,
  }) {
    if (role == ProjectRole.owner || role == ProjectRole.admin) return true;
    if (role == ProjectRole.member) {
      if (assigneeId == null || assigneeId.isEmpty) return false;
      return assigneeId == currentUserId;
    }
    return false;
  }

  // ── Files ─────────────────────────────────────────────────────────────────
  bool get canUploadFiles =>
      role == ProjectRole.owner ||
      role == ProjectRole.admin ||
      role == ProjectRole.member;

  bool get canDeleteAnyFile =>
      role == ProjectRole.owner || role == ProjectRole.admin;

  // ── Chat ──────────────────────────────────────────────────────────────────
  bool get canSendMessages =>
      role == ProjectRole.owner ||
      role == ProjectRole.admin ||
      role == ProjectRole.member;

  bool get canViewChat => true;

  // ── General ───────────────────────────────────────────────────────────────
  bool get isReadOnly => role == ProjectRole.viewer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectPermissions &&
          runtimeType == other.runtimeType &&
          role == other.role;

  @override
  int get hashCode => role.hashCode;
}
