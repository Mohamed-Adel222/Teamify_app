import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../data/models/models.dart' as api;
import '../../services/app_services.dart';
import '../../core/network/api_result.dart';
import '../../models/models.dart';
import '../../widgets/widgets.dart';
import '../../core/course_link.dart';
import '../mentor/mentor_skill_ui.dart';
import '../../services/ai_service.dart';

Future<List<Map<String, dynamic>>> _fetchTeammateRecommendationMaps(
    BuildContext context) async {
  final services = context.read<AppServices>();
  final user = context.read<SessionController>().currentUser;
  final result = await services.ai.recommendTeammates(
    {
      'user_id': user?.id,
      'skills': user?.skills ?? const <String>[],
    },
    topN: 8,
  ).unwrap();
  final raw = result['recommendations'] ??
      result['teammates'] ??
      result['users'] ??
      result['data'];
  if (raw is List && raw.isNotEmpty) {
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  return const [];
}

int _matchPercentFromMap(Map<String, dynamic> map) {
  final matchPercent = map['match_percent'];
  if (matchPercent is num) {
    return matchPercent.round().clamp(0, 100);
  }
  final similarity = (map['similarity_score'] as num?)?.toDouble() ?? 0;
  return (similarity * 100).round().clamp(0, 100);
}

int _courseMatchPercent(Map<String, dynamic> course) {
  final matchPercent = course['match_percent'];
  if (matchPercent is num) {
    return matchPercent.round().clamp(0, 100);
  }
  final match = course['match'];
  if (match is num) {
    return match.round().clamp(0, 100);
  }
  final relevance = course['relevance'];
  if (relevance is num) {
    return (relevance * 100).round().clamp(0, 100);
  }
  return 0;
}

String _courseStatusLine(Map<String, dynamic> course) {
  final match = _courseMatchPercent(course);
  final progress = course['progress'];
  if (progress is num && progress > 0) {
    return '${progress.round()}% complete • $match% match';
  }
  final fills = course['fills'];
  if (fills is List && fills.isNotEmpty) {
    return 'Closes gap: ${fills.take(3).join(', ')} • $match% match';
  }
  final duration = course['duration'] ?? course['hours'];
  if (duration != null && duration.toString().isNotEmpty) {
    return '${duration.toString()} • $match% match';
  }
  return '$match% skill match';
}

Future<List<({UserModel user, Map<String, dynamic> raw})>>
    _fetchTeammateRecommendationItems(BuildContext context) async {
  final maps = await _fetchTeammateRecommendationMaps(context);
  return maps
      .map((item) => (
            user: api.ApiUser.fromJson(item).toDisplayModel(),
            raw: item,
          ))
      .toList();
}

Future<List<Map<String, dynamic>>> _fetchRecommendedCourses(
    BuildContext context) async {
  final userId = context.read<SessionController>().currentUser?.id ?? '';
  if (userId.isEmpty) return const [];
  final result =
      await context.read<AppServices>().ai.mentorCourses(userId).unwrap();
  final raw = result['courses'] ??
      result['recommended_courses'] ??
      result['items'] ??
      result['data'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

// ── AI Hub ────────────────────────────────────────────────────────────────────
class AIHubScreen extends StatelessWidget {
  const AIHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> tools = [
      {
        'icon': Icons.checklist_rounded,
        'title': 'Smart To-Do',
        'sub': 'AI-prioritized tasks',
        'route': R.smartTodo,
        'color': AppColors.primary
      },
      {
        'icon': Icons.people_outline,
        'title': 'Team Recommendation',
        'sub': 'Best fit matching',
        'route': R.teamRecommendation,
        'color': AppColors.accent
      },
      {
        'icon': Icons.auto_awesome,
        'title': 'Task Allocation',
        'sub': 'AI assignment',
        'route': R.aiTaskAllocation,
        'color': const Color(0xFF6366F1)
      },
      {
        'icon': Icons.psychology_outlined,
        'title': 'AI Career Mentor',
        'sub': 'Mentor, courses & feedback',
        'route': R.mentorMain,
        'color': AppColors.success
      },
      {
        'icon': Icons.rate_review_outlined,
        'title': 'Peer Feedback',
        'sub': 'Rate your teammates',
        'route': R.mentorMain,
        'tab': 4,
        'color': const Color(0xFF0EA5E9)
      },
      {
        'icon': Icons.trending_up,
        'title': 'AI Insights',
        'sub': 'Performance analysis',
        'route': R.aiInsights,
        'color': AppColors.warning
      },
      {
        'icon': Icons.timer_outlined,
        'title': 'Pomodoro',
        'sub': 'Focus timer',
        'route': R.pomodoro,
        'color': Colors.red
      },
      {
        'icon': Icons.bar_chart,
        'title': 'Skills',
        'sub': 'AI skill mapping',
        'route': R.skills,
        'color': Colors.teal
      },
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('AI Hub',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const Text('Your AI-powered workspace',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            AIBanner(
                title: 'AI is ready',
                subtitle: 'All systems operational. 3 insights available.',
                onTap: () => Navigator.pushNamed(context, R.aiInsights)),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount =
                    width >= 900 ? 3 : (width >= 520 ? 2 : 1);
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: crossAxisCount == 1 ? 2.4 : 1.3,
                  children: tools
                      .map((t) => GestureDetector(
                            onTap: () {
                              final route = t['route'] as String;
                              final tab = t['tab'] as int?;
                              if (tab != null) {
                                Navigator.pushNamed(context, route,
                                    arguments: {'tab': tab});
                              } else {
                                Navigator.pushNamed(context, route);
                              }
                            },
                            child: TCard(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                            color: (t['color'] as Color)
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Icon(t['icon'] as IconData,
                                            color: t['color'] as Color,
                                            size: 22)),
                                    const SizedBox(height: 8),
                                    Text(t['title'] as String,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                            fontSize: 13)),
                                    Text(t['sub'] as String,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary)),
                                  ]),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          TBottomNav(current: 2, onTap: (i) => handleRoleNav(context, i)),
    );
  }
}

// ── Smart Todo ────────────────────────────────────────────────────────────────
class SmartTodoScreen extends StatefulWidget {
  const SmartTodoScreen({super.key});
  @override
  State<SmartTodoScreen> createState() => _SmartTodoScreenState();
}

class _SmartTodoScreenState extends State<SmartTodoScreen> {
  bool _loading = true;
  String? _error;
  final List<Map<String, dynamic>> _todos = [];
  final Set<String> _done = {};

  static const _priorityOrder = {
    'critical': 0,
    'high': 1,
    'medium': 2,
    'low': 3
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<AppServices>();
      final accessible = await svc.tasks.listAccessibleTasks(limit: 100);
      final rows = accessible.when(
        success: (list) => list,
        failure: (_) => <Map<String, dynamic>>[],
      );
      final todos = rows
          .map((t) => {
                'id': t['id']?.toString() ?? '',
                'title': t['title']?.toString() ?? 'Task',
                'priority':
                    (t['priority']?.toString() ?? 'medium').toLowerCase(),
                'project': t['project_name']?.toString() ?? 'Project',
                'status': t['status']?.toString() ?? 'pending',
              })
          .where((t) => (t['id']?.toString() ?? '').isNotEmpty)
          .toList();
      todos.sort((a, b) => (_priorityOrder[a['priority']] ?? 3)
          .compareTo(_priorityOrder[b['priority']] ?? 3));
      if (!mounted) return;
      setState(() {
        _todos.clear();
        _todos.addAll(todos);
        _done
          ..clear()
          ..addAll(
            todos
                .where((t) => t['status']?.toString().toLowerCase() == 'done')
                .map((t) => t['id'].toString()),
          );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Color _priorityBg(String p) {
    switch (p) {
      case 'critical':
        return AppColors.error.withValues(alpha: 0.12);
      case 'high':
        return AppColors.error.withValues(alpha: 0.1);
      case 'medium':
        return AppColors.warning.withValues(alpha: 0.1);
      default:
        return AppColors.border;
    }
  }

  Color _priorityFg(String p) {
    switch (p) {
      case 'critical':
      case 'high':
        return AppColors.error;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Smart To-Do',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loading ? null : _load)
          ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                  TButton(label: 'Retry', onTap: _load),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _todos.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: AIBanner(
                              title: 'AI Prioritization',
                              subtitle: 'Tasks sorted by impact and urgency'));
                    }
                    final t = _todos[i - 1];
                    final id = t['id'].toString();
                    final done = _done.contains(id);
                    final priority = (t['priority'] as String?) ?? 'medium';
                    return TCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        GestureDetector(
                          onTap: () async {
                            final newDone = !done;
                            setState(() {
                              if (newDone) {
                                _done.add(id);
                              } else {
                                _done.remove(id);
                              }
                            });
                            await context
                                .read<AppServices>()
                                .tasks
                                .updateStatus(
                                  id,
                                  newDone ? 'done' : 'in_progress',
                                );
                          },
                          child: Icon(
                              done
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color:
                                  done ? AppColors.success : AppColors.border,
                              size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(t['title'] as String,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: done
                                          ? AppColors.textSecondary
                                          : AppColors.textPrimary,
                                      decoration: done
                                          ? TextDecoration.lineThrough
                                          : null,
                                      fontSize: 13)),
                              Text(t['project'] as String,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                            ])),
                        TChip(
                            label: priority[0].toUpperCase() +
                                priority.substring(1),
                            bg: _priorityBg(priority),
                            textColor: _priorityFg(priority)),
                      ]),
                    );
                  },
                ),
    );
  }
}

