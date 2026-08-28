import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../data/models/admin_announcement_model.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

/// Screen 2: Compose and broadcast an announcement via
/// `POST /admin/notifications`.
class CreateAnnouncementScreen extends StatefulWidget {
  const CreateAnnouncementScreen({super.key});

  @override
  State<CreateAnnouncementScreen> createState() =>
      _CreateAnnouncementScreenState();
}

class _CreateAnnouncementScreenState extends State<CreateAnnouncementScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();
  final TextEditingController _userIdCtrl = TextEditingController();

  AnnouncementAudience _audience = AnnouncementAudience.allUsers;
  bool _sending = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_prefilled) return;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is AdminAnnouncement) {
        setState(() {
          _prefilled = true;
          _titleCtrl.text = args.title;
          _messageCtrl.text = args.message;
          _audience = args.audience;
        });
      }
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    _userIdCtrl.dispose();
    super.dispose();
  }

  AdminAnnouncement _buildCurrentAnnouncement({
    required AnnouncementStatus status,
  }) {
    return AdminAnnouncement(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      title: _titleCtrl.text.trim(),
      message: _messageCtrl.text.trim(),
      audience: _audience,
      targetTeamName: _userIdCtrl.text.trim(),
      status: status,
      createdAt: DateTime.now(),
      sentAt: status == AnnouncementStatus.sent ? DateTime.now() : null,
    );
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);

    final result = await context.read<AppServices>().admin.broadcastNotification(
          _audience.apiTarget,
          _titleCtrl.text.trim(),
          _messageCtrl.text.trim(),
          userId: _audience == AnnouncementAudience.specificTeam
              ? _userIdCtrl.text.trim()
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

  Future<void> _navigateToPreview() async {
    if (!_formKey.currentState!.validate()) return;
    final item = _buildCurrentAnnouncement(status: AnnouncementStatus.draft);
    final sent = await Navigator.pushNamed(
      context,
      R.adminAnnouncementsPreview,
      arguments: item,
    );
    if (sent == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          'Create Announcement',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Announcement Details ───────────────────────────────────────
            const TSectionHeader(title: 'Announcement Details'),
            const SizedBox(height: 8),
            TCard(
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Title is required'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Announcement Title',
                      hintText: 'e.g. Platform Maintenance Notice: v2.5',
                      prefixIcon: Icon(Icons.title, color: AppColors.primary),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _messageCtrl,
                    maxLines: 4,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Message is required'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Announcement Message',
                      hintText:
                          'Enter the full announcement text broadcasted to users…',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Audience Selection ─────────────────────────────────────────
            const TSectionHeader(title: 'Target Audience'),
            const SizedBox(height: 8),
            TCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<AnnouncementAudience>(
                    key: ValueKey(_audience),
                    initialValue: _audience,
                    decoration: const InputDecoration(
                      labelText: 'Audience Segment',
                      prefixIcon:
                          Icon(Icons.people_outline, color: AppColors.primary),
                      border: OutlineInputBorder(),
                    ),
                    items: AnnouncementAudienceX.broadcastable.map((aud) {
                      return DropdownMenuItem(
                        value: aud,
                        child: Row(
                          children: [
                            Icon(aud.icon, size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(aud == AnnouncementAudience.specificTeam
                                ? 'Specific User'
                                : aud.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _audience = val);
                    },
                  ),
                  if (_audience == AnnouncementAudience.specificTeam) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _userIdCtrl,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (_audience != AnnouncementAudience.specificTeam) {
                          return null;
                        }
                        if (v == null || v.trim().isEmpty) {
                          return 'User ID is required';
                        }
                        return int.tryParse(v.trim()) == null
                            ? 'User ID must be a number'
                            : null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Recipient User ID',
                        hintText: 'e.g. 42',
                        prefixIcon: Icon(Icons.person_outline,
                            color: AppColors.primary),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Delivery ───────────────────────────────────────────────────
            const TSectionHeader(title: 'Delivery'),
            const SizedBox(height: 8),
            const TCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.notifications_active_outlined,
                    color: AppColors.primary),
                title: Text('In-App Notification',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Delivered immediately to each recipient\'s Notification Center.',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Form Action Buttons Bar ────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TButton(
                    label: 'Preview',
                    outline: true,
                    onTap: _sending ? null : _navigateToPreview,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TButton(
                    label: _sending ? 'Sending…' : 'Send',
                    onTap: _sending ? null : _send,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
