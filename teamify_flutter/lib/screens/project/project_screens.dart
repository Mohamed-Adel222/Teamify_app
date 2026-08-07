import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../core/permissions/project_permissions.dart';
import '../../data/models/notification_preferences_model.dart';
import '../../services/notification_event_dispatcher.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../core/session/session_controller.dart';
import '../../services/app_services.dart';
import '../../data/models/models.dart' as api;
import '../../models/models.dart';
import '../../core/files/file_downloader.dart';
import '../../widgets/widgets.dart';
import '../../widgets/project_member_detail_tile.dart';
import '../chat/chat_room_utils.dart';

bool _matchesMemberSearch(api.ApiUser user, String query) {
  if (query.isEmpty) return true;
  final hay = '${user.primaryName} ${user.displayName} ${user.email} '
          '${user.memberMetaLine} ${user.skillsSummary} ${user.bio}'
      .toLowerCase();
  return hay.contains(query);
}

Widget _inviteMemberPickerRow({
  required api.ApiUser user,
  required bool selected,
  required bool sending,
  required ValueChanged<bool?> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Checkbox(
            value: selected,
            onChanged: sending ? null : onChanged,
          ),
        ),
        Expanded(
          child: ProjectMemberDetailTile(
            user: user,
            useAccountRole: true,
            showSkills: true,
          ),
        ),
      ],
    ),
  );
}

/// Route arguments for [AddTaskScreen] when opened from a project context.
class AddTaskRouteArgs {
  final String projectId;
  const AddTaskRouteArgs({required this.projectId});
}

String? _routeProjectIdForTask(Object? args) {
  if (args is String && args.isNotEmpty) return args;
  if (args is AddTaskRouteArgs) return args.projectId;
  if (args is Map && args['projectId'] != null) {
    return args['projectId'].toString();
  }
  if (args is ProjectModel) return args.id;
  if (args is api.ApiProject) return args.id;
  return null;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _dateFromDisplay(String display) {
  if (display.isEmpty) return null;
  final parts = display.split('/');
  if (parts.length == 3) {
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d != null && m != null && y != null) return DateTime(y, m, d);
  }
  return DateTime.tryParse(display);
}

String _cleanProjectDescription(String raw) {
  var text = raw.trim();
  if (text.startsWith('[Visibility:')) {
    final end = text.indexOf(']');
    if (end != -1 && end + 1 < text.length) {
      text = text.substring(end + 1).trim();
    }
  }
  return text;
}

String _displayDateLabel(DateTime? d) {
  if (d == null) return 'Not set';
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

String _apiTaskStatusFromUi(String ui) {
  switch (ui) {
    case 'In Progress':
      return 'in_progress';
    case 'Completed':
      return 'done';
    case 'Review':
    case 'Blocked':
    case 'To Do':
    default:
      return 'pending';
  }
}

String _priorityApi(String ui) => ui.toLowerCase();

TaskModel _taskWithMemberNames(
  api.ApiTask task,
  Map<String, api.ApiUser> membersById,
) {
  final base = task.toDisplayModel();
  if (base.assigneeId.isEmpty) return base;
  final member = membersById[base.assigneeId];
  if (member == null) return base;
  final name = member.primaryName;
  return TaskModel(
    id: base.id,
    title: base.title,
    description: base.description,
    assignee: name,
    assigneeId: base.assigneeId,
    assigneeEmail: member.email.isNotEmpty ? member.email : base.assigneeEmail,
    assigneeDisplayName: member.displayName,
    assigneeInitials: api.ApiTask.initialsFrom(name),
    status: base.status,
    priority: base.priority,
    dueDate: base.dueDate,
  );
}

String _taskStatusLabel(String raw) {
  switch (raw) {
    case 'done':
      return 'Done';
    case 'in_progress':
      return 'In Progress';
    default:
      return 'To Do';
  }
}

String _uiTaskStatusFromApi(String raw) {
  switch (raw) {
    case 'done':
      return 'Completed';
    case 'in_progress':
      return 'In Progress';
    default:
      return 'To Do';
  }
}

String _priorityLabelFromApi(String raw) {
  if (raw.isEmpty) return 'Medium';
  return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
}

int _progressFromTasks(List<TaskModel> tasks) {
  if (tasks.isEmpty) return 0;
  final done = tasks.where((t) => t.status == 'done').length;
  return ((done / tasks.length) * 100).round();
}

String _delayRiskDisplayLabel(String? raw) {
  if (raw == null || raw.isEmpty || raw.toLowerCase() == 'unknown') {
    return 'Unknown';
  }
  switch (raw.toLowerCase()) {
    case 'low':
      return 'Low Risk';
    case 'medium':
      return 'Medium Risk';
    case 'high':
      return 'High Risk';
    default:
      return '${raw[0].toUpperCase()}${raw.substring(1)} Risk';
  }
}

Color _delayRiskBg(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'high':
      return const Color(0xFFFEE2E2);
    case 'medium':
      return const Color(0xFFFEF3C7);
    case 'low':
      return const Color(0xFFDCFCE7);
    default:
      return const Color(0xFFF1F5F9);
  }
}

Color _delayRiskText(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'high':
      return const Color(0xFFDC2626);
    case 'medium':
      return const Color(0xFFD97706);
    case 'low':
      return const Color(0xFF16A34A);
    default:
      return AppColors.textSecondary;
  }
}

bool _isKnownDelayRisk(String? risk) =>
    risk != null && risk.isNotEmpty && risk.toLowerCase() != 'unknown';

String _estimateDelayRiskFromTasks(
    List<TaskModel> tasks, ProjectModel project) {
  final active = tasks.where((t) => t.status != 'done').toList();
  if (active.isEmpty) return 'low';

  var score = 0;
  final now = DateTime.now();
  for (final t in active) {
    if (t.dueDate.isEmpty) continue;
    DateTime? due = DateTime.tryParse(t.dueDate);
    if (due == null) continue;
    final days = due.difference(now).inDays;
    if (days < 0) {
      score += 3;
    } else if (days <= 2) {
      score += 2;
    } else if (days <= 5) {
      score += 1;
    }
    if (t.status == 'pending' && days <= 3) score += 1;
  }

  if (project.endDate.isNotEmpty) {
    final parts = project.endDate.split('/');
    if (parts.length == 3) {
      final end = DateTime.tryParse(
        '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}',
      );
      if (end != null) {
        final daysToEnd = end.difference(now).inDays;
        if (daysToEnd < 0) {
          score += 3;
        } else if (daysToEnd <= 7) {
          score += 1;
        }
      }
    }
  }

  if (score >= 5) return 'high';
  if (score >= 2) return 'medium';
  return 'low';
}

String _projectListDateLabel(ProjectModel p) {
  if (p.endDate.isNotEmpty) return 'Due ${p.endDate}';
  if (p.startDate.isNotEmpty) return 'Started ${p.startDate}';
  return 'No due date';
}

String _projectListSubtitle(ProjectModel p) {
  if (p.ownerName.isNotEmpty) return p.ownerName;
  if (p.company.isNotEmpty && p.company != 'Teamify') return p.company;
  if (p.status.isNotEmpty) {
    return p.status[0].toUpperCase() + p.status.substring(1);
  }
  return 'Project';
}

String _estimateDelayRiskFromProjectDates(ProjectModel p) {
  if (p.endDate.isEmpty) {
    return p.progress >= 100 ? 'low' : 'medium';
  }
  final parts = p.endDate.split('/');
  if (parts.length != 3) return 'unknown';
  final end = DateTime.tryParse(
    '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}',
  );
  if (end == null) return 'unknown';
  final days = end.difference(DateTime.now()).inDays;
  if (days < 0) return 'high';
  if (days <= 3) return p.progress >= 90 ? 'medium' : 'high';
  if (days <= 7 && p.progress < 70) return 'medium';
  return 'low';
}

/// Full task view with role-based actions (owner vs member).
class TaskDetailScreen extends StatefulWidget {
  final TaskModel initialTask;
  final String projectId;
  final bool isOwner;