// ── AI Task Allocation ────────────────────────────────────────────────────────
class AITaskAllocationScreen extends StatefulWidget {
  const AITaskAllocationScreen({super.key});
  @override
  State<AITaskAllocationScreen> createState() => _AITaskAllocationScreenState();
}

class _AITaskAllocationScreenState extends State<AITaskAllocationScreen> {
  bool _loadingTasks = true;
  bool _classifying = false;
  String? _error;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _tasks = [];
  String? _selectedTaskId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTasks());
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loadingTasks = true;
      _error = null;
    });
    try {
      final services = context.read<AppServices>();
      final rows =
          await services.tasks.listAccessibleTasks(limit: 100).unwrap();
      final tasks = rows
          .map((t) => <String, dynamic>{
                'id': t['id']?.toString(),
                'title': t['title']?.toString() ?? '',
                'project_name': t['project_name']?.toString() ?? 'Project',
              })
          .where((t) =>
              t['id'] != null && (t['title']?.toString() ?? '').isNotEmpty)
          .toList();
      if (!mounted) return;
      final firstId = tasks.isNotEmpty ? tasks.first['id']?.toString() : null;
      setState(() {
        _tasks = tasks;
        _selectedTaskId = firstId;
        _loadingTasks = false;
      });
      if (firstId != null) {
        _classify(_taskTextForId(firstId));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loadingTasks = false;
      });
    }
  }

  String _taskTextForId(String id) {
    for (final t in _tasks) {
      if (t['id']?.toString() == id) {
        return t['title']?.toString() ?? '';
      }
    }
    return '';
  }

  Future<void> _classify(String taskText) async {
    if (taskText.trim().isEmpty) return;
    setState(() {
      _classifying = true;
      _error = null;
    });
    final svc = context.read<AppServices>();
    final result = await svc.ai.classifyTask(taskText);
    if (!mounted) return;
    result.when(
      success: (data) {
        setState(() {
          _data = data;
          _classifying = false;
          _error = null;
        });
      },
      failure: (msg) {
        setState(() {
          _classifying = false;
          final code = result.statusCode;
          _error = code != null
              ? 'Error $code: $msg'
              : (msg.isNotEmpty ? msg : 'Classification failed');
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('AI Task Allocation',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: _loadingTasks
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ?? 'No tasks found in your projects.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _error != null
                            ? AppColors.error
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(_selectedTaskId),
                    initialValue: _selectedTaskId,
                    decoration: const InputDecoration(
                      labelText: 'Select a task',
                      border: OutlineInputBorder(),
                    ),
                    items: _tasks
                        .map((t) => DropdownMenuItem<String>(
                              value: t['id']?.toString(),
                              child: Text(
                                '${t['project_name']}: ${t['title']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() {
                        _selectedTaskId = id;
                        _data = null;
                      });
                      _classify(_taskTextForId(id));
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_classifying)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Running AI classifier…',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_error != null && _data == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.error)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _selectedTaskId == null
                                ? null
                                : () =>
                                    _classify(_taskTextForId(_selectedTaskId!)),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (_data != null) ...[
                    const AIBanner(
                        title: 'AI Allocation Engine',
                        subtitle: 'Matching tasks to the best team members'),
                    const SizedBox(height: 16),
                    TCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Model Details',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  fontSize: 16)),
                          const SizedBox(height: 12),
                          _row('Category',
                              _data?['category']?.toString() ?? 'N/A'),
                          _row('Complexity',
                              _data?['complexity']?.toString() ?? 'N/A'),
                          _row('Confidence',
                              '${((_data?['confidence'] as num?)?.toDouble() ?? 0) * 100}%'),
                        ])),
                    const SizedBox(height: 12),
                    TCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Recommended Assignment',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(children: [
                            const TAvatar(initials: 'AI', radius: 28),
                            const SizedBox(width: 14),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      _data?['suggested_assignee']
                                              ?.toString() ??
                                          'Auto Assigned',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary)),
                                  const Text('Best match for this task',
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13)),
                                ])),
                            TChip(
                                label: 'Optimal',
                                bg: AppColors.success.withValues(alpha: 0.1),
                                textColor: AppColors.success,
                                fontSize: 12),
                          ]),
                        ])),
                    const SizedBox(height: 16),
                    TButton(
                        label: 'View Full Result',
                        onTap: () =>
                            Navigator.pushNamed(context, R.aiSuggestedResult)),
                  ],
                ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
              width: 110,
              child: Text(k,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 13))),
        ]),
      );
}

