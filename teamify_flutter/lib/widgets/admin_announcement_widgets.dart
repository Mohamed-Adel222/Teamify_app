import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/models/admin_announcement_model.dart';
import 'widgets.dart';

/// Status badge displaying AnnouncementStatus with icon and background pill.
class StatusBadge extends StatelessWidget {
  final AnnouncementStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Audience chip with category icon.
class AudienceChip extends StatelessWidget {
  final AnnouncementAudience audience;
  final String customTeamName;

  const AudienceChip({
    super.key,
    required this.audience,
    this.customTeamName = '',
  });

  @override
  Widget build(BuildContext context) {
    final label = audience == AnnouncementAudience.specificTeam &&
            customTeamName.isNotEmpty
        ? customTeamName
        : audience.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(audience.icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Delivery badge showing channel indicators.
class DeliveryBadge extends StatelessWidget {
  final AnnouncementDeliveryType type;

  const DeliveryBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            type.label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Announcement Card component.
class AnnouncementCard extends StatelessWidget {
  final AdminAnnouncement announcement;
  final VoidCallback? onTap;
  final PopupMenuItemSelected<String>? onActionSelected;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    this.onTap,
    this.onActionSelected,
  });

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Status Badge + Audience + Action Menu
          Row(
            children: [
              StatusBadge(status: announcement.status),
              const SizedBox(width: 8),
              AudienceChip(
                audience: announcement.audience,
                customTeamName: announcement.targetTeamName,
              ),
              const Spacer(),
              DeliveryBadge(type: announcement.deliveryType),
              if (onActionSelected != null) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: AppColors.textSecondary),
                  onSelected: onActionSelected,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'preview',
                      child: Row(
                        children: [
                          Icon(Icons.visibility_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Preview'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'resend',
                      child: Row(
                        children: [
                          Icon(Icons.copy_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Send again'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Announcement Title
          Text(
            announcement.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),

          // Announcement Short Preview
          Text(
            announcement.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Footer Row: Timestamps
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 12, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(
                announcement.sentAt != null
                    ? 'Sent ${_formatDate(announcement.sentAt!)}'
                    : 'Created ${_formatDate(announcement.createdAt)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
              if (announcement.recipientCount > 0) ...[
                const Spacer(),
                const Icon(Icons.people_outline,
                    size: 12, color: AppColors.success),
                const SizedBox(width: 4),
                Text(
                  '${announcement.recipientCount} recipients',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Search Bar component.
class AnnouncementSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const AnnouncementSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
        decoration: InputDecoration(
          icon: const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
          border: InputBorder.none,
          hintText: 'Search announcements by title or content…',
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: onClear,
                )
              : null,
        ),
      ),
    );
  }
}

/// Empty State component.
class AnnouncementEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onCreatePressed;

  const AnnouncementEmptyState({
    super.key,
    this.title = 'No announcements found',
    this.message =
        'There are no announcements matching your current search or filter criteria.',
    this.onCreatePressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.campaign_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (onCreatePressed != null) ...[
              const SizedBox(height: 20),
              TButton(
                label: '+ Create Announcement',
                onTap: onCreatePressed,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