  const TaskDetailScreen({
    super.key,
    required this.initialTask,
    required this.projectId,
    required this.isOwner,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late TaskModel _task;
  bool _busy = false;
  bool _editing = false;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _editStatus = 'To Do';
  String _editPriority = 'Medium';
  String? _editAssigneeId;
  List<api.ApiUser> _members = [];

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    _syncEditorsFromTask();
    _loadMembers();
    _refreshTask();
  }

  void _syncEditorsFromTask() {
    _titleCtrl.text = _task.title;
    _descCtrl.text = _task.description;
    _editStatus = _uiTaskStatusFromApi(_task.status);
    _editPriority = _priorityLabelFromApi(_task.priority);
    _editAssigneeId = _task.assigneeId.isEmpty ? null : _task.assigneeId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshTask() async {
    try {
      final result = await context.read<AppServices>().tasks.getTask(_task.id);
      if (!mounted) return;
      result.when(
        success: (apiTask) {
          setState(() {
            _task = apiTask.toDisplayModel();
            if (!_editing) _syncEditorsFromTask();
          });
        },
        failure: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _loadMembers() async {
    final result = await context
        .read<AppServices>()
        .projects
        .listMembers(widget.projectId);
    if (!mounted) return;
    result.when(
      success: (users) => setState(() => _members = users),
      failure: (_) {},
    );
  }

  Future<void> _updateStatus(String apiStatus) async {
    setState(() => _busy = true);
    try {
      final result = await context
          .read<AppServices>()
          .tasks
          .updateStatus(_task.id, apiStatus);
      if (!mounted) return;
      result.when(
        success: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Status updated')),
          );
          Navigator.pop(context, true);
        },
        failure: (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e), backgroundColor: AppColors.error),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEdits() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }
    setState(() => _busy = true);
    final pid = int.tryParse(widget.projectId);
    if (pid == null) return;
    try {
      final payload = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'project_id': pid,
        'status': _apiTaskStatusFromUi(_editStatus),
        'priority': _priorityApi(_editPriority),
      };
      if (_editAssigneeId != null && _editAssigneeId!.isNotEmpty) {
        final aid = int.tryParse(_editAssigneeId!);
        if (aid != null) payload['assigned_to'] = aid;
      } else {
        payload['assigned_to'] = null;
      }
      final result =
          await context.read<AppServices>().tasks.updateTask(_task.id, payload);
      if (!mounted) return;
      result.when(
        success: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Task updated'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        },
        failure: (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e), backgroundColor: AppColors.error),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTask() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Remove "${_task.title}" permanently?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result =
          await context.read<AppServices>().tasks.deleteTask(_task.id);
      if (!mounted) return;
      result.when(
        success: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task deleted')),
          );
          Navigator.pop(context, true);
        },
        failure: (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e), backgroundColor: AppColors.error),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _assigneeEditLabel() {
    if (_editAssigneeId == null) return 'Unassigned';
    for (final m in _members) {
      if (m.id == _editAssigneeId) return m.primaryName;
    }
    return 'Selected member';
  }

  Future<void> _pickAssignee() async {
    if (_members.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Assign to',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Unassigned'),
              onTap: () {
                setState(() => _editAssigneeId = null);
                Navigator.pop(ctx);
              },
            ),
            ..._members.map(
              (u) => ListTile(
                title: ProjectMemberDetailTile(user: u),
                onTap: () {
                  setState(() => _editAssigneeId = u.id);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary)),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  bool get _isAssignedToCurrentUser {
    final me = context.read<SessionController>().currentUser?.id ?? '';
    return _task.assigneeId.isNotEmpty && _task.assigneeId == me;
  }

  /// Owners manage any task; members only their own assigned tasks.
  bool get _canUpdateStatus => widget.isOwner || _isAssignedToCurrentUser;

  @override
  Widget build(BuildContext context) {
    final statusLabel = _taskStatusLabel(_task.status);
    final assigneeMeta = <String>[
      if (_task.assigneeEmail.isNotEmpty) _task.assigneeEmail,
      if (_task.dueDate.isNotEmpty) 'Due ${_task.dueDate}',
    ].join(' · ');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_editing ? 'Edit task' : 'Task details',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (widget.isOwner && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _editing = true;
                        _syncEditorsFromTask();
                      }),
            ),
          if (widget.isOwner && _editing)
            TextButton(
              onPressed: _busy ? null : () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!widget.isOwner)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _canUpdateStatus
                          ? 'This task is assigned to you. You can update its status only. '
                              'The project owner can edit, delete, or reassign tasks.'
                          : 'View only — you can change status only on tasks assigned to you. '
                              'The project owner can edit, delete, or reassign tasks.',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                if (_editing) ...[
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('edit-status-$_editStatus'),
                    initialValue: _editStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      'To Do',
                      'In Progress',
                      'Completed',
                    ]
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _editStatus = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('edit-priority-$_editPriority'),
                    initialValue: _editPriority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                    ),
                    items: ['Low', 'Medium', 'High']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _editPriority = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Assignee'),
                    subtitle: Text(_assigneeEditLabel()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickAssignee,
                  ),
                  const SizedBox(height: 16),
                  TButton(label: 'Save changes', onTap: _saveEdits),
                ] else ...[
                  TCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_task.title,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        if (_task.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(_task.description,
                              style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: AppColors.textSecondary)),
                        ],
                        const SizedBox(height: 12),
                        _detailRow('Status', statusLabel),
                        _detailRow(
                            'Priority', _priorityLabelFromApi(_task.priority)),
                        _detailRow(
                          'Assignee',
                          _task.assignee.isNotEmpty
                              ? _task.assignee
                              : 'Unassigned',
                        ),
                        if (assigneeMeta.isNotEmpty)
                          _detailRow('Details', assigneeMeta),
                      ],
                    ),
                  ),
                  if (_canUpdateStatus) ...[
                    const SizedBox(height: 16),
                    const Text('Update status',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusChip('To Do', 'pending'),
                        _statusChip('In Progress', 'in_progress'),
                        _statusChip('Completed', 'done'),
                      ],
                    ),
                  ] else if (!widget.isOwner) ...[
                    const SizedBox(height: 12),
                    Text(
                      _task.assigneeId.isEmpty
                          ? 'This task is unassigned. Ask the project owner to assign it to you if you need to update it.'
                          : 'Status can only be changed by the assignee (${_task.assignee}) or the project owner.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (widget.isOwner) ...[
                    const SizedBox(height: 24),
                    const Text('Owner actions',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    TButton(
                      label: 'Edit task',
                      outline: true,
                      icon: Icons.edit_outlined,
                      onTap: () => setState(() {
                        _editing = true;
                        _syncEditorsFromTask();
                      }),
                    ),
                    const SizedBox(height: 8),
                    TButton(
                      label: 'Change assignee',
                      outline: true,
                      icon: Icons.person_add_outlined,
                      onTap: () {
                        setState(() {
                          _editing = true;
                          _syncEditorsFromTask();
                        });
                        _pickAssignee();
                      },
                    ),
                    const SizedBox(height: 8),
                    TButton(
                      label: 'Delete task',
                      onTap: _deleteTask,
                      icon: Icons.delete_outline,
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _statusChip(String label, String apiValue) {
    final selected = _task.status == apiValue;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: _canUpdateStatus ? (_) => _updateStatus(apiValue) : null,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      checkmarkColor: AppColors.primary,
    );
  }
}

class ProjectDetailsScreen extends StatefulWidget {
  const ProjectDetailsScreen({super.key});
  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabLabels = [
    'Overview',
    'Tasks',
    'Files',
    'Chat',
    'Analytics'
  ];

  ProjectModel? _project;
  List<TaskModel> _tasks = [];
  bool _tasksLoading = false;
  String? _tasksError;
  bool _delayRiskLoading = false;
  int _filesRefreshToken = 0;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: _tabLabels.length, vsync: this, initialIndex: 0);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index == 2) {
        setState(() => _filesRefreshToken++);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_project != null) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    final p = args is ProjectModel
        ? args
        : args is api.ApiProject
            ? args.toDisplayModel()
            : null;
    if (p == null) return;
    setState(() {
      _project = p;
      _tasks = List<TaskModel>.from(p.tasks);
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _bootstrapProjectData());
  }

  Future<void> _bootstrapProjectData() async {
    await _refreshProjectFromApi();
    await _fetchTasks();
    await _loadDelayRisk();
  }

  void _setDelayRisk(String risk) {
    if (!mounted || _project == null) return;
    setState(() => _project = _project!.copyWith(delayRisk: risk));
  }

  /// Reload project from DB so owner name, dates, and description are current.
  Future<void> _refreshProjectFromApi() async {
    final id = _project?.id;
    if (id == null || id.isEmpty || !mounted) return;
    try {
      final result = await context.read<AppServices>().projects.getProject(id);
      if (!mounted) return;
      result.when(
        success: (apiProject) {
          final fresh = apiProject.toDisplayModel();
          final progress =
              _tasks.isNotEmpty ? _progressFromTasks(_tasks) : fresh.progress;
          final keepRisk = _project?.delayRisk;
          setState(() {
            _project = fresh.copyWith(
              tasks: _tasks,
              progress: progress,
              delayRisk:
                  _isKnownDelayRisk(keepRisk) ? keepRisk! : fresh.delayRisk,
            );
          });
        },
        failure: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _loadDelayRisk() async {
    final proj = _project;
    if (proj == null || proj.id.isEmpty || !mounted) return;
    setState(() => _delayRiskLoading = true);
    try {
      final result = await context.read<AppServices>().ai.predictDelay(
            projectId: proj.id,
            forceRefresh: true,
          );
      if (!mounted) return;
      result.when(
        success: (data) {
          final err = data['error']?.toString();
          if (err != null && err.isNotEmpty) {
            _setDelayRisk(_estimateDelayRiskFromTasks(_tasks, proj));
          } else {
            final risk = data['risk_level']?.toString();
            _setDelayRisk(
              _isKnownDelayRisk(risk)
                  ? risk!
                  : _estimateDelayRiskFromTasks(_tasks, proj),
            );
          }
          if (mounted) setState(() => _delayRiskLoading = false);
        },
        failure: (_) {
          _setDelayRisk(_estimateDelayRiskFromTasks(_tasks, proj));
          if (mounted) setState(() => _delayRiskLoading = false);
        },
      );
    } catch (_) {
      _setDelayRisk(_estimateDelayRiskFromTasks(_tasks, proj));
      if (mounted) setState(() => _delayRiskLoading = false);
    }
  }

  Future<void> _editProjectDetails() async {
    final proj = _project;
    if (proj == null || !mounted) return;

    final updated = await showModalBottomSheet<api.ApiProject>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EditProjectSheet(project: proj),
    );
    if (updated == null || !mounted) return;

    final fresh = updated.toDisplayModel();
    setState(() {
      _project = fresh.copyWith(
        tasks: _tasks,
        progress:
            _tasks.isNotEmpty ? _progressFromTasks(_tasks) : fresh.progress,
        delayRisk: proj.delayRisk,
      );
    });
    _loadDelayRisk();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Project updated')),
    );
  }

  Future<void> _openAddTaskForProject() async {
    final proj = _project;
    if (proj == null) return;
    final created = await Navigator.pushNamed(
      context,
      R.addTask,
      arguments: {'projectId': proj.id},
    );
    if (mounted) {
      if (created == true) {
        NotificationEventDispatcher.triggerEvent(
          context: context,
          type: NotificationType.taskAssigned,
          title: 'New Task Assigned',
          body: 'A new task was created and assigned in "${proj.name}".',
          entityType: 'project',
          entityId: proj.id,
        );
      }
      await _fetchTasks();
    }
  }

  Future<void> _fetchTasks() async {
    final proj = _project;
    if (proj == null || !mounted) return;
    setState(() {
      _tasksLoading = true;
      _tasksError = null;
    });
    try {
      final svc = context.read<AppServices>();
      final membersFuture = svc.projects.listMembers(proj.id);
      final tasksFuture = svc.tasks.listTasks(
        projectId: proj.id,
        forceRefresh: true,
      );
      final membersResult = await membersFuture;
      final result = await tasksFuture;
      if (!mounted) return;
      final membersById = <String, api.ApiUser>{};
      membersResult.when(
        success: (members) {
          for (final m in members) {
            membersById[m.id] = m;
          }
        },
        failure: (_) {},
      );
      result.when(
        success: (tasks) {
          final models =
              tasks.map((t) => _taskWithMemberNames(t, membersById)).toList();
          final progress = _progressFromTasks(models);
          final keepRisk = _project?.delayRisk;
          setState(() {
            _tasks = models;
            _tasksLoading = false;
            _project = proj.copyWith(
              tasks: models,
              progress: progress,
              delayRisk:
                  _isKnownDelayRisk(keepRisk) ? keepRisk! : proj.delayRisk,
            );
            _tasksError = null;
          });
        },
        failure: (err) {
          setState(() {
            _tasksLoading = false;
            _tasksError = err;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tasksLoading = false;
        _tasksError = e.toString();
      });
    }
  }

  ProjectRole _activeDemoRole = ProjectRole.owner;

  ProjectRole _resolveActiveRole(ProjectModel p, String currentUserId) {
    if (AppConfig.isDemoMode) {
      return _activeDemoRole;
    }
    if (p.ownerId.isNotEmpty && p.ownerId == currentUserId) {
      return ProjectRole.owner;
    }
    return ProjectRole.member;
  }

  Widget _buildDemoRoleSelector() {
    final roleName = _activeDemoRole.name[0].toUpperCase() +
        _activeDemoRole.name.substring(1);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: PopupMenuButton<ProjectRole>(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onSelected: (role) {
          setState(() => _activeDemoRole = role);
          NotificationEventDispatcher.triggerEvent(
            context: context,
            type: NotificationType.roleChanged,
            title: 'Role & Permissions Changed',
            body:
                'Your role in "${_project?.name ?? 'Project'}" was updated to ${role.name.toUpperCase()}.',
            entityType: 'project',
            entityId: _project?.id ?? '',
          );
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: ProjectRole.owner, child: Text('Owner')),
          PopupMenuItem(value: ProjectRole.admin, child: Text('Admin')),
          PopupMenuItem(value: ProjectRole.member, child: Text('Member')),
          PopupMenuItem(value: ProjectRole.viewer, child: Text('Viewer')),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined,
                size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Role: $roleName',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down,
                size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _delayRiskWidget(String? risk) {
    return Row(
      children: [
        const Text('Delay Risk: ',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(width: 4),
        if (_delayRiskLoading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _delayRiskBg(risk),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _delayRiskDisplayLabel(risk),
              style: TextStyle(
                color: _delayRiskText(risk),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    if (p == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: AppColors.primary, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No project selected or data is invalid.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentUserId =
        context.read<SessionController>().currentUser?.id ?? '';
    final activeRole = _resolveActiveRole(p, currentUserId);
    final permissions = ProjectPermissions.forRole(activeRole);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        toolbarHeight: 48,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppColors.primary, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (permissions.canCreateTasks)
                      ElevatedButton.icon(
                        onPressed: _openAddTaskForProject,
                        icon: const Icon(Icons.add_task, size: 16),
                        label: const Text('New Task',
                            style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    if (permissions.canEditProject) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Edit project',
                        onPressed: _editProjectDetails,
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(p.company,
                    style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                if (AppConfig.isDemoMode) _buildDemoRoleSelector(),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Overall Process',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface)),
                    Text('${p.progress}%',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (p.progress / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                _delayRiskWidget(p.delayRisk),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabLabels.length,
              itemBuilder: (context, i) {
                final sel = _tabController.index == i;
                return GestureDetector(
                  onTap: () => setState(() => _tabController.index = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                        child: Text(_tabLabels[i],
                            style: TextStyle(
                                color: sel
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12))),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0F172A)
                  : const Color(0xFFF8FAFC),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _OverviewTab(project: p, permissions: permissions),
                  _TasksTab(
                    projectId: p.id,
                    tasks: _tasks,
                    loading: _tasksLoading,
                    errorMessage: _tasksError,
                    onRetry: _fetchTasks,
                    onRefreshTasks: _fetchTasks,
                    permissions: permissions,
                  ),
                  _FilesTab(
                    projectId: p.id,
                    refreshToken: _filesRefreshToken,
                  ),
                  _ChatTab(project: p),
                  _AnalyticsTab(project: p),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          TBottomNav(current: 0, onTap: (i) => handleRoleNav(context, i)),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
class _OverviewTab extends StatefulWidget {
  final ProjectModel project;
  final ProjectPermissions permissions;
  const _OverviewTab({required this.project, required this.permissions});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  List<api.ApiUser>? _members;
  List<api.ApiProjectInvitation> _invitations = [];
  bool _membersLoading = true;
  bool _invitationsLoading = false;
  final TextEditingController _inviteSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchMembers();
      if (widget.permissions.canInviteMembers) _fetchInvitations();
    });
  }

  @override
  void dispose() {
    _inviteSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMembers() async {
    try {
      final result = await context
          .read<AppServices>()
          .projects
          .listMembers(widget.project.id);
      if (!mounted) return;
      result.when(
        success: (users) => setState(() {
          _members = users;
          _membersLoading = false;
        }),
        failure: (_) => setState(() => _membersLoading = false),
      );
    } catch (_) {
      if (mounted) setState(() => _membersLoading = false);
    }
  }

  Future<void> _fetchInvitations() async {
    if (!widget.permissions.canInviteMembers) return;
    setState(() => _invitationsLoading = true);
    try {
      final result = await context
          .read<AppServices>()
          .projects
          .listProjectInvitations(widget.project.id);
      if (!mounted) return;
      result.when(
        success: (rows) => setState(() {
          _invitations = rows;
          _invitationsLoading = false;
        }),
        failure: (_) => setState(() => _invitationsLoading = false),
      );
    } catch (_) {
      if (mounted) setState(() => _invitationsLoading = false);
    }
  }

  Future<void> _refreshTeamSection() async {
    await Future.wait([_fetchMembers(), _fetchInvitations()]);
  }

  String _duration() {
    final s = widget.project.startDate;
    final e = widget.project.endDate;
    if (s.isEmpty && e.isEmpty) return 'No dates set';
    if (s.isEmpty) return 'Until $e';
    if (e.isEmpty) return 'From $s';
    return '$s – $e';
  }

  String _ownerDisplayName(ProjectModel p) {
    if (p.ownerName.isNotEmpty) return p.ownerName;
    if (_members != null) {
      for (final u in _members!) {
        if (u.projectRoleLabel == 'Owner' || u.role.toLowerCase() == 'owner') {
          return u.fullName.isNotEmpty ? u.fullName : u.displayName;
        }
      }
    }
    return 'Unknown';
  }

  Set<String> get _existingMemberIds {
    final ids = <String>{widget.project.ownerId};
    for (final u in _members ?? const []) {
      if (u.id.isNotEmpty) ids.add(u.id);
    }
    return ids;
  }

  Set<String> get _pendingInviteeIds => _invitations
      .where((inv) => inv.isPending)
      .map((inv) => inv.inviteeId)
      .where((id) => id.isNotEmpty)
      .toSet();

  bool _canInviteUser(api.ApiUser user) =>
      !user.isAdmin &&
      user.id.isNotEmpty &&
      !_existingMemberIds.contains(user.id) &&
      !_pendingInviteeIds.contains(user.id);

  bool _userMatchesInviteSearch(api.ApiUser user, String query) =>
      _matchesMemberSearch(user, query);

  Widget _inviteMemberRow({
    required api.ApiUser user,
    required bool selected,
    required bool sending,
    required ValueChanged<bool?> onChanged,
  }) =>
      _inviteMemberPickerRow(
        user: user,
        selected: selected,
        sending: sending,
        onChanged: onChanged,
      );

  Future<void> _openInviteMembersDialog() async {
    final selected = <String>{};
    var loadingUsers = true;
    var sending = false;
    String? loadError;
    List<api.ApiUser> allUsers = [];

    final projects = context.read<AppServices>().projects;
    final result = await projects.getAvailableMembers();
    result.when(
      success: (users) {
        allUsers = users.where(_canInviteUser).toList();
        loadingUsers = false;
      },
      failure: (e) {
        loadError = e;
        loadingUsers = false;
      },
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final q = _inviteSearchController.text.trim().toLowerCase();
          final visible =
              allUsers.where((m) => _userMatchesInviteSearch(m, q)).toList();

          Future<void> sendInvites() async {
            if (selected.isEmpty || sending) return;
            setDialog(() => sending = true);
            var sent = 0;
            var failed = 0;
            for (final id in selected) {
              final r = await projects.addMember(widget.project.id, id);
              r.when(
                success: (_) {
                  sent++;
                  NotificationEventDispatcher.triggerEvent(
                    context: context,
                    type: NotificationType.teamInvitation,
                    title: 'Project Invitation',
                    body: 'You were invited to join "${widget.project.name}".',
                    entityType: 'project',
                    entityId: widget.project.id,
                  );
                },
                failure: (_) => failed++,
              );
            }
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (!mounted) return;
            final msg = failed == 0
                ? '$sent invitation${sent == 1 ? '' : 's'} sent'
                : '$sent sent, $failed failed';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
            _refreshTeamSection();
          }

          return AlertDialog(
            title: const Text('Invite team members'),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SizedBox(
              width: double.maxFinite,
              height: 520,
              child: loadingUsers
                  ? const Center(child: CircularProgressIndicator())
                  : loadError != null
                      ? Center(
                          child: Text(
                            loadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        )
                      : Column(
                          children: [
                            TextField(
                              controller: _inviteSearchController,
                              decoration: InputDecoration(
                                hintText: 'Search name, email, skills, field…',
                                prefixIcon: const Icon(Icons.search, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              onChanged: (_) => setDialog(() {}),
                            ),
                            const SizedBox(height: 8),
                            if (allUsers.isEmpty)
                              const Expanded(
                                child: Center(
                                  child: Text(
                                    'Everyone available is already on this project.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              )
                            else if (visible.isEmpty)
                              const Expanded(
                                child: Center(child: Text('No users found')),
                              )
                            else
                              Expanded(
                                child: ListView.builder(
                                  itemCount: visible.length,
                                  itemBuilder: (_, i) {
                                    final m = visible[i];
                                    final isSelected = selected.contains(m.id);
                                    return _inviteMemberRow(
                                      user: m,
                                      selected: isSelected,
                                      sending: sending,
                                      onChanged: (_) {
                                        setDialog(() {
                                          if (isSelected) {
                                            selected.remove(m.id);
                                          } else {
                                            selected.add(m.id);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: (sending || selected.isEmpty) ? null : sendInvites,
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        selected.isEmpty
                            ? 'Send invitations'
                            : 'Send (${selected.length})',
                      ),
              ),
            ],
          );
        },
      ),
    );

    _inviteSearchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _buildCard('Project Summary', [
          _infoRow('Duration', _duration(), Icons.calendar_today_outlined),
          _infoRow(
            'Project Owner',
            _ownerDisplayName(p),
            Icons.person_outline,
            trailing: widget.permissions.role == ProjectRole.owner
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('You',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          const Text('Description',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(
            p.description.isNotEmpty ? p.description : 'No description.',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.6),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Team Members',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (widget.permissions.canInviteMembers)
                    TextButton.icon(
                      onPressed:
                          _membersLoading ? null : _openInviteMembersDialog,
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: const Text('Invite'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                ],
              ),
              if (widget.permissions.canInviteMembers) ...[
                const SizedBox(height: 4),
                const Text(
                  'Pending invites appear below until accepted or declined.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (widget.permissions.canInviteMembers) ...[
                _buildInvitationsSection(),
                const SizedBox(height: 12),
              ],
              if (_membersLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_members == null || _members!.isEmpty)
                const Text(
                  'No team members found',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                )
              else
                ..._members!.map(
                  (u) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ProjectMemberDetailTile(
                      user: u,
                      showJoinedAt: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInvitationsSection() {
    if (_invitationsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_invitations.isEmpty) {
      return const Text(
        'No invitations sent yet.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Invitations',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ..._invitations.map(_invitationRow),
      ],
    );
  }

  Widget _invitationRow(api.ApiProjectInvitation inv) {
    Color badgeBg;
    Color badgeFg;
    IconData badgeIcon;
    switch (inv.status.toLowerCase()) {
      case 'accepted':
        badgeBg = AppColors.success.withValues(alpha: 0.12);
        badgeFg = AppColors.success;
        badgeIcon = Icons.check_circle_outline;
        break;
      case 'declined':
        badgeBg = AppColors.error.withValues(alpha: 0.12);
        badgeFg = AppColors.error;
        badgeIcon = Icons.cancel_outlined;
        break;
      default:
        badgeBg = const Color(0xFFFFF3E0);
        badgeFg = const Color(0xFFE65100);
        badgeIcon = Icons.schedule;
    }

    final skills = inv.inviteeSkills.where((s) => s.trim().isNotEmpty).take(6);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (inv.inviteeEmail.isNotEmpty)
                      Text(
                        inv.inviteeEmail,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 14, color: badgeFg),
                    const SizedBox(width: 4),
                    Text(
                      inv.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeFg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  skills.map((s) => TChip(label: s, fontSize: 10)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(String title, List<Widget> children, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6)
            ],
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String l, String v, IconData i, {Widget? trailing}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(i, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('$l: ',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            if (trailing != null) trailing,
          ]));
}

// ── Tasks Tab ─────────────────────────────────────────────────────────────────
class _TasksTab extends StatefulWidget {
  final String projectId;
  final List<TaskModel> tasks;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onRetry;
  final Future<void> Function() onRefreshTasks;
  final ProjectPermissions permissions;

  const _TasksTab({
    required this.projectId,
    required this.tasks,
    required this.loading,
    required this.errorMessage,
    required this.onRetry,
    required this.onRefreshTasks,
    required this.permissions,
  });

  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab> {
  String? _statusFilter;
  String? _peopleFilter;
  String? _priorityFilter;

  List<TaskModel> get _filteredTasks {
    return widget.tasks.where((t) {
      if (_statusFilter != null && t.status != _statusFilter) return false;
      if (_priorityFilter != null &&
          t.priority.toLowerCase() != _priorityFilter) {
        return false;
      }
      if (_peopleFilter != null) {
        if (_peopleFilter == '_unassigned') {
          return t.assigneeId.isEmpty;
        }
        if (t.assigneeId != _peopleFilter) return false;
      }
      return true;
    }).toList();
  }

  String get _statusLabel {
    switch (_statusFilter) {
      case 'pending':
        return 'To Do';
      case 'in_progress':
        return 'In Progress';
      case 'done':
        return 'Completed';
      default:
        return 'All Status';
    }
  }

  String get _peopleLabel {
    if (_peopleFilter == null) return 'All People';
    if (_peopleFilter == '_unassigned') return 'Unassigned';
    for (final t in widget.tasks) {
      if (t.assigneeId == _peopleFilter) return t.assignee;
    }
    return 'Assignee';
  }

  String get _priorityLabel => _priorityFilter == null
      ? 'All Priority'
      : _priorityFilter![0].toUpperCase() + _priorityFilter!.substring(1);

  Future<void> _pickFilter({
    required String title,
    required List<MapEntry<String?, String>> options,
    required String? current,
    required void Function(String?) onPick,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
            ...options.map(
              (e) => ListTile(
                title: Text(e.value),
                trailing: current == e.key
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  onPick(e.key);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openTaskDetail(TaskModel t) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          initialTask: t,
          projectId: widget.projectId,
          isOwner: widget.permissions.canEditAnyTask,
        ),
      ),
    );
    if (changed == true && context.mounted) {
      NotificationEventDispatcher.triggerEvent(
        context: context,
        type: NotificationType.taskUpdated,
        title: 'Task Updated',
        body: 'Status or details for task "${t.title}" were updated.',
        entityType: 'task',
        entityId: t.id,
      );
      await widget.onRefreshTasks();
    }
  }

  List<MapEntry<String?, String>> get _peopleOptions {
    final seen = <String>{};
    final opts = <MapEntry<String?, String>>[
      const MapEntry(null, 'All People'),
      const MapEntry('_unassigned', 'Unassigned'),
    ];
    for (final t in widget.tasks) {
      if (t.assigneeId.isEmpty || seen.contains(t.assigneeId)) continue;
      seen.add(t.assigneeId);
      opts.add(MapEntry(t.assigneeId, t.assignee));
    }
    return opts;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredTasks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.grid_view_rounded,
                    size: 24, color: AppColors.textSecondary)),
            const Spacer(),
            if (widget.permissions.canCreateTasks)
              ElevatedButton.icon(
                onPressed: widget.loading
                    ? null
                    : () async {
                        final created = await Navigator.pushNamed(
                          context,
                          R.addTask,
                          arguments:
                              AddTaskRouteArgs(projectId: widget.projectId),
                        );
                        if (!context.mounted) return;
                        if (created != null) await widget.onRefreshTasks();
                      },
                icon: const Icon(Icons.add, size: 20, color: Colors.white),
                label: const Text('Add Task',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            _filterChip(
              _statusLabel,
              () => _pickFilter(
                title: 'Filter by status',
                current: _statusFilter,
                options: const [
                  MapEntry(null, 'All Status'),
                  MapEntry('pending', 'To Do'),
                  MapEntry('in_progress', 'In Progress'),
                  MapEntry('done', 'Completed'),
                ],
                onPick: (v) => setState(() => _statusFilter = v),
              ),
            ),
            const SizedBox(width: 8),
            _filterChip(
              _peopleLabel,
              () => _pickFilter(
                title: 'Filter by assignee',
                current: _peopleFilter,
                options: _peopleOptions,
                onPick: (v) => setState(() => _peopleFilter = v),
              ),
            ),
            const SizedBox(width: 8),
            _filterChip(
              _priorityLabel,
              () => _pickFilter(
                title: 'Filter by priority',
                current: _priorityFilter,
                options: const [
                  MapEntry(null, 'All Priority'),
                  MapEntry('low', 'Low'),
                  MapEntry('medium', 'Medium'),
                  MapEntry('high', 'High'),
                ],
                onPick: (v) => setState(() => _priorityFilter = v),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(visible)),
      ],
    );
  }

  Widget _buildBody(List<TaskModel> visible) {
    if (widget.loading && widget.tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.errorMessage != null && widget.tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(
          widget.tasks.isEmpty
              ? 'No tasks yet. Add one to get started.'
              : 'No tasks match these filters.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: widget.onRefreshTasks,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: visible.length,
        itemBuilder: (ctx, i) => _taskCard(visible[i]),
      ),
    );
  }

  Widget _taskCard(TaskModel t) {
    final rawStatus = t.status;
    final statusLabel = _taskStatusLabel(rawStatus);
    final isDone = rawStatus == 'done';
    final assigneeMeta = <String>[
      if (t.assigneeEmail.isNotEmpty) t.assigneeEmail,
      if (t.assigneeDisplayName.isNotEmpty &&
          t.assigneeDisplayName != t.assignee)
        '@${t.assigneeDisplayName}',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openTaskDetail(t),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _badge(
                      statusLabel,
                      isDone
                          ? const Color(0xFFDCFCE7)
                          : AppColors.primary.withValues(alpha: 0.1),
                      isDone ? const Color(0xFF16A34A) : AppColors.primary),
                ],
              ),
              if (t.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  t.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TAvatar(initials: t.assigneeInitials, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.assignee,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (assigneeMeta.isNotEmpty)
                          Text(
                            assigneeMeta,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (t.dueDate.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Due ${t.dueDate}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _badge(
                    t.priority[0].toUpperCase() + t.priority.substring(1),
                    const Color(0xFFFEF2F2),
                    const Color(0xFFDC2626),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: fg,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _filterChip(String label, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down,
                    size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      );
}

// ── Files Tab ─────────────────────────────────────────────────────────────────
class _FilesTab extends StatefulWidget {
  final String? projectId;
  final int refreshToken;
  const _FilesTab({this.projectId, this.refreshToken = 0});

  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab> {
  String _selectedFilter = 'ALL';
  bool _uploading = false;
  int _fileVersion = 0;
  String? _busyFileId;

  @override
  void didUpdateWidget(covariant _FilesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      setState(() => _fileVersion++);
    }
  }

  Future<void> _pickAndUpload() async {
    final svc = context.read<AppServices>();
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    final bytes = picked.bytes;
    if (path == null && bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cannot access file data.'),
              behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    setState(() => _uploading = true);
    try {
      final res = await svc.files.uploadFile(
        filePath: path ?? '',
        filename: picked.name,
        projectId: widget.projectId,
        fileBytes: bytes,
      );
      if (!mounted) return;
      res.when(
        success: (_) {
          setState(() {
            _uploading = false;
            _fileVersion++;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${picked.name} uploaded successfully'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green.shade700),
          );
        },
        failure: (e) {
          setState(() => _uploading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Upload failed: $e'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.red.shade700),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Upload error: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700),
      );
    }
  }

  final List<String> _filters = [
    'ALL',
    'PDF',
    'FIGMA',
    'IMAGE',
    'SKETCH',
    'DOC'
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border)),
            child: const TextField(
              decoration: InputDecoration(
                  hintText: 'Search Files',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.textSecondary, size: 18)),
            ),
          ),
        ),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _filters.map((t) {
              final sel = _selectedFilter == t;
              return GestureDetector(
                onTap: () => setState(() => _selectedFilter = t),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: sel ? null : Border.all(color: AppColors.border),
                  ),
                  child: Center(
                      child: Text(t,
                          style: TextStyle(
                              color:
                                  sel ? Colors.white : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: _uploading ? null : _pickAndUpload,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                  color: _uploading
                      ? AppColors.primary.withValues(alpha: 0.6)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_uploading)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                  else
                    const Icon(Icons.upload_file_outlined,
                        color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(_uploading ? 'Uploading...' : 'Upload File',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RepositoryLoader<List<api.ApiFile>>(
            key: ValueKey(_fileVersion),
            load: () async {
              final pid = widget.projectId;
              if (pid == null || pid.isEmpty) {
                throw Exception('Project not loaded');
              }
              final r = await context.read<AppServices>().files.listFiles(
                    projectId: pid,
                    forceRefresh: _fileVersion > 0,
                  );
              return r.when(
                success: (list) => list,
                failure: (e) => throw Exception(e),
              );
            },
            isEmpty: (files) => files.isEmpty,
            emptyMessage: 'No files found',
            builder: (context, files) {
              final filteredFiles = _filterFiles(files);
              if (filteredFiles.isEmpty) {
                return const Center(
                  child: Text('No files found',
                      style: TextStyle(color: AppColors.textSecondary)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: filteredFiles.length,
                itemBuilder: (ctx, i) {
                  final f = filteredFiles[i];
                  final color = _getFileColor(f.name, mime: f.type);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Icon(_getFileIcon(f.name, mime: f.type),
                                    color: color, size: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(f.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppColors.textPrimary)),
                                  const SizedBox(height: 6),
                                  Text('${f.size} - Dec 18 - ${f.uploadedBy}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500)),
                                ])),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert,
                                  color: AppColors.textSecondary),
                              onSelected: (val) {
                                if (val == 'Delete') {
                                  _showDeleteConfirm(context, f.name);
                                } else {
                                  _showEditDialog(context, val, f.name);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                    value: 'Edit', child: Text('Edit')),
                                const PopupMenuItem(
                                    value: 'Rename', child: Text('Rename')),
                                const PopupMenuItem(
                                    value: 'Delete',
                                    child: Text('Delete',
                                        style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _fileActionBtn(
                              label: 'Download',
                              icon: Icons.download_rounded,
                              isPrimary: false,
                              busy: _busyFileId == f.id,
                              onTap: _busyFileId != null
                                  ? null
                                  : () => _downloadFile(context, f),
                            ),
                            const SizedBox(width: 8),
                            _fileActionBtn(
                              label: 'Share',
                              icon: Icons.share_rounded,
                              isPrimary: true,
                              busy: _busyFileId == f.id,
                              onTap: _busyFileId != null
                                  ? null
                                  : () => _shareFile(context, f),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<api.ApiFile> _filterFiles(List<api.ApiFile> files) {
    if (_selectedFilter == 'ALL') return files;
    return files.where((f) {
      final n = f.name.toLowerCase();
      final mime = f.type.toLowerCase();
      final filter = _selectedFilter.toLowerCase();
      if (filter == 'figma') {
        return n.endsWith('.fig') || n.contains('figma');
      }
      if (filter == 'image') {
        return mime.startsWith('image/') ||
            n.endsWith('.png') ||
            n.endsWith('.jpg') ||
            n.endsWith('.jpeg') ||
            n.endsWith('.webp') ||
            n.endsWith('.gif');
      }
      if (filter == 'doc') {
        return n.endsWith('.doc') ||
            n.endsWith('.docx') ||
            n.contains('doc') ||
            mime.contains('word');
      }
      if (filter == 'pdf') {
        return n.endsWith('.pdf') || mime.contains('pdf');
      }
      return n.contains(filter);
    }).toList();
  }

  void _showEditDialog(BuildContext context, String action, String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action $fileName'),
        content: TextField(
            decoration: InputDecoration(
                hintText: 'Enter new name',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Save')),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text(
            'Are you sure you want to delete "$fileName"? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
  }

  IconData _getFileIcon(String n, {String mime = ''}) {
    final m = mime.toLowerCase();
    if (m.startsWith('image/')) return Icons.image_rounded;
    if (n.endsWith('.pdf') || m.contains('pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (n.endsWith('.fig')) return Icons.auto_awesome_motion_rounded;
    if (n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.webp')) {
      return Icons.image_rounded;
    }
    if (n.endsWith('.docx') || n.endsWith('.doc')) {
      return Icons.description_rounded;
    }
    if (n.endsWith('.sketch')) return Icons.diamond_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(String n, {String mime = ''}) {
    final m = mime.toLowerCase();
    if (m.startsWith('image/') ||
        n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg')) {
      return const Color(0xFF3B82F6);
    }
    if (n.endsWith('.pdf') || m.contains('pdf')) {
      return const Color(0xFFEF4444);
    }
    if (n.endsWith('.fig')) return const Color(0xFFA855F7);
    if (n.endsWith('.docx') || n.endsWith('.doc')) {
      return const Color(0xFF2563EB);
    }
    if (n.endsWith('.sketch')) return const Color(0xFFF97316);
    return AppColors.textSecondary;
  }

  String _mimeForFile(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.doc')) return 'application/msword';
    if (n.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return 'application/octet-stream';
  }

  Future<List<int>?> _fetchFileBytes(
      BuildContext context, api.ApiFile file) async {
    setState(() => _busyFileId = file.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result =
          await context.read<AppServices>().files.downloadFile(file.id);
      if (!mounted) return null;
      return result.when(
        success: (bytes) => bytes,
        failure: (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(e),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade700,
            ),
          );
          return null;
        },
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busyFileId = null);
    }
  }

  Future<void> _downloadFile(BuildContext context, api.ApiFile file) async {
    final bytes = await _fetchFileBytes(context, file);
    if (bytes == null || bytes.isEmpty || !context.mounted) return;
    try {
      await saveDownloadedBytes(
        filename: file.name,
        bytes: Uint8List.fromList(bytes),
        mimeType: _mimeForFile(file.name),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.name} downloaded'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _shareFile(BuildContext context, api.ApiFile file) async {
    final bytes = await _fetchFileBytes(context, file);
    if (bytes == null || bytes.isEmpty || !context.mounted) return;
    final data = Uint8List.fromList(bytes);
    final mime = _mimeForFile(file.name);
    try {
      final shared = await shareDownloadedBytes(
        filename: file.name,
        bytes: data,
        mimeType: mime,
      );
      if (!context.mounted) return;
      if (shared) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sharing ${file.name}…'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await Clipboard.setData(
          ClipboardData(text: 'Teamify file: ${file.name}'));
      await saveDownloadedBytes(
        filename: file.name,
        bytes: data,
        mimeType: mime,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'File downloaded. Name copied — attach from your Downloads folder.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Share failed: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _fileActionBtn({
    required String label,
    required IconData icon,
    required bool isPrimary,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: isPrimary ? null : Border.all(color: AppColors.primary),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isPrimary ? Colors.white : AppColors.primary,
                  ),
                )
              else
                Icon(icon,
                    size: 12,
                    color: isPrimary ? Colors.white : AppColors.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? Colors.white : AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chat Tab ──────────────────────────────────────────────────────────────────
class _ChatTab extends StatefulWidget {
  final ProjectModel project;
  const _ChatTab({required this.project});

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  bool _opening = false;

  Future<void> _openChat() async {
    setState(() => _opening = true);
    try {
      await openProjectTeamChat(
        context,
        projectId: widget.project.id,
        projectName: widget.project.name,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: AppColors.primary),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('${p.progress}% progress',
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                TBar(value: p.progress / 100, height: 8),
                if (p.endDate.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('Due: ${p.endDate}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ]),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TButton(
            label: _opening ? 'Opening chat...' : 'Open Team Chat',
            onTap: _opening ? null : _openChat,
          ),
        ),
        const Expanded(
            child: Center(
                child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('Tap "Open Team Chat" to join the conversation.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ))),
      ],
    );
  }
}

// ── Analytics Tab ─────────────────────────────────────────────────────────────
class _AnalyticsTab extends StatefulWidget {
  final ProjectModel project;
  const _AnalyticsTab({required this.project});

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  bool _exporting = false;

  Future<void> _exportReport() async {
    setState(() => _exporting = true);
    final p = widget.project;

    final buffer = StringBuffer();
    buffer.writeln('Analytics Report — ${p.name}');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Status: ${p.status}');
    buffer.writeln('Progress: ${p.progress}%');
    buffer.writeln('Owner: ${p.ownerName}');
    if (p.startDate.isNotEmpty) buffer.writeln('Start: ${p.startDate}');
    if (p.endDate.isNotEmpty) buffer.writeln('End: ${p.endDate}');
    buffer.writeln('');
    buffer.writeln('Tasks (${p.tasks.length} total):');
    final done = p.tasks.where((t) => t.status == 'done').length;
    final inProg = p.tasks.where((t) => t.status == 'in_progress').length;
    buffer.writeln('  Completed: $done');
    buffer.writeln('  In Progress: $inProg');
    buffer.writeln('  To Do: ${p.tasks.length - done - inProg}');

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Report ready:\n${buffer.toString().split('\n').take(5).join('\n')}'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.primary,
      duration: const Duration(seconds: 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _chartCard('Task Completion Rate', _BarChart()),
        const SizedBox(height: 10),
        _chartCard('AI Delay Prediction', _LineChart()),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _exporting ? null : _exportReport,
          icon: const Icon(Icons.file_download_outlined,
              color: Colors.white, size: 22),
          label: const Text('Export Analytics Report',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _chartCard(String t, Widget c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.primary)),
            const SizedBox(height: 12),
            SizedBox(height: 120, child: c),
          ],
        ),
      );
}

class _BarChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
            child: CustomPaint(
                painter: _BarPainter(), child: const SizedBox.expand())),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem(AppColors.primary, 'Completed'),
            const SizedBox(width: 20),
            _legendItem(AppColors.border, 'Total'),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(Color c, String l) => Row(children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(l,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold)),
      ]);
}

class _BarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 0.5;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Y-Axis Labels & Grid
    for (int i = 0; i <= 4; i++) {
      final y = size.height - (i * (size.height / 4));
      textPainter.text = TextSpan(
          text: '${i * 5}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10));
      textPainter.layout();
      textPainter.paint(canvas, Offset(-20, y - 6));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    final data = [
      [8, 12],
      [14, 18],
      [10, 14],
      [16, 20]
    ];
    const barW = 18.0;
    final groupW = size.width / 4;

    for (int i = 0; i < 4; i++) {
      final xBase = i * groupW + (groupW / 2) - barW;
      // Primary Bar
      final h1 = (data[i][0] / 20) * size.height;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(xBase, size.height - h1, barW, h1),
              const Radius.circular(4)),
          Paint()..color = AppColors.primary);
      // Secondary Bar
      final h2 = (data[i][1] / 20) * size.height;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(xBase + barW + 4, size.height - h2, barW, h2),
              const Radius.circular(4)),
          Paint()..color = AppColors.border);

      textPainter.text = TextSpan(
          text: 'Week ${i + 1}',
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.bold));
      textPainter.layout();
      textPainter.paint(canvas, Offset(xBase - 4, size.height + 8));
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) => false;
}

class _LineChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
            child: CustomPaint(
                painter: _LinePainter(), child: const SizedBox.expand())),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem(AppColors.primary, 'Actual Progress'),
            const SizedBox(width: 20),
            _legendItem(AppColors.warning, 'Predicted Progress'),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(Color c, String l) => Row(children: [
        Container(width: 12, height: 2, color: c),
        const SizedBox(width: 6),
        Text(l,
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold)),
      ]);
}

class _LinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 0.5;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= 4; i++) {
      final y = size.height - (i * (size.height / 4));
      textPainter.text = TextSpan(
          text: '${i * 25}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10));
      textPainter.layout();
      textPainter.paint(canvas, Offset(-25, y - 6));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    final actual = [
      Offset(0, size.height * 0.7),
      Offset(size.width * 0.25, size.height * 0.6),
      Offset(size.width * 0.5, size.height * 0.55)
    ];
    final predicted = [
      Offset(0, size.height * 0.7),
      Offset(size.width * 0.25, size.height * 0.65),
      Offset(size.width * 0.5, size.height * 0.58),
      Offset(size.width * 0.75, size.height * 0.45),
      Offset(size.width, size.height * 0.3)
    ];

    final paintBlue = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final paintOrange = Paint()
      ..color = AppColors.warning
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(
        Path()
          ..moveTo(actual[0].dx, actual[0].dy)
          ..lineTo(actual[1].dx, actual[1].dy)
          ..lineTo(actual[2].dx, actual[2].dy),
        paintBlue);

    for (int i = 0; i < predicted.length - 1; i++) {
      canvas.drawLine(predicted[i], predicted[i + 1], paintOrange);
    }

    for (var p in actual) {
      canvas.drawCircle(p, 4, Paint()..color = AppColors.primary);
    }
    for (var p in predicted) {
      canvas.drawCircle(p, 4, Paint()..color = AppColors.warning);
    }

    final labels = ['Jan 5', 'Jan 8', 'Jan 10', 'Jan 12', 'Jan 15'];
    for (int i = 0; i < 5; i++) {
      textPainter.text = TextSpan(
          text: labels[i],
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.bold));
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(i * (size.width / 4) - 10, size.height + 8));
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) => false;
}

// ── Projects List Screen ──────────────────────────────────────────────────────
class ProjectsListScreen extends StatefulWidget {
  const ProjectsListScreen({super.key});
  @override
  State<ProjectsListScreen> createState() => _ProjectsListScreenState();
}

class _ProjectsListScreenState extends State<ProjectsListScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<ProjectModel> _projects = [];
  bool _loading = true;
  String? _loadError;
  bool _initialLoadDone = false;

  List<ProjectModel> get _filteredProjects {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _projects;
    return _projects.where((p) {
      final haystack = [
        p.name,
        p.company,
        p.description,
        p.ownerName,
        p.status,
        p.delayRisk,
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    _load();
  }

  Future<void> _openAddProject() async {
    try {
      final created = await Navigator.of(context).push<api.ApiProject>(
        MaterialPageRoute(
          builder: (_) => const AddProjectScreen(),
        ),
      );
      if (!mounted || created == null) return;
      await _load(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open new project: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      if (_projects.isEmpty) _loading = true;
      _loadError = null;
    });
    try {
      final result = await context.read<AppServices>().projects.listProjects(
            forceRefresh: forceRefresh,
          );
      if (!mounted) return;
      result.when(
        success: (items) {
          final projects = items.map((project) {
            final model = project.toDisplayModel();
            return model.copyWith(
              delayRisk: _estimateDelayRiskFromProjectDates(model),
            );
          }).toList();
          setState(() {
            _projects = projects;
            _loading = false;
            _loadError = null;
          });
          unawaited(_enrichDelayRisksFromAi());
        },
        failure: (e) {
          setState(() {
            _loading = false;
            _loadError = e;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _enrichDelayRisksFromAi() async {
    if (!mounted || _projects.isEmpty) return;
    final svc = context.read<AppServices>().ai;
    for (var i = 0; i < _projects.length; i++) {
      if (!mounted) return;
      final p = _projects[i];
      try {
        final result = await svc.predictDelay(projectId: p.id);
        if (!mounted) return;
        result.when(
          success: (data) {
            final risk = data['risk_level']?.toString();
            if (!_isKnownDelayRisk(risk) || !mounted) return;
            setState(() {
              if (i < _projects.length && _projects[i].id == p.id) {
                _projects[i] = _projects[i].copyWith(delayRisk: risk);
              }
            });
          },
          failure: (_) {},
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios,
                  size: 18, color: AppColors.primary),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Projects',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  fontSize: 18)),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.primary),
              tooltip: 'New project',
              onPressed: _openAddProject,
            ),
          ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search Projects...',
                    border: InputBorder.none,
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.primary, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ))),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(forceRefresh: true),
            child: _projectsBody(),
          ),
        ),
      ]),
      bottomNavigationBar:
          TBottomNav(current: 0, onTap: (i) => handleRoleNav(context, i)),
    );
  }

  Widget _projectsBody() {
    if (_loading && _projects.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_loadError != null && _projects.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => _load(forceRefresh: true),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    final visible = _filteredProjects;
    if (_projects.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 80),
            const Center(
              child: Text('No projects found',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 24),
            TButton(
              label: '+ New Project',
              onTap: _openAddProject,
            ),
            const SizedBox(height: 80),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              'No projects match "${_searchController.text.trim()}"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        ...visible.map((p) => GestureDetector(
              onTap: () => Navigator.pushNamed(
                context,
                R.projectDetails,
                arguments: p,
              ),
              child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_projectListSubtitle(p),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                              Text('${p.progress}% progress',
                                  style: const TextStyle(fontSize: 11))
                            ]),
                        const SizedBox(height: 6),
                        TBar(value: p.progress / 100),
                        const SizedBox(height: 12),
                        Row(children: [
                          const Icon(Icons.calendar_today_outlined, size: 12),
                          const SizedBox(width: 6),
                          Text(_projectListDateLabel(p),
                              style: const TextStyle(fontSize: 11)),
                          const Spacer(),
                          TChip(
                              label: _delayRiskDisplayLabel(p.delayRisk),
                              bg: _delayRiskBg(p.delayRisk),
                              textColor: _delayRiskText(p.delayRisk))
                        ]),
                      ])),
            )),
        const SizedBox(height: 20),
        TButton(
          label: '+ New Project',
          onTap: _openAddProject,
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}

// ── Add Task Screen ──────────────────────────────────────────────────────────
class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  String _selectedStatus = 'To Do';
  String _selectedPriority = 'Medium';
  DateTime? _dueDate;
  String _dueLabel = 'Select date';

  bool _isLoading = false;
  String? _error;

  List<api.ApiProject> _projectChoices = [];
  bool _projectsLoading = false;
  String? _projectsError;
  String? _selectedProjectId;

  List<api.ApiUser> _projectMembers = [];
  bool _membersLoading = false;
  String? _membersError;

  /// null = unassigned
  String? _selectedAssigneeId;

  final Map<String, Color> _statusColors = {
    'To Do': Colors.blue,
    'In Progress': Colors.orange,
    'Review': Colors.purple,
    'Completed': Colors.green,
    'Blocked': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapProjects());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  String? get _activeProjectId =>
      _selectedProjectId ??
      _routeProjectIdForTask(ModalRoute.of(context)?.settings.arguments);

  String get _currentUserId =>
      context.read<SessionController>().currentUser?.id ?? '';

  bool _isProjectOwner(String? projectId) {
    if (projectId == null || projectId.isEmpty) return false;
    final uid = _currentUserId;
    if (uid.isEmpty) return false;
    for (final p in _projectChoices) {
      if (p.id == projectId) return p.ownerId == uid;
    }
    return false;
  }

  bool get _canAssignMembers => _isProjectOwner(_activeProjectId);

  List<api.ApiProject> _ownedProjects(List<api.ApiProject> projects) {
    final uid = _currentUserId;
    if (uid.isEmpty) return [];
    return projects.where((p) => p.ownerId == uid).toList();
  }

  api.ApiUser? get _selectedAssignee {
    if (_selectedAssigneeId == null || _selectedAssigneeId!.isEmpty) {
      return null;
    }
    for (final u in _projectMembers) {
      if (u.id == _selectedAssigneeId) return u;
    }
    return null;
  }

  String _assigneeFieldLabel() {
    final u = _selectedAssignee;
    if (u == null) return 'Unassigned';
    final role = u.projectRoleLabel;
    return role.isNotEmpty ? '${u.primaryName} ($role)' : u.primaryName;
  }

  Future<void> _showAssigneePicker(BuildContext context) async {
    if (_projectMembers.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        builder: (_, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                'Assign to',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: const Text('Unassigned'),
                    onTap: () {
                      setState(() => _selectedAssigneeId = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  const Divider(height: 1),
                  ..._projectMembers.map(
                    (u) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      title: ProjectMemberDetailTile(user: u),
                      onTap: () {
                        setState(() => _selectedAssigneeId = u.id);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadProjectMembers(String projectId) async {
    if (!_isProjectOwner(projectId)) {
      setState(() {
        _membersLoading = false;
        _membersError = null;
        _projectMembers = [];
        _selectedAssigneeId = null;
      });
      return;
    }
    setState(() {
      _membersLoading = true;
      _membersError = null;
      _projectMembers = [];
      _selectedAssigneeId = null;
    });
    final result =
        await context.read<AppServices>().projects.listMembers(projectId);
    if (!mounted) return;
    result.when(
      success: (users) => setState(() {
        _projectMembers = users;
        _membersLoading = false;
      }),
      failure: (e) => setState(() {
        _membersError = e;
        _membersLoading = false;
      }),
    );
  }

  void _onProjectSelected(String? projectId) {
    setState(() {
      _selectedProjectId = projectId;
      _selectedAssigneeId = null;
      _projectMembers = [];
    });
    if (projectId != null && projectId.isNotEmpty) {
      _loadProjectMembers(projectId);
    }
  }

  Future<void> _bootstrapProjects() async {
    final routeId =
        _routeProjectIdForTask(ModalRoute.of(context)?.settings.arguments);
    if (routeId != null && routeId.isNotEmpty) {
      setState(() {
        _projectsLoading = true;
        _projectsError = null;
      });
      final result =
          await context.read<AppServices>().projects.getProject(routeId);
      if (!mounted) return;
      await result.when(
        success: (project) async {
          if (!AppConfig.isDemoMode && project.ownerId != _currentUserId) {
            setState(() {
              _projectsLoading = false;
              _projectsError =
                  'Only the project owner can add tasks and assign members.';
              _projectChoices = [];
              _selectedProjectId = null;
            });
            return;
          }
          setState(() {
            _projectChoices = [project];
            _selectedProjectId = routeId;
            _projectsLoading = false;
          });
          await _loadProjectMembers(routeId);
        },
        failure: (e) {
          setState(() {
            _projectsLoading = false;
            _projectsError = e;
          });
        },
      );
      return;
    }
    setState(() {
      _projectsLoading = true;
      _projectsError = null;
    });
    try {
      final result = await context.read<AppServices>().projects.listProjects();
      if (!mounted) return;
      result.when(
        success: (list) {
          final owned = _ownedProjects(list);
          final defaultId = owned.isNotEmpty ? owned.first.id : null;
          setState(() {
            _projectChoices = owned;
            _projectsLoading = false;
            _selectedProjectId ??= defaultId;
          });
          if (defaultId != null) {
            _loadProjectMembers(defaultId);
          }
        },
        failure: (e) {
          setState(() {
            _projectsLoading = false;
            _projectsError = e;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _projectsLoading = false;
        _projectsError = e.toString();
      });
    }
  }

  Future<void> _openAiSuggest() async {
    final projectId = _activeProjectId;
    if (projectId == null || projectId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a project before using AI suggestions.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final result = await Navigator.pushNamed(
      context,
      R.aiPriority,
      arguments: {
        'project_id': projectId,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
      },
    );
    if (!mounted || result == null) return;
    if (result is Map) {
      final priority = result['priority']?.toString();
      if (priority != null && priority.isNotEmpty) {
        setState(() => _selectedPriority = _priorityLabelFromApi(priority));
      }
      final date = result['date'];
      if (date is DateTime) {
        setState(() {
          _dueDate = date;
          _dueLabel = '${date.day}/${date.month}/${date.year}';
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final projectId = _selectedProjectId ??
        _routeProjectIdForTask(ModalRoute.of(context)?.settings.arguments);
    if (projectId == null || projectId.isEmpty) {
      setState(() => _error = 'Select a valid project.');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please select a project.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!AppConfig.isDemoMode && !_isProjectOwner(projectId)) {
      setState(() => _error = 'Only the project owner can add tasks.');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Only the project owner can add tasks.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'project_id': int.tryParse(projectId) ?? projectId,
        'description': _descController.text.trim(),
        'status': _apiTaskStatusFromUi(_selectedStatus),
        'priority': _priorityApi(_selectedPriority),
      };
      if (_dueDate != null) {
        payload['due_date'] = _isoDate(_dueDate!);
      }
      if (_canAssignMembers &&
          _selectedAssigneeId != null &&
          _selectedAssigneeId!.isNotEmpty) {
        final aid = int.tryParse(_selectedAssigneeId!);
        if (aid != null) payload['assigned_to'] = aid;
      }

      final result =
          await context.read<AppServices>().tasks.createTask(payload);
      if (!mounted) return;

      if (result.isOfflineQueued) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('You\'re offline — task will sync when connected.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
        return;
      }

      result.when(
        success: (task) {
          setState(() => _isLoading = false);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Task created successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop(task);
        },
        failure: (e) {
          setState(() {
            _isLoading = false;
            _error = e;
          });
          messenger.showSnackBar(
            SnackBar(
              content: Text(e),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade700,
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final routePid =
        _routeProjectIdForTask(ModalRoute.of(context)?.settings.arguments);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              size: 18, color: AppColors.primary),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: const Text('Add Task',
            style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_projectsLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (_projectsError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_projectsError!,
                        style: TextStyle(
                            color: Colors.red.shade700, fontSize: 13)),
                  ),
                if (routePid == null) ...[
                  _label('Project'),
                  if (!_projectsLoading &&
                      _projectChoices.isEmpty &&
                      _projectsError == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'No projects you own. Create a project to add tasks.',
                        style:
                            TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  if (!_projectsLoading && _projectChoices.isNotEmpty)
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _selectedProjectId,
                      decoration: _outlineDecoration(),
                      items: _projectChoices
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: _isLoading ? null : _onProjectSelected,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Pick a project' : null,
                    ),
                  const SizedBox(height: 16),
                ],
                _label('Task Title'),
                TextFormField(
                  controller: _titleController,
                  decoration: _outlineDecoration(hint: 'Enter task title'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Title is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_canAssignMembers) ...[
                  _label('Assignee (optional)'),
                  if (_activeProjectId == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Select a project to choose a team member.',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                    )
                  else if (_membersLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (_membersError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _membersError!,
                              style: TextStyle(
                                  color: Colors.red.shade700, fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => _loadProjectMembers(_activeProjectId!),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (_projectMembers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'No members on this project yet.',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                    )
                  else ...[
                    GestureDetector(
                      onTap: _isLoading
                          ? null
                          : () => _showAssigneePicker(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 20, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _selectedAssignee == null
                                  ? Text(
                                      _assigneeFieldLabel(),
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    )
                                  : ProjectMemberDetailTile(
                                      user: _selectedAssignee!,
                                      showSkills: false,
                                    ),
                            ),
                            Icon(Icons.arrow_drop_down,
                                color: Colors.grey.shade600),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ] else if (_activeProjectId != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Only the project owner can assign team members.',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ),
                ],
                _label('Due Date'),
                GestureDetector(
                  onTap: _isLoading ? null : () => _showDateOptions(context),
                  child: _dropField(_dueLabel, Icons.calendar_month),
                ),
                const SizedBox(height: 16),
                _label('Status'),
                GestureDetector(
                  onTap: _isLoading ? null : () => _showStatusOptions(context),
                  child: _statusDrop(),
                ),
                const SizedBox(height: 16),
                _label('Priority'),
                GestureDetector(
                  onTap: _isLoading
                      ? null
                      : () => _showOptions(
                          context,
                          'Priority',
                          ['Low', 'Medium', 'High'],
                          (val) => setState(() => _selectedPriority = val)),
                  child: _priorityDrop(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _openAiSuggest,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('AI Suggest priority & deadline'),
                  ),
                ),
                const SizedBox(height: 8),
                _label('Description'),
                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: _outlineDecoration(hint: 'Describe the task'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style:
                          TextStyle(color: Colors.red.shade700, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                TButton(
                  label: _isLoading ? 'Creating…' : 'Create Task',
                  onTap: _isLoading ? null : _submit,
                ),
                const SizedBox(height: 12),
                TButton(
                  label: 'Cancel',
                  outline: true,
                  onTap: _isLoading ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _outlineDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15)),
      );

  void _showOptions(BuildContext context, String title, List<String> options,
      void Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 16),
            ...options.map((o) => ListTile(
                  title: Text(o),
                  onTap: () {
                    onSelect(o);
                    Navigator.pop(ctx);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showStatusOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Status',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 20),
            ..._statusColors.keys.map((status) {
              final sel = _selectedStatus == status;
              return ListTile(
                leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: _statusColors[status], shape: BoxShape.circle)),
                title: Text(status,
                    style: TextStyle(
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        color:
                            sel ? AppColors.primary : AppColors.textPrimary)),
                trailing: sel
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedStatus = status);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showDateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Due Date',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 20),
            _dateOption(ctx, 'Today', DateTime.now()),
            _dateOption(
                ctx, 'Tomorrow', DateTime.now().add(const Duration(days: 1))),
            _dateOption(
                ctx, 'Next Week', DateTime.now().add(const Duration(days: 7))),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined,
                  color: AppColors.primary),
              title: const Text('Pick Custom Date'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() {
                    _dueDate = picked;
                    _dueLabel = '${picked.day}/${picked.month}/${picked.year}';
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateOption(BuildContext ctx, String label, DateTime date) => ListTile(
        leading: const Icon(Icons.calendar_today_outlined,
            color: AppColors.primary, size: 20),
        title: Text(label),
        subtitle: Text('${date.day}/${date.month}/${date.year}'),
        onTap: () {
          setState(() {
            _dueDate = date;
            _dueLabel = '${date.day}/${date.month}/${date.year}';
          });
          Navigator.pop(ctx);
        },
      );

  Widget _dropField(String h, IconData? i) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            if (i != null) ...[
              Icon(i, size: 18, color: AppColors.primary),
              const SizedBox(width: 10)
            ],
            Expanded(
              child: Text(h,
                  style: TextStyle(
                      color: h.contains('/')
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                      fontWeight: h.contains('/')
                          ? FontWeight.w500
                          : FontWeight.normal)),
            ),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.primary),
          ],
        ),
      );

  Widget _statusDrop() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: _statusColors[_selectedStatus],
                    shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Text(_selectedStatus,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
            const Spacer(),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.primary),
          ],
        ),
      );

  Widget _priorityDrop() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            TChip(
                label: _selectedPriority,
                bg: _selectedPriority == 'High'
                    ? Colors.red
                    : (_selectedPriority == 'Medium'
                        ? AppColors.warning
                        : Colors.blue),
                textColor: Colors.white),
            const Spacer(),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.primary),
          ],
        ),
      );
}

// ── Edit Project Sheet ────────────────────────────────────────────────────────
class _EditProjectSheet extends StatefulWidget {
  final ProjectModel project;
  const _EditProjectSheet({required this.project});

  @override
  State<_EditProjectSheet> createState() => _EditProjectSheetState();
}

class _EditProjectSheetState extends State<_EditProjectSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;

  late String _statusApi;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _nameController = TextEditingController(text: p.name);
    _descriptionController =
        TextEditingController(text: _cleanProjectDescription(p.description));
    _categoryController = TextEditingController(
      text: p.company == 'Teamify' ? '' : p.company,
    );
    _statusApi = const {'planned', 'active', 'on_hold', 'completed'}
            .contains(p.status.toLowerCase())
        ? p.status.toLowerCase()
        : 'active';
    _startDate = _dateFromDisplay(p.startDate);
    _endDate = _dateFromDisplay(p.endDate);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  InputDecoration _decor({String? hint}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textPrimary)),
      );

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      setState(() => _error = 'End date must be after start date');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'name': _nameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'category': _categoryController.text.trim(),
      'status': _statusApi,
      'start_date': _startDate != null ? _isoDate(_startDate!) : '',
      'end_date': _endDate != null ? _isoDate(_endDate!) : '',
    };

    final result = await context
        .read<AppServices>()
        .projects
        .updateProject(widget.project.id, payload);
    if (!mounted) return;

    result.when(
      success: (project) => Navigator.pop(context, project),
      failure: (err) => setState(() {
        _saving = false;
        _error = err;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Edit project',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      _fieldLabel('Project name *'),
                      TextFormField(
                        controller: _nameController,
                        maxLength: 150,
                        decoration: _decor(hint: 'Project title'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Category / label'),
                      TextFormField(
                        controller: _categoryController,
                        maxLength: 100,
                        decoration: _decor(hint: 'e.g. Mobile, Research'),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Description'),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        maxLength: 5000,
                        decoration: _decor(hint: 'Goals, scope, notes…'),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Status'),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _statusApi,
                        decoration: _decor(),
                        items: const [
                          DropdownMenuItem(
                              value: 'planned', child: Text('Planned')),
                          DropdownMenuItem(
                              value: 'active', child: Text('Active')),
                          DropdownMenuItem(
                              value: 'on_hold', child: Text('On hold')),
                          DropdownMenuItem(
                              value: 'completed', child: Text('Completed')),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _statusApi = v ?? 'active'),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Duration'),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _pickDate(isStart: true),
                              icon: const Icon(Icons.calendar_today_outlined,
                                  size: 16),
                              label: Text(
                                _displayDateLabel(_startDate),
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 12),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('–',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                          ),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _pickDate(isStart: false),
                              icon: const Icon(Icons.event_outlined, size: 16),
                              label: Text(
                                _displayDateLabel(_endDate),
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: Color(0xFFDC2626), fontSize: 13)),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Save changes',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Add Project Screen ────────────────────────────────────────────────────────
class AddProjectScreen extends StatefulWidget {
  const AddProjectScreen({super.key});
  @override
  State<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends State<AddProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _memberSearchController = TextEditingController();

  String _statusApi = 'active';
  DateTime? _startDate;
  DateTime? _endDate;
  String _startLabel = 'Start date (optional)';
  String _endLabel = 'Target / due date (optional)';
  bool _teamVisible = true;

  bool _isLoading = false;
  String? _error;

  // ── Member selection ──────────────────────────────────────────────────────
  List<api.ApiUser> _allMembers = [];
  final Set<String> _selectedMemberIds = {};
  bool _membersLoading = false;
  String? _membersError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    if (!mounted) return;
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    final result =
        await context.read<AppServices>().projects.getAvailableMembers();
    if (!mounted) return;
    result.when(
      success: (members) => setState(() {
        _allMembers = members.where((m) => !m.isAdmin).toList();
        _membersLoading = false;
      }),
      failure: (e) => setState(() {
        _membersError = e;
        _membersLoading = false;
      }),
    );
  }

  void _toggleMember(String id) => setState(() {
        if (_selectedMemberIds.contains(id)) {
          _selectedMemberIds.remove(id);
        } else {
          _selectedMemberIds.add(id);
        }
      });

  Future<void> _openMemberPicker(BuildContext outerCtx) async {
    _memberSearchController.clear();
    await showDialog<void>(
      context: outerCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final q = _memberSearchController.text.trim().toLowerCase();
          final visible =
              _allMembers.where((m) => _matchesMemberSearch(m, q)).toList();

          return AlertDialog(
            title: const Text('Invite team members'),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SizedBox(
              width: double.maxFinite,
              height: 520,
              child: Column(children: [
                TextField(
                  controller: _memberSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search name, email, skills, field…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _memberSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _memberSearchController.clear();
                              setDialog(() {});
                            })
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => setDialog(() {}),
                ),
                const SizedBox(height: 8),
                if (_membersLoading)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (visible.isEmpty)
                  const Expanded(child: Center(child: Text('No users found')))
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final m = visible[i];
                        final selected = _selectedMemberIds.contains(m.id);
                        return _inviteMemberPickerRow(
                          user: m,
                          selected: selected,
                          sending: false,
                          onChanged: (_) {
                            setDialog(() => _toggleMember(m.id));
                          },
                        );
                      },
                    ),
                  ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done')),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildSelectedChips() {
    if (_selectedMemberIds.isEmpty) return const SizedBox.shrink();
    final selected =
        _allMembers.where((m) => _selectedMemberIds.contains(m.id)).toList();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: selected
          .map((m) => Chip(
                avatar: CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    m.initials,
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                ),
                label:
                    Text(m.primaryName, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => _toggleMember(m.id),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ))
          .toList(),
    );
  }

  String _composeDescription() {
    final base = _descriptionController.text.trim();
    final vis = _teamVisible ? 'Team' : 'Private';
    final buf = StringBuffer();
    buf.writeln('[Visibility: $vis]');
    buf.write(base);
    return buf.toString().trim();
  }

  Future<void> _pickStart(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _startDate = d;
        _startLabel = _isoDate(d);
      });
    }
  }

  Future<void> _pickEnd(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _endDate = d;
        _endLabel = _isoDate(d);
      });
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _composeDescription(),
        'status': _statusApi,
        'category': _categoryController.text.trim(),
        if (_selectedMemberIds.isNotEmpty)
          'member_ids':
              _selectedMemberIds.map((id) => int.tryParse(id) ?? id).toList(),
      };
      if (_startDate != null) payload['start_date'] = _isoDate(_startDate!);
      if (_endDate != null) payload['end_date'] = _isoDate(_endDate!);

      final result =
          await context.read<AppServices>().projects.createProject(payload);
      if (!mounted) return;

      result.when(
        success: (project) {
          setState(() => _isLoading = false);
          messenger.showSnackBar(
            SnackBar(
              content: Text(_selectedMemberIds.isEmpty
                  ? 'Project created'
                  : 'Project created — ${_selectedMemberIds.length} invitation(s) sent'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop(project);
        },
        failure: (e) {
          setState(() {
            _isLoading = false;
            _error = e;
          });
          messenger.showSnackBar(
            SnackBar(
              content: Text(e),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade700,
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios,
                  size: 18, color: AppColors.primary),
              onPressed: _isLoading ? null : () => Navigator.pop(context)),
          title: const Text('Add New Project',
              style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          centerTitle: true),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 4),
              _fieldLabel('Project title *'),
              TextFormField(
                controller: _nameController,
                decoration: _decor(hint: 'e.g. Website redesign'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _fieldLabel('Description'),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: _decor(hint: 'Goals, scope, notes…'),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Category / label (optional)'),
              TextFormField(
                controller: _categoryController,
                decoration: _decor(hint: 'e.g. Mobile, Research'),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Status'),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _statusApi,
                decoration: _decor(),
                items: const [
                  DropdownMenuItem(value: 'planned', child: Text('Planned')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'on_hold', child: Text('On hold')),
                  DropdownMenuItem(
                      value: 'completed', child: Text('Completed')),
                ],
                onChanged: _isLoading
                    ? null
                    : (v) => setState(() => _statusApi = v ?? 'active'),
              ),
              const SizedBox(height: 16),

              // ── Team Members ─────────────────────────────────────────
              _fieldLabel('Team Members (optional)'),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _isLoading || _membersLoading
                    ? null
                    : () => _openMemberPicker(context),
                icon: _membersLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.group_add_outlined, size: 18),
                label: Text(
                  _selectedMemberIds.isEmpty
                      ? 'Invite members (they must accept)'
                      : '${_selectedMemberIds.length} invitation(s) to send',
                  style: const TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (_membersError != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Could not load members — you can add them after creation.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade700),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 8),
              _buildSelectedChips(),
              // ─────────────────────────────────────────────────────────

              const SizedBox(height: 16),
              _fieldLabel('Visibility'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Team-visible notes'),
                subtitle:
                    const Text('Stored in description until API adds a flag.'),
                value: _teamVisible,
                onChanged:
                    _isLoading ? null : (v) => setState(() => _teamVisible = v),
              ),
              const SizedBox(height: 8),
              _fieldLabel('Dates'),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _pickStart(context),
                    child:
                        Text(_startLabel, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _pickEnd(context),
                    child:
                        Text(_endLabel, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              TButton(
                label: _isLoading ? 'Creating…' : 'Create Project',
                onTap: _isLoading ? null : _submit,
              ),
              const SizedBox(height: 12),
              TButton(
                label: 'Cancel',
                outline: true,
                onTap: _isLoading ? null : () => Navigator.pop(context),
              ),
            ]),
          )),
    );
  }

  Widget _fieldLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );

  InputDecoration _decor({String? hint}) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