// ── Suggested Result ──────────────────────────────────────────────────────────
class AISuggestedResultScreen extends StatelessWidget {
  const AISuggestedResultScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('AI Result',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body:
          RepositoryLoader<List<({UserModel user, Map<String, dynamic> raw})>>(
        load: () => _fetchTeammateRecommendationItems(context),
        isEmpty: (items) => items.isEmpty,
        emptyMessage: 'No suggested teammates found',
        builder: (context, items) =>
            ListView(padding: const EdgeInsets.all(16), children: [
          ...items.take(3).map((item) {
            final u = item.user;
            final pct = _matchPercentFromMap(item.raw);
            return TCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  TAvatar(initials: u.initials, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(u.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                        Text(u.role,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        TBar(value: pct / 100, color: AppColors.primary),
                      ])),
                  const SizedBox(width: 12),
                  Column(children: [
                    Text('$pct%',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 16)),
                    const Text('match',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                ]));
          }),
          const SizedBox(height: 8),
          TButton(
              label: 'View Explanation',
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final maps = await _fetchTeammateRecommendationMaps(context);
                if (!context.mounted || maps.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(
                        content: Text('No recommendation data available.')),
                  );
                  return;
                }
                navigator.pushNamed(R.aiExplanation, arguments: maps.first);
              }),
        ]),
      ),
    );
  }
}

// ── AI Explanation ────────────────────────────────────────────────────────────
class AIExplanationScreen extends StatelessWidget {
  const AIExplanationScreen({super.key});

