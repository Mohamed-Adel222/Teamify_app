import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/models.dart' as api;
import 'widgets.dart';

/// Rich member row: avatar, name, @username, meta line, optional skills.
class ProjectMemberDetailTile extends StatelessWidget {
  final api.ApiUser user;
  final bool showSkills;
  final bool showJoinedAt;
  final bool useAccountRole;
  final Widget? trailing;

  const ProjectMemberDetailTile({
    super.key,
    required this.user,
    this.showSkills = true,
    this.showJoinedAt = false,
    this.useAccountRole = false,
    this.trailing,
  });

  static String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return value.isNotEmpty ? value[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final name = user.primaryName;
    final role = useAccountRole ? user.displayRole : user.projectRoleLabel;
    final meta = _metaLine(user);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TAvatar(initials: _initials(name), radius: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (role.isNotEmpty) _roleBadge(role),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              if (user.displayName.isNotEmpty && user.displayName != name)
                Text(
                  '@${user.displayName}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              if (role.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    role,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              if (showSkills)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _skillsSection(context, user.skills),
                ),
              if (showJoinedAt && user.joinedAt.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Joined ${_formatJoined(user.joinedAt)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roleBadge(String roleLabel) {
    final l = roleLabel.toLowerCase();
    String text = '👤 Member';
    Color bg = const Color(0xFFF1F5F9);
    Color fg = const Color(0xFF475569);

    if (l.contains('owner')) {
      text = '👑 Owner';
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
    } else if (l.contains('admin')) {
      text = '🛡 Admin';
      bg = const Color(0xFFE0E7FF);
      fg = const Color(0xFF4F46E5);
    } else if (l.contains('viewer')) {
      text = '👁 Viewer';
      bg = const Color(0xFFCCFBF1);
      fg = const Color(0xFF0D9488);
    }

    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  static String _formatJoined(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _skillsSection(BuildContext context, List<String> skills) {
    final visible = skills.where((s) => s.trim().isNotEmpty).take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Skills',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        if (visible.isEmpty)
          const Text(
            'No skills listed',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: visible
                .map(
                  (skill) => TChip(
                    label: skill,
                    fontSize: 10,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  String _metaLine(api.ApiUser user) {
    final parts = <String>[];
    if (user.email.isNotEmpty) parts.add(user.email);
    if (!useAccountRole && user.displayRole.isNotEmpty) {
      parts.add(user.displayRole);
    }
    if (user.professionalField.isNotEmpty) {
      parts.add(user.professionalField);
    }
    if (user.major.isNotEmpty) parts.add(user.major);
    if (user.availability.isNotEmpty) parts.add(user.availability);
    if (user.experienceLevel.isNotEmpty) parts.add(user.experienceLevel);
    if (user.memberExperienceYears > 0) {
      parts.add('${user.memberExperienceYears}y experience');
    }
    if (user.tasksCompleted > 0) {
      parts.add('${user.tasksCompleted} tasks done');
    }
    if (user.qualityScore > 0) {
      parts.add('Quality ${user.qualityScore.toStringAsFixed(0)}%');
    }
    if (user.attendanceRate > 0) {
      parts.add('Attendance ${user.attendanceRate.toStringAsFixed(0)}%');
    }
    return parts.join(' · ');
  }
}
