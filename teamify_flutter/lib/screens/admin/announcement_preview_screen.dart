import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../data/models/admin_announcement_model.dart';
import '../../services/app_services.dart';
import '../../widgets/admin_announcement_widgets.dart';
import '../../widgets/widgets.dart';

/// Screen 3: Comprehensive Multi-Channel Preview for Admin Announcements.
class AnnouncementPreviewScreen extends StatefulWidget {
  const AnnouncementPreviewScreen({super.key});

  @override
  State<AnnouncementPreviewScreen> createState() =>
      _AnnouncementPreviewScreenState();
}

class _AnnouncementPreviewScreenState extends State<AnnouncementPreviewScreen> {
  bool _sending = false;

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _send(AdminAnnouncement item) async {
    setState(() => _sending = true);
    final result =
        await context.read<AppServices>().admin.broadcastNotification(
              item.audience.apiTarget,
              item.title,
              item.message,
              userId: item.audience == AnnouncementAudience.specificTeam
                  ? item.targetTeamName
                  : null,
            );

    if (!mounted) return;
    setState(() => _sending = false);

    result.when(
      success: (_) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Announcement broadcasted successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      },
      failure: (error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item =
        ModalRoute.of(context)?.settings.arguments as AdminAnnouncement?;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preview Announcement')),
        body: const Center(child: Text('No announcement data available for preview.')),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 18, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Announcement Preview',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 1. Announcement Card Preview ──────────────────────────────
          const TSectionHeader(title: '1. Admin Card Preview'),
          const SizedBox(height: 8),
          AnnouncementCard(announcement: item),
          const SizedBox(height: 16),

          // ── 2. In-App Notification Preview ─────────────────────────────
          if (item.inAppNotification) ...[
            const TSectionHeader(title: '2. In-App Notification Center Preview'),
            const SizedBox(height: 8),
            TCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign,
                        size: 20, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'Just now',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.textHint),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 3. Email Preview ──────────────────────────────────────────
          if (item.emailNotification) ...[
            const TSectionHeader(title: '3. Email Digest Preview'),
            const SizedBox(height: 8),
            TCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Email Header Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.flash_on, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Teamify Platform Digest',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Email Body
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello Teamify User,',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.message,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: const Text('Open Teamify Workspace',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const Text(
                          'You are receiving this email because you subscribed to Teamify Platform Announcements. Manage notifications in Profile Settings.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 10, color: AppColors.textHint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 4. Recipient Summary ──────────────────────────────────────
          const TSectionHeader(title: '4. Recipient & Delivery Summary'),
          const SizedBox(height: 8),
          TCard(
            child: Column(
              children: [
                _summaryRow(
                  icon: item.audience.icon,
                  label: 'Target Segment',
                  value: item.audience.label,
                ),
                const Divider(),
                _summaryRow(
                  icon: Icons.send_outlined,
                  label: 'Delivery Channels',
                  value: item.deliveryType.label,
                ),
                const Divider(),
                _summaryRow(
                  icon: Icons.people_alt_outlined,
                  label: 'Recipients',
                  value: item.recipientCount > 0
                      ? '${item.recipientCount} users'
                      : 'Resolved when sent',
                ),
                if (item.sentAt != null) ...[
                  const Divider(),
                  _summaryRow(
                    icon: Icons.send_outlined,
                    label: 'Sent At',
                    value: _formatDateTime(item.sentAt!),
                    valueColor: AppColors.success,
                  ),
                ],
                if (item.sentByName.isNotEmpty) ...[
                  const Divider(),
                  _summaryRow(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Sent By',
                    value: item.sentByName,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Action Buttons Bar ────────────────────────────────────────
          if (item.status == AnnouncementStatus.sent)
            TButton(
              label: 'Close',
              outline: true,
              onTap: () => Navigator.pop(context),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TButton(
                    label: 'Back to Form',
                    outline: true,
                    onTap: _sending ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TButton(
                    label: _sending ? 'Sending…' : 'Confirm & Send',
                    onTap: _sending ? null : () => _send(item),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _summaryRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