  List<Map<String, dynamic>> _factorsFromRecommendation(
      Map<String, dynamic>? rec) {
    if (rec == null || rec.isEmpty) return const [];
    final match = ((rec['match_percent'] as num?)?.toDouble() ??
            (rec['similarity_score'] as num?)?.toDouble() ??
            0) /
        (rec.containsKey('match_percent') ? 100 : 1);
    final skills = (rec['skills'] as List?)?.cast<String>() ?? const [];
    final experience = rec['experience_level']?.toString() ?? '';
    final skillMatch = ((rec['skill_match_score'] as num?)?.toDouble() ?? match)
        .clamp(0.0, 1.0);
    final avgRating = ((rec['avg_rating'] as num?)?.toDouble() ?? 0) / 5.0;
    final availability =
        ((rec['availability_score'] as num?)?.toDouble() ?? match)
            .clamp(0.0, 1.0);
    final currentTasks = (rec['current_tasks'] as num?)?.toDouble() ?? 0;
    final workload =
        (1.0 - (currentTasks / 10).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    return [
      {
        'label': 'Skills Match',
        'value': skillMatch,
        'desc': skills.isEmpty
            ? 'Skills profile compared against your requirements'
            : 'Strong overlap: ${skills.take(4).join(', ')}',
      },
      {
        'label': 'Avg Rating',
        'value': avgRating.clamp(0.0, 1.0),
        'desc': experience.isNotEmpty
            ? 'Experience level: $experience'
            : 'Average peer rating from Teamify records',
      },
      {
        'label': 'Compatibility',
        'value': match.clamp(0.0, 1.0),
        'desc':
            'Overall ML similarity score from teammate recommendation model',
      },
      {
        'label': 'Availability',
        'value': availability,
        'desc': 'Workload and capacity considered in the recommendation',
      },
      {
        'label': 'Workload',
        'value': workload,
        'desc': 'Lower active task load improves assignment fit',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rec =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final name = rec?['full_name']?.toString().trim().isNotEmpty == true
        ? rec!['full_name'].toString()
        : rec?['display_name']?.toString() ?? 'Recommended teammate';
    final factors = _factorsFromRecommendation(rec);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('AI Explanation',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AIBanner(
            title: 'Why $name?',
            subtitle: 'AI reasoning for this recommendation'),
        const SizedBox(height: 16),
        TCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Reasoning Factors',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 16)),
          const SizedBox(height: 12),
          ...factors.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(f['label'] as String,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      Text('${(((f['value'] as double) * 100).toInt())}%',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold))
                    ]),
                    const SizedBox(height: 4),
                    TBar(value: f['value'] as double),
                    const SizedBox(height: 4),
                    Text(f['desc'] as String,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ]))),
        ])),
      ]),
    );
  }
}

// ── AI Priority ───────────────────────────────────────────────────────────────
class AIPriorityScreen extends StatefulWidget {
  const AIPriorityScreen({super.key});
  @override
  State<AIPriorityScreen> createState() => _AIPriorityScreenState();
}

class _AIPriorityScreenState extends State<AIPriorityScreen> {
  String _priority = 'medium';
  bool _suggesting = false;
  List<String> _reasons = [];
  String? _projectId;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final pid = args['project_id']?.toString();
      if (pid != null && pid.isNotEmpty) {
        setState(() => _projectId = pid);
      }
      final title = args['title']?.toString();
      if (title != null && title.isNotEmpty) {
        _titleCtrl.text = title;
      }
      final desc = args['description']?.toString();
      if (desc != null && desc.isNotEmpty) {
        _descCtrl.text = desc;
      }
    }
    await _loadProject();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProject() async {
    if (_projectId != null) return;
    final svc = context.read<AppServices>();
    final result = await svc.projects.listProjects();
    result.when(
      success: (list) {
        if (list.isNotEmpty && mounted) {
          setState(() => _projectId = list.first.id.toString());
        }
      },
      failure: (_) {},
    );
  }

  Future<void> _suggest() async {
    if (_projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No project found. Create a project first.')));
      return;
    }
    setState(() {
      _suggesting = true;
      _reasons = [];
    });
    try {
      final svc = context.read<AppServices>();
      final result = await svc.ai
          .suggestPriority(
            projectId: _projectId!,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
          )
          .unwrap();
      if (!mounted) return;
      final rawPriority =
          (result['priority'] ?? 'medium').toString().toLowerCase();
      final rawReasons = result['reasons'];
      setState(() {
        _priority = rawPriority;
        _reasons = rawReasons is List
            ? rawReasons.map((e) => e.toString()).toList()
            : [];
        _suggesting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _suggesting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Color _colorFor(String p) {
    switch (p) {
      case 'critical':
      case 'high':
        return AppColors.error;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('AI Priority Suggestion',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Describe your task',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 15)),
                const SizedBox(height: 10),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Task title',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Brief description (optional)',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _suggesting ? null : _suggest,
                    icon: _suggesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome, size: 18),
                    label:
                        Text(_suggesting ? 'Analysing…' : 'Get AI Suggestion'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white),
                  ),
                ),
              ])),
          const SizedBox(height: 16),
          TCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Suggested Priority',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 15)),
                const SizedBox(height: 12),
                ...['critical', 'high', 'medium', 'low'].map((p) {
                  final sel = _priority == p;
                  final c = _colorFor(p);
                  return GestureDetector(
                    onTap: () => setState(() => _priority = p),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: sel ? c.withValues(alpha: 0.1) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: sel ? c : AppColors.border,
                              width: sel ? 2 : 1)),
                      child: Row(children: [
                        Icon(Icons.flag, color: c, size: 20),
                        const SizedBox(width: 12),
                        Text(p[0].toUpperCase() + p.substring(1),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: sel ? c : AppColors.textPrimary,
                                fontSize: 15)),
                        const Spacer(),
                        if (sel) Icon(Icons.check_circle, color: c)
                      ]),
                    ),
                  );
                }),
                if (_reasons.isNotEmpty) ...[
                  const Divider(),
                  const Text('AI Reasoning:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  ..._reasons.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold)),
                              Expanded(
                                  child: Text(r,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary))),
                            ]),
                      )),
                ],
              ])),
          const Spacer(),
          TButton(
              label: 'Confirm Priority',
              onTap: () async {
                final result = await Navigator.pushNamed(
                  context,
                  R.aiDeadline,
                  arguments: {
                    'priority': _priority,
                    'project_id': _projectId,
                    'title': _titleCtrl.text.trim(),
                    'description': _descCtrl.text.trim(),
                  },
                );
                if (!context.mounted || result == null) return;
                Navigator.pop(context, result);
              }),
        ]),
      ),
    );
  }
}

