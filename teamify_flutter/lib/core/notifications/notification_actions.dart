import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../theme.dart';
import '../../data/models/models.dart' as api;
import '../../screens/project/project_screens.dart';
import '../../services/app_services.dart';
import '../../core/session/session_controller.dart';
import '../../widgets/widgets.dart';

String notificationTypeLabel(String type) {
  if (type.isEmpty) return 'General';
  return type
      .split('_')
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

String formatNotificationFullDate(String iso) {
  if (iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  final y = local.year;
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

/// Mark read, show details sheet, and open linked task/project when applicable.
Future<void> handleNotificationTap(
  BuildContext context,
  api.ApiNotification n, {
  VoidCallback? onUpdated,
  void Function(String id)? onMarkReadLocally,
}) async {
  if (!context.mounted) return;

  final notification = n.isRead ? n : n.copyWith(isRead: true);
  final type = notification.type.toLowerCase();
  final et = notification.entityType.toLowerCase();
  final isProjectInvitation = type == 'project_invitation' ||
      et == 'projectinvitation' ||
      et == 'project_invitation';

  if (isProjectInvitation) {
    // Mark read locally/API without refreshing the list yet — refreshing would
    // deactivate the ListView item context before the sheet closes.
    if (!n.isRead && n.id.isNotEmpty) {
      onMarkReadLocally?.call(n.id);
      unawaited(
        context.read<AppServices>().notifications.markRead(n.id),
      );
    }
    await _showProjectInvitationSheet(
      context,
      notification,
    );
    onUpdated?.call();
    return;
  }

  if (!n.isRead && n.id.isNotEmpty) {
    onMarkReadLocally?.call(n.id);
    final result =
        await context.read<AppServices>().notifications.markRead(n.id);
    result.when(
      success: (_) => onUpdated?.call(),
      failure: (_) => onUpdated?.call(),
    );
  }

  if (!context.mounted) return;

  if (et == 'task' && notification.entityId.isNotEmpty) {
    await _openTaskDetailFromNotification(context, notification,
        onUpdated: onUpdated);
    return;
  }

  await _showNotificationSheet(context, notification, onUpdated: onUpdated);
}

Future<void> _showProjectInvitationSheet(
  BuildContext context,
  api.ApiNotification n,
) async {
  final invitationId = n.entityId;
  if (invitationId.isEmpty) {
    await _showNotificationSheet(context, n);
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return _ProjectInvitationSheetBody(
        notification: n,
        invitationId: invitationId,
      );
    },
  );
}

class _ProjectInvitationSheetBody extends StatefulWidget {
  const _ProjectInvitationSheetBody({
    required this.notification,
    required this.invitationId,
  });

  final api.ApiNotification notification;
  final String invitationId;

  @override
  State<_ProjectInvitationSheetBody> createState() =>
      _ProjectInvitationSheetBodyState();
}

class _ProjectInvitationSheetBodyState
    extends State<_ProjectInvitationSheetBody> {
  bool _responding = false;
  String? _error;
  AppServices? _services;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = context.read<AppServices>();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  Future<void> _respond(bool accept) async {
    if (_responding) return;
    final services = _services;
    if (services == null) return;

    setState(() {
      _responding = true;
      _error = null;
    });

    try {
      final result = accept
          ? await services.projects.acceptInvitation(widget.invitationId)
          : await services.projects.declineInvitation(widget.invitationId);

      if (!mounted) return;

      if (result.isSuccess) {
        Navigator.pop(context);
        _messenger?.showSnackBar(
          SnackBar(
            content: Text(
              accept ? 'You joined the project' : 'Invitation declined',
            ),
            backgroundColor:
                accept ? AppColors.success : AppColors.textSecondary,
          ),
        );
        return;
      }

      setState(() {
        _responding = false;
        _error = result.error ?? 'Could not update invitation';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _responding = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            n.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TChip(
            label: 'Project invitation',
            bg: AppColors.primary.withValues(alpha: 0.08),
            textColor: AppColors.primary,
            fontSize: 11,
          ),
          const SizedBox(height: 12),
          Text(
            n.body.isNotEmpty
                ? n.body
                : 'You have been invited to join a project.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            formatNotificationFullDate(n.createdAt),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(fontSize: 13, color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: TButton(
              label: _responding ? 'Please wait…' : 'Accept',
              onTap: _responding ? null : () => _respond(true),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TButton(
              label: 'Decline',
              outline: true,
              onTap: _responding ? null : () => _respond(false),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openProjectFromNotification(
  BuildContext context,
  api.ApiNotification n, {
  VoidCallback? onUpdated,
}) async {
  if (n.entityId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This notification has no linked project.'),
        backgroundColor: AppColors.error,
      ),
    );
    return;
  }

  try {
    final result =
        await context.read<AppServices>().projects.getProject(n.entityId);
    if (!context.mounted) return;
    await result.when(
      success: (project) async {
        await Navigator.pushNamed(
          context,
          R.projectDetails,
          arguments: project.toDisplayModel(),
        );
        onUpdated?.call();
      },
      failure: (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e), backgroundColor: AppColors.error),
        );
      },
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ),
    );
  }
}

Future<void> _openTaskDetailFromNotification(
  BuildContext context,
  api.ApiNotification n, {
  VoidCallback? onUpdated,
}) async {
  final services = context.read<AppServices>();
  try {
    final taskResult = await services.tasks.getTask(n.entityId);
    if (!context.mounted) return;
    await taskResult.when(
      success: (task) async {
        if (task.projectId.isEmpty) {
          await _showNotificationSheet(context, n, onUpdated: onUpdated);
          return;
        }
        final projectResult =
            await services.projects.getProject(task.projectId);
        if (!context.mounted) return;
        await projectResult.when(
          success: (project) async {
            final userId =
                context.read<SessionController>().currentUser?.id ?? '';
            final isOwner =
                project.ownerId.isNotEmpty && project.ownerId == userId;
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => TaskDetailScreen(
                  initialTask: task.toDisplayModel(),
                  projectId: task.projectId,
                  isOwner: isOwner,
                ),
              ),
            );
            if (changed == true) onUpdated?.call();
          },
          failure: (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e), backgroundColor: AppColors.error),
            );
            _showNotificationSheet(context, n, onUpdated: onUpdated);
          },
        );
      },
      failure: (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e), backgroundColor: AppColors.error),
        );
        _showNotificationSheet(context, n, onUpdated: onUpdated);
      },
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
    );
    await _showNotificationSheet(context, n, onUpdated: onUpdated);
  }
}

Future<void> _showNotificationSheet(
  BuildContext context,
  api.ApiNotification n, {
  VoidCallback? onUpdated,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              n.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TChip(
              label: notificationTypeLabel(n.type),
              bg: AppColors.primary.withValues(alpha: 0.08),
              textColor: AppColors.primary,
              fontSize: 11,
            ),
            const SizedBox(height: 12),
            Text(
              n.body.isNotEmpty ? n.body : 'No additional details.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              formatNotificationFullDate(n.createdAt),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (n.hasLinkedEntity) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TButton(
                  label: n.entityType.toLowerCase() == 'task'
                      ? 'View task'
                      : 'View ${n.entityType.toLowerCase()}',
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    final et = n.entityType.toLowerCase();
                    if (et == 'task') {
                      await _openTaskDetailFromNotification(
                        context,
                        n,
                        onUpdated: onUpdated,
                      );
                    } else if (et == 'project') {
                      await _openProjectFromNotification(
                        context,
                        n,
                        onUpdated: onUpdated,
                      );
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
