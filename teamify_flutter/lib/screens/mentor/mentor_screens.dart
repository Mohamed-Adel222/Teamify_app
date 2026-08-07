import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/session/session_controller.dart';
import '../../data/models/api_helpers.dart';
import '../../services/app_services.dart';
import '../../services/ai_service.dart';
import '../../widgets/widgets.dart';
import 'mentor_skill_ui.dart';

// ── Mentor Main Screen (Tabs Container) ──────────────────────────────────────
class MentorMainScreen extends StatefulWidget {
  final int initialTab;
  const MentorMainScreen({super.key, this.initialTab = 0});
  @override
  State<MentorMainScreen> createState() => _MentorMainScreenState();
}

class _MentorMainScreenState extends State<MentorMainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  String? _error;
  MentorInsights? _insights;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 4),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _load(forceRefresh: true));
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final session = context.read<SessionController>();
    final svc = context.read<AppServices>();
    final user = session.currentUser;

    setState(() {
      _loading = true;
      _error = null;
    });

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _error = 'Not logged in';
        _loading = false;
      });
      return;
    }

    try {
      if (forceRefresh) {
        await svc.ai.invalidateMentorInsights(user.id);
      }
      final result = await svc.ai.getMentorInsights(
        user.id,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        setState(() {
          _insights = result.data!;
          _loading = false;
        });
      } else {
        final msg = result.error ?? 'Request failed';
        setState(() {
          _error = result.isNetworkError
              ? 'Cannot reach the server. Is Flask running on port 5022?'
              : (result.statusCode != null
                  ? 'Error ${result.statusCode}: $msg'
                  : msg);
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Career Mentor',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (_insights != null && _insights!.generatedAt.isNotEmpty)
              Text(
                'Live data · ${_insights!.feedbackCount} feedback · ${_insights!.tasksCompleted}/${_insights!.tasksAssigned} tasks',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          indicator: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: 'Mentor'),
            Tab(text: 'Skills'),
            Tab(text: 'Courses'),
            Tab(text: 'Performance'),
            Tab(text: 'Feedback')
          ],
        ),
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
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _load(forceRefresh: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(forceRefresh: true),
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _MentorOverviewTab(insights: _insights!),
                      _SkillsTab(insights: _insights!),
                      _DetailedCoursesTab(insights: _insights!),
                      _DetailedPerformanceTab(insights: _insights!),
                      _FeedbackTab(
                          onSubmitted: () => _load(forceRefresh: true)),
                    ],
                  ),
                ),
      floatingActionButton: _insights == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  MentorGeneralChatArgs.openFromInsights(context, _insights!),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              label: const Text('Ask AI Mentor',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }
}

// ── Detailed Performance Tab ──────────────────────────────────────────────────
class _DetailedPerformanceTab extends StatelessWidget {
  final MentorInsights insights;
  const _DetailedPerformanceTab({required this.insights});

  String _trendLabel(String trend) {
    switch (trend) {
      case 'up':
        return 'Improving';
      case 'down':
        return 'Needs attention';
      default:
        return 'Stable';
    }
  }