// ── AI Deadline ───────────────────────────────────────────────────────────────
class AIDeadlineScreen extends StatefulWidget {
  const AIDeadlineScreen({super.key});
  @override
  State<AIDeadlineScreen> createState() => _AIDeadlineScreenState();
}

class _AIDeadlineScreenState extends State<AIDeadlineScreen> {
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  bool _loading = true;
  String _bannerSubtitle = 'Fetching AI suggestion…';
  List<String> _reasons = [];
  String _priority = 'medium';
  String? _projectId;
  String? _taskId;
  String _title = '';
  String _description = '';
  bool _saving = false;

  String _isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _confirmDeadline() async {
    if (_saving) return;
    setState(() => _saving = true);
    final svc = context.read<AppServices>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_taskId != null && _taskId!.isNotEmpty) {
        await svc.tasks.updateTask(_taskId!, {
          'due_date': _isoDate(_date),
          'priority': _priority,
        }).unwrap();
      } else if (_projectId != null &&
          _projectId!.isNotEmpty &&
          _title.trim().isNotEmpty) {
        await svc.tasks.createTask({
          'title': _title.trim(),
          'project_id': int.parse(_projectId!),
          'description': _description.trim(),
          'priority': _priority,
          'due_date': _isoDate(_date),
          'status': 'pending',
        }).unwrap();
      }
      if (!mounted) return;
      Navigator.pop(context, {
        'date': _date,
        'priority': _priority,
        'project_id': _projectId,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestion());
  }

  Future<void> _loadSuggestion() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    String priority = 'medium';
    String? projectId;
    if (args is Map) {
      priority = (args['priority'] as String?) ?? 'medium';
      projectId = args['project_id']?.toString();
      _priority = priority;
      _projectId = projectId;
      _taskId = args['task_id']?.toString();
      _title = args['title']?.toString() ?? '';
      _description = args['description']?.toString() ?? '';
    }
    if (projectId == null) {
      final svc = context.read<AppServices>();
      final result = await svc.projects.listProjects();
      result.when(
        success: (list) {
          if (list.isNotEmpty) projectId = list.first.id.toString();
        },
        failure: (_) {},
      );
    }
    if (projectId == null || !mounted) {
      setState(() {
        _loading = false;
        _bannerSubtitle = 'No project available. Using default 7-day estimate.';
      });
      return;
    }
    try {
      final svc = context.read<AppServices>();
      final result = await svc.ai
          .suggestDeadline(
            projectId: projectId!,
            priority: priority,
          )
          .unwrap();
      if (!mounted) return;
      final dateStr = result['suggested_date']?.toString() ?? '';
      final rawReasons = result['reasons'];
      final parsedDate = DateTime.tryParse(dateStr);
      final reasons = rawReasons is List
          ? rawReasons.map((e) => e.toString()).toList()
          : <String>[];
      setState(() {
        if (parsedDate != null) _date = parsedDate;
        _reasons = reasons;
        _bannerSubtitle = reasons.isNotEmpty
            ? reasons.first
            : 'AI suggests ${_date.day}/${_date.month}/${_date.year} based on priority';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _bannerSubtitle = 'Using default 7-day estimate.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('AI Deadline Suggestion',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                AIBanner(title: 'AI Suggestion', subtitle: _bannerSubtitle),
                const SizedBox(height: 16),
                TCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Suggested Deadline',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontSize: 16)),
                      const SizedBox(height: 16),
                      CalendarDatePicker(
                          initialDate: _date,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                          onDateChanged: (d) => setState(() => _date = d)),
                      if (_reasons.length > 1) ...[
                        const Divider(),
                        const Text('AI Reasoning:',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        ..._reasons.skip(1).map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ',
                                        style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold)),
                                    Expanded(
                                        child: Text(r,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color:
                                                    AppColors.textSecondary))),
                                  ]),
                            )),
                      ],
                    ])),
                const Spacer(),
                TButton(
                    label: _saving ? 'Saving…' : 'Confirm Deadline',
                    onTap: _saving ? null : _confirmDeadline),
              ]),
            ),
    );
  }
}

// ── Pomodoro ──────────────────────────────────────────────────────────────────
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});
  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  int _seconds = 25 * 60;
  bool _running = false;
  int _session = 1;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _running = !_running);
    if (_running) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_seconds > 0) {
          setState(() => _seconds--);
        } else {
          _timer?.cancel();
          setState(() {
            _running = false;
            _session++;
            _seconds = 25 * 60;
          });
        }
      });
    } else {
      _timer?.cancel();
    }
  }

  String get _timeStr =>
      '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final progress = _seconds / (25 * 60);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Pomodoro Timer',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          TChip(
              label: 'Session $_session',
              bg: AppColors.primary.withValues(alpha: 0.1)),
          const SizedBox(height: 32),
          SizedBox(
              width: 220,
              height: 220,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                    child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: AppColors.border,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.primary))),
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_timeStr,
                      style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  Text(_running ? 'Focus' : 'Paused',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ]),
              ])),
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            GestureDetector(
                onTap: () => setState(() {
                      _timer?.cancel();
                      _running = false;
                      _seconds = 25 * 60;
                    }),
                child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border)),
                    child: const Icon(Icons.refresh,
                        color: AppColors.textSecondary))),
            const SizedBox(width: 20),
            GestureDetector(
                onTap: _toggle,
                child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                    child: Icon(_running ? Icons.pause : Icons.play_arrow,
                        color: Colors.white, size: 32))),
            const SizedBox(width: 20),
            GestureDetector(
                onTap: () => setState(() {
                      _timer?.cancel();
                      _running = false;
                      _session++;
                      _seconds = 25 * 60;
                    }),
                child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border)),
                    child: const Icon(Icons.skip_next,
                        color: AppColors.textSecondary))),
          ]),
        ]),
      ),
    );
  }
}

// ── AI Insights ───────────────────────────────────────────────────────────────

double _delayPercentValue(num? raw) {
  if (raw == null) return 0;
  final v = raw.toDouble();
  if (v > 0 && v <= 1) return v * 100;
  return v.clamp(0, 100).toDouble();
}

Color _delayRiskColor(String? risk) {
  switch (risk?.toLowerCase()) {
    case 'high':
      return AppColors.error;
    case 'medium':
      return AppColors.warning;
    case 'low':
      return AppColors.success;
    default:
      return AppColors.textSecondary;
  }
}

String _delayRiskLabel(String? risk) {
  if (risk == null || risk.isEmpty) return 'Unknown';
  return '${risk[0].toUpperCase()}${risk.substring(1).toLowerCase()}';
}

class AIInsightsScreen extends StatefulWidget {
  const AIInsightsScreen({super.key});
  @override
  State<AIInsightsScreen> createState() => _AIInsightsScreenState();
}