  IconData _trendIcon(String trend) {
    switch (trend) {
      case 'up':
        return Icons.trending_up;
      case 'down':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  Color _trendColor(String trend) {
    switch (trend) {
      case 'up':
        return AppColors.success;
      case 'down':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  int _feedbackStars(Map<String, dynamic> f) =>
      (f['avg_rating'] as num?)?.toInt() ??
      (f['rating'] as num?)?.toInt() ??
      (f['quality_score'] as num?)?.round() ??
      0;

  String _feedbackAuthor(Map<String, dynamic> f) =>
      f['reviewer_name']?.toString() ??
      f['author_name']?.toString() ??
      'Teammate';

  String _feedbackBody(Map<String, dynamic> f) =>
      f['feedback_text']?.toString() ?? f['content']?.toString() ?? '';

  String _feedbackDate(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final perfScore = insights.performanceOverall;
    final perf = insights.performanceHistory;
    final history = perf['history'] is List ? (perf['history'] as List) : [];
    final commitment = insights.metricScore('commitment');
    final teamwork = insights.metricScore('teamwork');
    final quality = insights.metricScore('quality');
    final trend = insights.trend;
    final recent = insights.recentFeedback;
    final hasPeer = insights.hasPeerPerformanceData;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Performance',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(
          hasPeer
              ? 'Scores from ${insights.feedbackCount} peer feedback & ${insights.ratingCount} ratings in your projects'
              : 'No peer scores yet — complete tasks and collect feedback from teammates',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TCard(
          child: Row(
            children: [
              _statChip('Feedback', '${insights.feedbackCount}'),
              const SizedBox(width: 8),
              _statChip('Ratings', '${insights.ratingCount}'),
              const SizedBox(width: 8),
              _statChip(
                hasPeer ? 'Peer avg' : 'Score',
                hasPeer ? '${perfScore.toInt()}/100' : '—',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppColors.primary.withValues(alpha: 0.05),
              AppColors.success.withValues(alpha: 0.05)
            ]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
          ),
          child: Column(children: [
            Stack(alignment: Alignment.center, children: [
              SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                      value: hasPeer ? perfScore / 100 : 0,
                      strokeWidth: 12,
                      backgroundColor: AppColors.border,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primary))),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(hasPeer ? perfScore.toInt().toString() : '—',
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                Text(hasPeer ? 'Performance avg' : 'Awaiting feedback',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ]),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_trendIcon(trend), color: _trendColor(trend), size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${_trendLabel(trend)} · ${insights.aiTip.isNotEmpty ? insights.aiTip : 'Based on stored feedback'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _trendColor(trend),
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Performance Metrics',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _metricItem('Commitment', commitment.toInt(), Icons.visibility_outlined,
            AppColors.success),
        _metricItem('Teamwork', teamwork.toInt(), Icons.people_outline,
            AppColors.primary),
        _metricItem('Quality', quality.toInt(),
            Icons.workspace_premium_outlined, AppColors.accent),
        const SizedBox(height: 24),
        const Text('Recent Peer Feedback',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        if (recent.isEmpty)
          const Text(
            'No peer feedback stored yet. Teammates can rate you on the Feedback tab.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          )
        else
          ...recent.take(6).map((f) {
            final stars = _feedbackStars(f);
            final created = f['created_at']?.toString() ?? '';
            final body = _feedbackBody(f);
            return TCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _feedbackAuthor(f),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < stars ? Icons.star : Icons.star_border,
                            size: 14,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (f['project_name'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        f['project_name'].toString(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        body,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  if (created.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _feedbackDate(created),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        const SizedBox(height: 24),
        const Text('History',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        TCard(
            child: SizedBox(
                height: 150,
                child: history.isEmpty
                    ? Center(
                        child: Text(
                          insights.feedbackCount == 0 &&
                                  insights.ratingCount == 0
                              ? 'No peer feedback yet. Use the Feedback tab to rate teammates — scores will appear here.'
                              : 'Not enough monthly data for a chart yet.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: history.take(6).map((e) {
                          final period = e['period']?.toString() ?? '';
                          final label =
                              period.length >= 7 ? period.substring(5) : period;
                          return _bar(
                            label,
                            ((e['score'] as num?)?.toDouble() ?? 0) / 100,
                          );
                        }).toList(),
                      ))),
      ],
    );
  }

  Widget _statChip(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ]),
        ),
      );

  Widget _metricItem(String label, int val, IconData icon, Color col) => TCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(children: [
          Row(children: [
            Icon(icon, color: col, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$val',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 12),
          TBar(value: val / 100, color: col),
        ]),
      );

  Widget _bar(String label, double h) =>
      Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(
            width: 20,
            height: 100 * h,
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 8),
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ]);
}

// ── Detailed Courses Tab ──────────────────────────────────────────────────────
class _DetailedCoursesTab extends StatefulWidget {
  final MentorInsights insights;
  const _DetailedCoursesTab({required this.insights});

  @override
  State<_DetailedCoursesTab> createState() => _DetailedCoursesTabState();
}

class _DetailedCoursesTabState extends State<_DetailedCoursesTab> {
  final Set<String> _enrolled = {};

  Future<void> _enroll(
      BuildContext context, Map<String, dynamic> course) async {
    final title = course['title']?.toString() ?? 'Course';
    final platform = course['platform']?.toString() ?? 'provider';
    final urlStr = course['url']?.toString() ?? '';
    final uri = Uri.tryParse(urlStr);
    if (uri == null || !uri.hasScheme) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No enrollment link for $title')),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (launched) {
      setState(() => _enrolled.add(title));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opening $title on $platform…')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open course link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = widget.insights.recommendedCourses;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Courses',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('AI-recommended for you',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        const AIBanner(
            title: 'Personalized Learning',
            subtitle: 'These courses are selected based on your goals'),
        const SizedBox(height: 24),
        const Text('Recommended for You',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        if (courses.isEmpty)
          const Text(
              'No courses yet — complete your profile skills so the ML catalog can match gaps.')
        else ...[
          if (widget.insights.mlRating['source'] == 'ml_model')
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Ranked by teamify_model.pkl + course catalog (stored in backend)',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ...courses.map((c) {
            final hours = c['hours']?.toString();
            final duration = c['duration']?.toString() ??
                (hours != null && hours.isNotEmpty
                    ? '$hours hrs'
                    : 'Self-paced');
            final ratingRaw = c['rating'];
            final rating = ratingRaw is num
                ? ratingRaw.toDouble()
                : double.tryParse(ratingRaw?.toString() ?? '') ?? 4.5;
            return _courseItem(context, c, duration, rating);
          }),
        ],
      ],
    );
  }

  Widget _courseItem(
    BuildContext context,
    Map<String, dynamic> course,
    String time,
    double rate,
  ) {
    final title = course['title']?.toString() ?? 'Course';
    final org = course['platform']?.toString() ?? 'Provider';
    final level = course['level']?.toString() ?? 'Recommended';
    final enrolled = _enrolled.contains(title);

    return TCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text('$org • $time',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          if (course['fills'] is List && (course['fills'] as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Closes gap: ${(course['fills'] as List).take(3).join(', ')}',
                style: const TextStyle(fontSize: 10, color: AppColors.primary),
              ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.star, color: Colors.amber, size: 14),
            Text(' $rate',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            if (course['relevance'] != null) ...[
              const SizedBox(width: 8),
              Text(
                'match ${((course['relevance'] as num) * 100).round()}%',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          TChip(
              label: level,
              bg: AppColors.primary.withValues(alpha: 0.1),
              textColor: AppColors.primary),
          const SizedBox(height: 8),
          ElevatedButton(
              onPressed: enrolled ? null : () => _enroll(context, course),
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      enrolled ? AppColors.success : AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 20)),
              child: Text(enrolled ? 'Enrolled ✓' : 'Enroll',
                  style: const TextStyle(color: Colors.white, fontSize: 12))),
        ]),
      ]),
    );
  }
}

// ── Feedback Tab ─────────────────────────────────────────────────────────────
class _FeedbackTab extends StatefulWidget {
  final VoidCallback? onSubmitted;
  const _FeedbackTab({this.onSubmitted});
  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  int _rating = 0;
  final _ctrl = TextEditingController();
  bool _submitting = false;
  bool _aiAssisting = false;
  String _aiSuggestion =
      'Consider mentioning specific achievements or areas for improvement to make your feedback more actionable.';

  // Project + member selection
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _members = [];
  String? _selectedProjectId;
  String? _selectedMemberId;
  bool _loadingProjects = true;
  String? _loadError;

  List<Map<String, dynamic>> _recentFeedback = [];
  bool _loadingRecent = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProjects();
      _loadRecentFeedback();
    });
  }

  Future<void> _loadRecentFeedback() async {
    final userId = context.read<SessionController>().currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loadingRecent = false);
      return;
    }
    setState(() => _loadingRecent = true);
    try {
      final result = await context
          .read<AppServices>()
          .feedback
          .getUserFeedback(userId, forceRefresh: true);
      if (mounted) {
        setState(() {
          _recentFeedback = result.data ?? [];
          _loadingRecent = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  String _memberName() {
    if (_selectedMemberId == null) return 'your teammate';
    for (final m in _members) {
      if (m['id'] == _selectedMemberId) {
        return m['name'] as String? ?? 'your teammate';
      }
    }
    return 'your teammate';
  }

  String _projectName() {
    if (_selectedProjectId == null) return 'the project';
    for (final p in _projects) {
      if (p['id'] == _selectedProjectId) {
        return p['name'] as String? ?? 'the project';
      }
    }
    return 'the project';
  }

  Future<void> _runAiAssist() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select a star rating first, then use AI assist.')));
      return;
    }
    setState(() => _aiAssisting = true);
    try {
      final result =
          await context.read<AppServices>().ai.generateFeedbackAssist(
                rating: _rating,
                teammateName: _memberName(),
                projectName: _projectName(),
              );
      if (!mounted) return;
      result.when(
        success: (data) {
          final draft = data['draft'] ?? '';
          final tip = data['suggestion'] ?? '';
          setState(() {
            if (draft.isNotEmpty) _ctrl.text = draft;
            if (tip.isNotEmpty) _aiSuggestion = tip;
          });
        },
        failure: (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e), backgroundColor: AppColors.error),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _aiAssisting = false);
    }
  }

  int _feedbackStars(Map<String, dynamic> f) =>
      (f['avg_rating'] as num?)?.toInt() ??
      (f['rating'] as num?)?.toInt() ??
      (f['quality_score'] as num?)?.round() ??
      0;

  String _feedbackAuthor(Map<String, dynamic> f) =>
      f['reviewer_name']?.toString() ??
      f['author_name']?.toString() ??
      'Teammate';

  String _feedbackBody(Map<String, dynamic> f) =>
      f['feedback_text']?.toString() ?? f['content']?.toString() ?? '';

  Future<void> _loadProjects() async {
    final projects = context.read<AppServices>().projects;
    try {
      final res = await projects.listProjects();
      if (!mounted) return;
      if (res.isSuccess) {
        setState(() {
          _projects =
              res.data!.map((p) => {'id': p.id, 'name': p.name}).toList();
          _loadingProjects = false;
        });
      } else {
        setState(() {
          _loadError = res.error;
          _loadingProjects = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingProjects = false;
      });
    }
  }

  Future<void> _loadMembers(String projectId) async {
    setState(() => _members = []);
    final projects = context.read<AppServices>().projects;
    final currentUserId =
        context.read<SessionController>().currentUser?.id ?? '';
    try {
      final res = await projects.listMembers(projectId);
      if (!mounted) return;
      if (res.isSuccess) {
        setState(() {
          // Exclude the current user — you cannot rate yourself
          _members = res.data!
              .where((u) => u.id != currentUserId)
              .map((u) => {
                    'id': u.id,
                    'name': u.fullName.isNotEmpty ? u.fullName : u.displayName
                  })
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a star rating first.')));
      return;
    }
    if (_selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a project.')));
      return;
    }
    if (_selectedMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a team member to rate.')));
      return;
    }

    setState(() => _submitting = true);
    final svc = context.read<AppServices>();
    final session = context.read<SessionController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await svc.feedback.submitFeedback(
        targetUserId: _selectedMemberId!,
        projectId: _selectedProjectId!,
        rating: _rating,
        comment: _ctrl.text.trim(),
      );
      if (!mounted) return;
      if (result.isSuccess) {
        final userId = session.currentUser?.id;
        if (userId != null) {
          await svc.ai.invalidateMentorInsights(userId);
        }
        await svc.ai.invalidateMentorInsights(_selectedMemberId!);
        widget.onSubmitted?.call();
        await _loadRecentFeedback();
        setState(() {
          _rating = 0;
          _ctrl.clear();
          _selectedMemberId = null;
        });
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Feedback saved to database. Performance & mentor insights will refresh.'),
            backgroundColor: AppColors.success));
      } else {
        final msg = result.error ?? 'Submission failed.';
        messenger.showSnackBar(SnackBar(
            content: Text(result.statusCode != null
                ? 'Error ${result.statusCode}: $msg'
                : msg),
            backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProjects) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
          child: Text(_loadError!,
              style: const TextStyle(color: AppColors.error)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Peer Feedback',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('Rate a teammate on your project',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        TCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Project picker ──────────────────────────────────────────────
          const Text('Project', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _projects.isEmpty
              ? const Text('No projects found.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13))
              : DropdownButtonFormField<String>(
                  key: ValueKey('project_${_selectedProjectId ?? 'none'}'),
                  initialValue: _selectedProjectId,
                  hint: const Text('Select a project'),
                  items: _projects
                      .map((p) => DropdownMenuItem<String>(
                            value: p['id'] as String,
                            child: Text(p['name'] as String),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedProjectId = val;
                      _selectedMemberId = null;
                      _members = [];
                    });
                    if (val != null) _loadMembers(val);
                  },
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), isDense: true),
                ),
          const SizedBox(height: 16),

          // ── Member picker ───────────────────────────────────────────────
          const Text('Team member to rate',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _selectedProjectId == null
              ? const Text('Select a project first.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13))
              : _members.isEmpty
                  ? const Text('No other members in this project.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13))
                  : DropdownButtonFormField<String>(
                      key: ValueKey('member_${_selectedProjectId}_'
                          '${_selectedMemberId ?? 'none'}_${_members.length}'),
                      initialValue: _selectedMemberId,
                      hint: const Text('Select a member'),
                      items: _members
                          .map((m) => DropdownMenuItem<String>(
                                value: m['id'] as String,
                                child: Text(m['name'] as String),
                              ))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedMemberId = val),
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), isDense: true),
                    ),
          const SizedBox(height: 20),

          // ── Star rating ────────────────────────────────────────────────
          const Text('Rating (1–5)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(
                  5,
                  (i) => IconButton(
                        icon: Icon(i < _rating ? Icons.star : Icons.star_border,
                            size: 32,
                            color: i < _rating
                                ? Colors.amber
                                : AppColors.textHint),
                        onPressed: () => setState(() => _rating = i + 1),
                      ))),
          const SizedBox(height: 20),

          // ── Comment ────────────────────────────────────────────────────
          const Text('Your Feedback',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12)),
            child: Stack(
              children: [
                TextField(
                  controller: _ctrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Share your thoughts...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.only(right: 88, bottom: 28),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: TextButton.icon(
                    onPressed: _aiAssisting ? null : _runAiAssist,
                    icon: _aiAssisting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome,
                            size: 16, color: AppColors.primary),
                    label: Text(
                      _aiAssisting ? 'Generating…' : 'AI assist',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _submitting
              ? const Center(child: CircularProgressIndicator())
              : TButton(
                  label: 'Submit Feedback',
                  icon: Icons.send,
                  onTap: _submit,
                ),
        ])),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF4FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Suggestion',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _aiSuggestion,
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
        ),
        const SizedBox(height: 20),
        const Text(
          'Recent Feedback',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        if (_loadingRecent)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_recentFeedback.isEmpty)
          const Text(
            'No peer feedback yet. Ratings from teammates will appear here.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          )
        else
          ..._recentFeedback.take(10).map((f) {
            final stars = _feedbackStars(f);
            final created = f['created_at']?.toString() ?? '';
            return TCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _feedbackAuthor(f),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < stars ? Icons.star : Icons.star_border,
                            size: 14,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_feedbackBody(f).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _feedbackBody(f),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (f['project_name'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Project: ${f['project_name']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    created.isNotEmpty
                        ? formatRelativeTime(created)
                        : 'Recently',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

// ── Mentor Overview Tab ───────────────────────────────────────────────────────
class _MentorOverviewTab extends StatelessWidget {
  final MentorInsights insights;
  const _MentorOverviewTab({required this.insights});

  List<Map<String, dynamic>> _recentTasks(MentorInsights insights) {
    final raw = insights.rawAnalysis['user_profile'];
    if (raw is! Map) return const [];
    final list = raw['recent_tasks'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((t) => (t['title']?.toString() ?? '').isNotEmpty)
        .toList();
  }

  Widget? _mlRatingBanner() {
    final ml = insights.rawAnalysis['ml_rating'];
    if (ml is! Map) return null;
    final rating = ml['predicted_rating'];
    final label = ml['performance_label'] ?? ml['percentile_label'];
    final source = ml['source']?.toString();
    if (rating == null) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.psychology_outlined,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              source == 'ml_model'
                  ? 'Teamify ML model: $rating/5${label != null ? ' ($label)' : ''}'
                  : 'Estimated rating: $rating/5',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mlBanner = _mlRatingBanner();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TCard(
          color: AppColors.primary.withValues(alpha: 0.05),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.stars, color: AppColors.primary, size: 24),
              SizedBox(width: 8),
              Text('Your AI Career Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            if (mlBanner != null) mlBanner,
            const SizedBox(height: 12),
            Text(
              insights.careerSummary,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              [
                insights.careerLevel,
                if (insights.experienceYears > 0)
                  '${insights.experienceYears.toStringAsFixed(0)} yrs experience',
                '${insights.tasksCompleted}/${insights.tasksAssigned} tasks done',
                '${insights.feedbackCount} feedback',
              ].join(' · '),
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            if (_recentTasks(insights).isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Your projects (from database)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              ..._recentTasks(insights).map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${t['title']} — ${t['status']}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        const Row(children: [
          Text('Career Path Progress',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 12),
        TCard(
            child: Column(children: [
          const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Current',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text('Next Level',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ]),
          const SizedBox(height: 12),
          TBar(value: insights.careerScore / 100),
          const SizedBox(height: 8),
          Text(
              '${insights.careerLevel}${insights.targetRole.isNotEmpty ? ' → ${insights.targetRole}' : ''} · ${insights.careerScore.toStringAsFixed(1)}/100',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ])),
        const SizedBox(height: 20),
        const Text('Strengths',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        if (insights.strengths.isEmpty)
          const Text(
              'Complete projects and receive peer feedback to see strengths.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
        else
          ...insights.strengths.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.area,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          if (s.message.isNotEmpty)
                            Text(s.message,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        const SizedBox(height: 20),
        const Text('Areas for Improvement',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        if (insights.weaknesses.isEmpty && insights.skillGaps.isEmpty)
          const Text('No critical gaps right now — keep building momentum.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
        else ...[
          ...insights.weaknesses.map((w) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.warning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.area,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          if (w.message.isNotEmpty)
                            Text(w.message,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          if (insights.skillGaps.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Skills to develop',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ...insights.skillGaps.take(3).map((g) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• ${g.area}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                )),
          ],
        ],
      ],
    );
  }
}

// ── Skills Tab ────────────────────────────────────────────────────────────────
class _SkillsTab extends StatelessWidget {
  final MentorInsights insights;
  const _SkillsTab({required this.insights});

  List<({String title, double score, bool owned})> _skillRows() {
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
      rows.add((title: name, score: 72, owned: true));
    }

    rows.sort((a, b) => b.score.compareTo(a.score));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _skillRows();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text(
              'Complete projects and add skills to your profile to unlock personalized recommendations.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          )
        else
          ...rows.map(
            (r) => MentorSkillCard(
              title: r.title,
              score: r.score,
              levelLabel:
                  MentorSkillCard.levelForScore(r.score, owned: r.owned),
              onExplore: () => MentorSkillCard.openExploreChat(
                context,
                skillName: r.title,
                score: r.score,
                levelLabel:
                    MentorSkillCard.levelForScore(r.score, owned: r.owned),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Career Mentor Chat ────────────────────────────────────────────────────────
class CareerMentorChatScreen extends StatefulWidget {
  const CareerMentorChatScreen({super.key});

  @override
  State<CareerMentorChatScreen> createState() => _CareerMentorChatScreenState();
}

class _CareerMentorChatScreenState extends State<CareerMentorChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _msgs = [];
  bool _loading = false;
  bool _loadingHistory = true;
  MentorSkillChatArgs? _skillFocus;
  MentorGeneralChatArgs? _mlSession;
  List<String> _currentSuggestions = [
    'What should I focus on next?',
    'How do I get promoted?',
    'Recommend courses for me',
    'Review my skill gaps',
  ];

  static const _greeting =
      "Hi! I'm your AI Career Mentor. I'm here to help you grow in your career. What would you like to focus on today?";

  MentorSkillChatArgs? _readSkillArgs() {
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is MentorSkillChatArgs ? args : null;
  }

  MentorGeneralChatArgs? _readMlArgs() {
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is MentorGeneralChatArgs ? args : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapChat());
  }

  Future<void> _bootstrapChat() async {
    _skillFocus = _readSkillArgs();
    _mlSession = _skillFocus == null ? _readMlArgs() : null;
    if (_skillFocus != null) {
      await _loadSkillFocusSession();
    } else if (_mlSession != null) {
      await _loadMlBackedSession();
    } else {
      await _loadHistory();
    }
  }

  Future<void> _loadMlBackedSession() async {
    final ml = _mlSession!;
    await _loadThreadHistory(
      threadKey: MentorGeneralChatArgs.threadKey,
      buildGreeting: () async => ml.buildGreeting(),
      suggestions: ml.buildSuggestions(),
      greetingExtras:
          ml.usesMlModel ? {'mlLabel': _mlLabelFromRating(ml.mlRating)} : null,
    );
  }

  String? _mlLabelFromRating(Map<String, dynamic> ml) {
    final rating = ml['predicted_rating'];
    final label = ml['percentile_label'] ?? ml['performance_label'];
    if (rating == null) return null;
    return 'Teamify ML · $rating/5${label != null ? ' ($label)' : ''}';
  }

  Future<void> _loadSkillFocusSession() async {
    final skill = _skillFocus!;
    await _loadThreadHistory(
      threadKey: skill.threadKey,
      buildGreeting: () => _skillGreeting(skill),
      suggestions: _skillSuggestions(skill),
    );
  }

  Future<void> _loadThreadHistory({
    required String threadKey,
    required Future<String> Function() buildGreeting,
    List<String> suggestions = const [],
    Map<String, dynamic>? greetingExtras,
  }) async {
    final ai = context.read<AppServices>().ai;
    try {
      final result = await ai.mentorChatHistory(threadKey: threadKey);
      if (!mounted) return;

      if (!result.isSuccess) {
        final greet = await buildGreeting();
        if (!mounted) return;
        setState(() {
          _msgs
            ..clear()
            ..add({'text': greet, 'isMe': false, ...?greetingExtras});
          _currentSuggestions = suggestions;
          _loadingHistory = false;
        });
        return;
      }

      final rows = result.data!;
      if (!mounted) return;

      if (rows.isEmpty) {
        final greet = await buildGreeting();
        if (!mounted) return;
        setState(() {
          _msgs
            ..clear()
            ..add({'text': greet, 'isMe': false, ...?greetingExtras});
          _currentSuggestions = suggestions;
          _loadingHistory = false;
        });
      } else {
        setState(() {
          _msgs.clear();
          for (final row in rows) {
            final content = row['content']?.toString() ?? '';
            if (content.isEmpty) continue;
            _msgs.add({
              'text': content,
              'isMe': row['role']?.toString() == 'user',
            });
          }
          _loadingHistory = false;
        });
      }
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      final greet = await buildGreeting();
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..add({'text': greet, 'isMe': false, ...?greetingExtras});
        _currentSuggestions = suggestions;
        _loadingHistory = false;
      });
    }
  }

  List<String> _skillSuggestions(MentorSkillChatArgs skill) {
    final name = skill.skillName;
    return [
      'What courses help me master $name?',
      'How do I improve my $name skills?',
      'What projects build $name experience?',
      'How does $name affect my promotion path?',
    ];
  }

  Future<String> _skillGreeting(MentorSkillChatArgs skill) async {
    final session = context.read<SessionController>();
    final svc = context.read<AppServices>();
    final user = session.currentUser;
    final name = skill.skillName;
    final level = skill.levelLabel;
    final score = skill.score.round();

    var mlLine = '';
    var careerLine = '';
    var courseHint = '';

    if (user != null) {
      try {
        final result = await svc.ai.getMentorInsights(user.id);
        if (result.isSuccess && result.data != null) {
          final insights = result.data!;
          final ml = insights.mlRating;
          final pred = ml['predicted_rating'];
          final label = ml['percentile_label'] ?? ml['performance_label'];
          if (pred != null) {
            mlLine = ml['source'] == 'ml_model'
                ? 'ML rating (teamify_model.pkl): **$pred/5**${label != null ? ' ($label)' : ''}.'
                : 'Estimated rating: **$pred/5**.';
          }
          careerLine =
              'Career level **${insights.careerLevel}** · score **${insights.careerScore.toStringAsFixed(0)}/100**.';

          final matched = insights.recommendedCourses.where((c) {
            final blob =
                '${c['title'] ?? ''} ${c['skills_covered'] ?? ''} ${c['skill'] ?? ''}'
                    .toLowerCase();
            return blob.contains(name.toLowerCase());
          }).take(2);
          if (matched.isNotEmpty) {
            courseHint = matched
                .map((c) =>
                    '• **${c['title']}** (${c['platform'] ?? 'Online'}, ${c['hours'] ?? '?'} hrs)')
                .join('\n');
          }
        }
      } catch (_) {}
    }

    return "Let's explore **$name** — you're at **$level** level with relevance **$score/100**.\n\n"
        "${mlLine.isNotEmpty ? '$mlLine\n' : ''}"
        "${careerLine.isNotEmpty ? '$careerLine\n\n' : ''}"
        "${courseHint.isNotEmpty ? 'Recommended for this skill:\n$courseHint\n\n' : ''}"
        "Ask about courses, practice plans, or how **$name** fits your next role.";
  }

  Future<String> _dbGreeting() async {
    final session = context.read<SessionController>();
    final svc = context.read<AppServices>();
    final user = session.currentUser;
    if (user == null) return _greeting;
    final insights = await svc.ai.getMentorInsights(user.id);
    if (!insights.isSuccess || insights.data == null) return _greeting;
    final i = insights.data!;
    final ml = i.mlRating;
    final pred = ml['predicted_rating'];
    final label = ml['percentile_label'] ?? ml['performance_label'];
    final mlLine = pred != null
        ? (ml['source'] == 'ml_model'
            ? 'ML rating (teamify_model.pkl): **$pred/5**${label != null ? ' ($label)' : ''}.'
            : 'Estimated rating: **$pred/5**.')
        : '';
    final gaps = i.skillGaps
        .where((g) => g.severity != 'owned')
        .map((g) => g.area)
        .take(2)
        .join(', ');
    return "Hi! I'm your AI Career Mentor, connected to your live Teamify data.\n\n"
        "${mlLine.isNotEmpty ? '$mlLine\n' : ''}"
        "You're **${i.careerLevel}** with career score **${i.careerScore.toStringAsFixed(0)}/100**."
        "${gaps.isNotEmpty ? ' Focus areas: $gaps.' : ''}\n\n"
        "Ask about courses, promotion, or your skill gaps.";
  }

  Future<void> _loadHistory() async {
    await _loadThreadHistory(
      threadKey: MentorGeneralChatArgs.threadKey,
      buildGreeting: _dbGreeting,
      suggestions: _currentSuggestions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final skill = _skillFocus;
    final ml = _mlSession;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill != null ? 'Explore · ${skill.skillName}' : 'AI Mentor',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  ml != null
                      ? 'Teamify ML · ${MentorGeneralChatArgs.mlModelPath}'
                      : 'Teamify ML · Online',
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.success),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
            child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          itemCount: _msgs.length + (_loading ? 1 : 0),
          itemBuilder: (_, i) {
            if (_loading && i == _msgs.length) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _buildBubble(_msgs[i]);
          },
        )),
        if (_loadingHistory)
          const Padding(
              padding: EdgeInsets.all(8), child: CircularProgressIndicator())
        else ...[
          if (_currentSuggestions.isNotEmpty) _buildSuggestions(),
          _buildInput(),
        ],
      ]),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildSuggestions() => Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _currentSuggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _suggest(_currentSuggestions[i]),
        ),
      );

  Widget _suggest(String text) => GestureDetector(
        onTap: () {
          _sendMsg(text);
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
          child: Text(text,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
        ),
      );

  Future<void> _sendMsg(String text) async {
    final history = _msgs
        .map((m) => {
              'role': (m['isMe'] as bool) ? 'user' : 'assistant',
              'content': m['text'] as String,
            })
        .toList();

    setState(() {
      _msgs.add({'text': text, 'isMe': true});
      _loading = true;
    });
    _scrollToBottom();

    final svc = context.read<AppServices>();
    final skill = _skillFocus;
    final taskContext = skill != null
        ? {
            'focus': 'skill_exploration',
            'skill_name': skill.skillName,
            'skill_level': skill.levelLabel,
            'relevance_score': skill.score.round(),
          }
        : null;
    final userContext = _mlSession?.toUserContext();
    final threadKey = skill?.threadKey ?? MentorGeneralChatArgs.threadKey;

    try {
      final result = await svc.ai.mentorChat(
        question: text,
        history: history,
        taskContext: taskContext,
        userContext: userContext,
        threadKey: threadKey,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        final reply = result.data!;
        setState(() {
          _msgs.add({
            'text': reply.reply,
            'isMe': false,
            if (reply.usedMlModel) 'mlLabel': _mlLabel(reply.ml),
          });
          if (reply.suggestions.isNotEmpty) {
            _currentSuggestions = reply.suggestions;
          }
          _loading = false;
        });
        _scrollToBottom();
      } else {
        if (!mounted) return;
        setState(() {
          _msgs.add({
            'text': 'Sorry, I could not get a response: ${result.error}',
            'isMe': false,
          });
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add({
          'text': "I'm having trouble connecting right now. Please try again.",
          'isMe': false,
        });
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  String? _mlLabel(Map<String, dynamic> ml) {
    final rating = ml['predicted_rating'];
    final label = ml['performance_label']?.toString();
    if (rating == null) return null;
    return 'Teamify ML · $rating/5${label != null ? ' ($label)' : ''}';
  }

  Widget _buildBubble(Map m) {
    final isMe = m['isMe'] as bool;
    final mlLabel = m['mlLabel']?.toString();
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isMe ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m['text'] as String,
                style: TextStyle(
                    color: isMe ? Colors.white : AppColors.textPrimary,
                    fontSize: 13)),
            if (mlLabel != null && mlLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(mlLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white70 : AppColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInput() => Material(
        elevation: 6,
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SafeArea(
              top: false,
              child: Row(children: [
                Expanded(
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(24)),
                        child: TextField(
                            controller: _ctrl,
                            enabled: !_loading,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (text) {
                              final t = text.trim();
                              if (t.isNotEmpty && !_loading) {
                                _ctrl.clear();
                                _sendMsg(t);
                              }
                            },
                            decoration: const InputDecoration(
                                hintText: 'Ask your mentor anything...',
                                border: InputBorder.none)))),
                const SizedBox(width: 8),
                IconButton(
                    icon: Icon(Icons.send,
                        color: _loading
                            ? AppColors.textSecondary
                            : AppColors.primary),
                    onPressed: _loading
                        ? null
                        : () {
                            if (_ctrl.text.isNotEmpty) {
                              final t = _ctrl.text.trim();
                              _ctrl.clear();
                              _sendMsg(t);
                            }
                          }),
              ])),
        ),
      );

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }
}