class _AIInsightsScreenState extends State<AIInsightsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  List<api.ApiProject> _projects = [];
  String? _selectedProjectId;
  Map<String, String> _taskTitles = {};
  Map<String, dynamic>? _modelStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({String? projectId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final svc = context.read<AppServices>();

      final projectsResult =
          await svc.projects.listProjects(forceRefresh: true);
      if (!mounted) return;

      var projects = <api.ApiProject>[];
      projectsResult.when(
        success: (list) => projects = list,
        failure: (e) => throw Exception(e),
      );

      if (projects.isEmpty) {
        setState(() {
          _error =
              'No projects found. Join or create a project to see delay insights.';
          _loading = false;
          _projects = [];
        });
        return;
      }

      final selected = projectId ?? _selectedProjectId ?? projects.first.id;

      Map<String, dynamic>? modelStatus;
      final modelResult = await svc.ai.getDelayModelStatus();
      modelResult.when(
        success: (m) => modelStatus = m,
        failure: (_) {},
      );

      final prediction = await svc.ai
          .predictDelay(projectId: selected, forceRefresh: true)
          .unwrap();
      final err = prediction['error']?.toString();
      if (err != null && err.isNotEmpty) {
        throw Exception(err);
      }

      final titles = <String, String>{};
      final tasksResult = await svc.tasks.listTasks(
        projectId: selected,
        forceRefresh: true,
      );
      tasksResult.when(
        success: (tasks) {
          for (final t in tasks) {
            titles[t.id] = t.title;
          }
        },
        failure: (_) {},
      );

      if (!mounted) return;
      setState(() {
        _projects = projects;
        _selectedProjectId = selected;
        _data = prediction;
        _taskTitles = titles;
        _modelStatus = modelStatus;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _onProjectChanged(String? id) {
    if (id == null || id == _selectedProjectId) return;
    _load(projectId: id);
  }

  api.ApiProject? get _selectedProject {
    if (_selectedProjectId == null) return null;
    for (final p in _projects) {
      if (p.id == _selectedProjectId) return p;
    }
    return null;
  }

  Widget _metricCard({
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    return TCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 50,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskRiskTile(Map<String, dynamic> risk) {
    final taskId = risk['task_id']?.toString() ?? '';
    final apiTitle = risk['task_title']?.toString() ?? '';
    final title = apiTitle.isNotEmpty
        ? apiTitle
        : (_taskTitles[taskId] ??
            (taskId.isNotEmpty ? 'Task #$taskId' : 'Task'));
    final prob = _delayPercentValue(risk['delay_probability'] as num?);
    final level = risk['risk_level']?.toString();
    final mlSource = risk['ml_source']?.toString() ?? '';
    final isMl = mlSource == 'ml_model';
    final reasons = risk['reasons'] as List<dynamic>? ?? [];
    final reasonText =
        reasons.isNotEmpty ? reasons.first.toString() : 'No details';

    return TCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: _selectedProject == null
          ? null
          : () {
              Navigator.pushNamed(
                context,
                R.projectDetails,
                arguments: _selectedProject!.toDisplayModel(),
              );
            },
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: _delayRiskColor(level), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${prob.round()}% · ${_delayRiskLabel(level)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    TChip(
                      label: isMl ? 'ML model' : 'Heuristic',
                      bg: isMl
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.background,
                      textColor:
                          isMl ? AppColors.primary : AppColors.textSecondary,
                      fontSize: 9,
                    ),
                  ],
                ),
                Text(
                  reasonText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final delayPct = _delayPercentValue(_data?['delay_probability'] as num?);
    final riskLevel = _data?['risk_level']?.toString();
    final reasons = (_data?['reasons'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final taskRisks = (_data?['task_risks'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
      ..sort((a, b) => _delayPercentValue(b['delay_probability'] as num?)
          .compareTo(_delayPercentValue(a['delay_probability'] as num?)));

    final highRiskTasks = taskRisks
        .where((t) => _delayPercentValue(t['delay_probability'] as num?) >= 20)
        .toList();

    final mlSummary = _data?['ml_summary'] as Map<String, dynamic>?;
    final modelAvailable = _modelStatus?['model_available'] == true ||
        mlSummary?['model_available'] == true;
    final mlTasks = (mlSummary?['tasks_scored_with_ml'] as num?)?.toInt() ?? 0;
    final activeTasks =
        (mlSummary?['active_tasks'] as num?)?.toInt() ?? taskRisks.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI Insights (Delay Prediction)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error),
                        ),
                        const SizedBox(height: 16),
                        TButton(label: 'Retry', onTap: () => _load()),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_projects.isNotEmpty) ...[
                        const Text(
                          'Project',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(_selectedProjectId),
                          initialValue: _selectedProjectId,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          items: _projects
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    p.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _loading ? null : _onProjectChanged,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Icon(
                              modelAvailable
                                  ? Icons.psychology_outlined
                                  : Icons.info_outline,
                              color: modelAvailable
                                  ? AppColors.primary
                                  : AppColors.warning,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                modelAvailable
                                    ? 'Delay_Predictor.pkl is active — '
                                        'scoring uses live task & member data from the database.'
                                    : 'ML model file not found — using rule-based '
                                        'fallback until Delay_Predictor.pkl is installed.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (modelAvailable && activeTasks > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '$mlTasks of $activeTasks tasks scored with the ML model',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      _metricCard(
                        title: 'Average delay risk',
                        subtitle:
                            '${delayPct.round()}% across active tasks in this project',
                        accent: delayPct >= 40
                            ? AppColors.error
                            : delayPct >= 20
                                ? AppColors.warning
                                : AppColors.success,
                      ),
                      _metricCard(
                        title: 'Overall risk level',
                        subtitle: _delayRiskLabel(riskLevel),
                        accent: _delayRiskColor(riskLevel),
                      ),
                      _metricCard(
                        title: 'Tasks needing attention',
                        subtitle: highRiskTasks.isEmpty
                            ? 'No high-risk active tasks in this project'
                            : '${highRiskTasks.length} task(s) above 20% delay risk',
                        accent: highRiskTasks.isEmpty
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      if (reasons.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const TSectionHeader(title: 'Project insights'),
                        const SizedBox(height: 8),
                        ...reasons.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(color: AppColors.primary),
                                ),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (taskRisks.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const TSectionHeader(title: 'Tasks in this project'),
                        const SizedBox(height: 8),
                        ...taskRisks.map(_taskRiskTile),
                      ] else ...[
                        const SizedBox(height: 12),
                        const TCard(
                          child: Text(
                            'No active tasks in this project, or all tasks are completed.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

// ── AI Mentor ─────────────────────────────────────────────────────────────────
class AIMentorScreen extends StatefulWidget {
  const AIMentorScreen({super.key});
  @override
  State<AIMentorScreen> createState() => _AIMentorScreenState();
}

class _AIMentorScreenState extends State<AIMentorScreen> {
  bool _loading = true;
  String? _error;
  String _summary = '';
  List<String> _nextSteps = [];
  double _careerProgress = 0;

  static const _icons = [
    Icons.school_outlined,
    Icons.code,
    Icons.people_outline,
    Icons.trending_up
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<AppServices>();
      final userId =
          context.read<SessionController>().currentUser?.id.toString() ?? '';
      if (userId.isEmpty) throw Exception('Not logged in');
      final result = await svc.ai.mentorRecommendations(userId).unwrap();
      if (!mounted) return;
      setState(() {
        _summary = result['career_summary']?.toString() ?? '';
        final raw = result['next_steps'];
        _nextSteps = raw is List ? raw.map((e) => e.toString()).toList() : [];
        _careerProgress =
            (result['career_path_percentage'] as num?)?.toDouble() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('AI Mentor',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loading ? null : _load)
          ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                  TButton(label: 'Retry', onTap: _load),
                ]))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const AIBanner(
                      title: 'Your AI Mentor',
                      subtitle: 'Personalized guidance based on your progress'),
                  const SizedBox(height: 16),
                  if (_summary.isNotEmpty)
                    TCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Career Summary',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                      fontSize: 15)),
                              const SizedBox(height: 8),
                              Text(_summary,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary)),
                              if (_careerProgress > 0) ...[
                                const SizedBox(height: 10),
                                Row(children: [
                                  const Text('Career Progress',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                  const Spacer(),
                                  Text('${_careerProgress.toInt()}%',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                          fontSize: 13)),
                                ]),
                                const SizedBox(height: 4),
                                TBar(
                                    value: _careerProgress / 100,
                                    color: AppColors.primary),
                              ],
                            ])),
                  TCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Recommended Next Steps',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                fontSize: 16)),
                        const SizedBox(height: 12),
                        if (_nextSteps.isEmpty)
                          const Text(
                              'No recommendations yet. Complete more tasks to unlock insights.',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13))
                        else
                          ..._nextSteps.asMap().entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(children: [
                                Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Icon(_icons[e.key % _icons.length],
                                        color: AppColors.primary, size: 20)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(e.value,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                            fontSize: 13))),
                              ]))),
                      ])),
                  const SizedBox(height: 12),
                  TButton(
                      label: 'Open AI Mentor Chat',
                      onTap: () =>
                          Navigator.pushNamed(context, R.aiMentorChat)),
                ]),
    );
  }
}

// ── Team Recommendation ───────────────────────────────────────────────────────
class TeamRecommendationScreen extends StatelessWidget {
  const TeamRecommendationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Team Recommendation',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body:
          RepositoryLoader<List<({UserModel user, Map<String, dynamic> raw})>>(
        load: () => _fetchTeammateRecommendationItems(context),
        isEmpty: (items) => items.isEmpty,
        emptyMessage:
            'No teammate matches yet. Add skills to your profile and complete tasks to improve recommendations.',
        builder: (context, items) =>
            ListView(padding: const EdgeInsets.all(16), children: [
          const AIBanner(
              title: 'AI Team Builder',
              subtitle: 'Optimal team composition for your project'),
          const SizedBox(height: 16),
          ...items.map((item) {
            final u = item.user;
            final pct = _matchPercentFromMap(item.raw);
            return TCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  TAvatar(initials: u.initials, radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(u.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                        Text(u.skills.take(3).join(', '),
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        TBar(value: pct / 100),
                      ])),
                  const SizedBox(width: 12),
                  Column(children: [
                    Text('$pct%',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                    const Text('match',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                ]));
          }),
        ]),
      ),
    );
  }
}

// ── Recommended Courses ───────────────────────────────────────────────────────
class RecommendedCoursesScreen extends StatelessWidget {
  const RecommendedCoursesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Recommended Courses',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: RepositoryLoader<List<Map<String, dynamic>>>(
        load: () => _fetchRecommendedCourses(context),
        isEmpty: (courses) => courses.isEmpty,
        emptyMessage: 'No recommended courses found',
        builder: (context, courses) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: courses.length,
          itemBuilder: (_, i) {
            final c = courses[i];
            final match = _courseMatchPercent(c);
            return TCard(
              margin: const EdgeInsets.only(bottom: 12),
              onTap: () => openCourseLink(context, c),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.play_circle_outline,
                        color: AppColors.primary, size: 28)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          (c['title'] ?? c['name'] ?? 'Recommended course')
                              .toString(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      Text((c['platform'] ?? c['provider'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      TBar(value: match / 100),
                      const SizedBox(height: 2),
                      Text(_courseStatusLine(c),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.primary)),
                    ])),
                const Icon(Icons.open_in_new,
                    size: 18, color: AppColors.textSecondary),
              ]),
            );
          },
        ),
      ),
    );
  }
}

// ── Skills Screen ─────────────────────────────────────────────────────────────
class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});
  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  bool _loading = true;
  String? _error;
  MentorInsights? _insights;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<AppServices>();
      final userId =
          context.read<SessionController>().currentUser?.id.toString() ?? '';
      if (userId.isEmpty) throw Exception('Not logged in');
      final insights = await svc.ai.getMentorInsights(userId).unwrap();
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<({String title, double score, bool owned})> _skillRows(
      MentorInsights insights) {
    final seen = <String>{};
    final rows = <({String title, double score, bool owned})>[];

    void add(MentorSkillInsight g) {
      final key = g.area.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      rows.add((
        title: g.area,
        score: g.score.clamp(0, 100),
        owned: g.severity == 'owned',
      ));
    }

    for (final g in insights.skillGaps) {
      add(g);
    }
    for (final w in insights.weaknesses) {
      if (!seen.contains(w.area.trim().toLowerCase())) add(w);
    }
    for (final s in insights.strengths) {
      if (rows.length >= 8) break;
      if (!seen.contains(s.area.trim().toLowerCase())) {
        seen.add(s.area.trim().toLowerCase());
        rows.add((title: s.area, score: s.score.clamp(0, 100), owned: true));
      }
    }
    for (final name in insights.profileSkills) {
      if (rows.length >= 10) break;
      final key = name.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      rows.add((title: name, score: 0, owned: true));
    }

    rows.sort((a, b) => b.score.compareTo(a.score));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _insights != null ? _skillRows(_insights!) : const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Skills',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loading ? null : _load)
          ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                  TButton(label: 'Retry', onTap: _load),
                ]))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Text(
                          'Complete projects and add skills to your profile to unlock personalized recommendations.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                        ),
                      )
                    else
                      ...rows.map(
                        (r) => MentorSkillCard(
                          title: r.title,
                          score: r.score,
                          levelLabel: MentorSkillCard.levelForScore(r.score,
                              owned: r.owned),
                          onExplore: () => MentorSkillCard.openExploreChat(
                            context,
                            skillName: r.title,
                            score: r.score,
                            levelLabel: MentorSkillCard.levelForScore(
                              r.score,
                              owned: r.owned,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
