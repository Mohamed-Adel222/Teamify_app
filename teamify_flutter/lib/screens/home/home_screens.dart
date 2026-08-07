import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../core/network/api_result.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../core/session/session_controller.dart';
import '../../data/models/api_helpers.dart';
import '../../data/models/models.dart' as api;
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import '../../config/app_config.dart';
import '../../core/notifications/notification_actions.dart';
import '../../core/localization/app_localizations.dart';
import '../../data/models/notification_preferences_model.dart';
import '../../data/demo/demo_notifications_data.dart';
import '../../widgets/notification_widgets.dart';
import '../../data/models/university_option_model.dart';
import '../project/project_screens.dart';

Map<String, int> _homeDashboardCounts(Map<String, dynamic> dash) {
  final stats = dash['stats'] as Map<String, dynamic>? ?? {};
  return {
    'activeProjects': (stats['active_projects_count'] as num?)?.toInt() ??
        (stats['accessible_projects_count'] as num?)?.toInt() ??
        0,
    'completed': (stats['completed_tasks'] as num?)?.toInt() ?? 0,
    'inProgress': (stats['in_progress_tasks'] as num?)?.toInt() ?? 0,
  };
}

class FreelancerHomeScreen extends StatefulWidget {
  const FreelancerHomeScreen({super.key});

  @override
  State<FreelancerHomeScreen> createState() => _FreelancerHomeScreenState();
}

class _FreelancerHomeScreenState extends State<FreelancerHomeScreen> {
  int _dashVersion = 0;
  int _notifVersion = 0;
  int _liveUnread = -1;
  StreamSubscription<int>? _unreadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindUnreadStream());
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  void _bindUnreadStream() {
    _unreadSub ??= context
        .read<AppServices>()
        .notifications
        .unreadCountStream
        .listen((count) {
      if (mounted) setState(() => _liveUnread = count);
    });
  }

  void _bumpHomeData() {
    final userId = context.read<SessionController>().currentUser?.id;
    context.read<AppServices>().home.invalidateDashboard(userId: userId);
    setState(() {
      _dashVersion++;
      _notifVersion++;
    });
  }

  Future<Map<String, dynamic>> _loadDashboard() {
    final userId = context.read<SessionController>().currentUser?.id;
    return context
        .read<AppServices>()
        .home
        .getDashboard(userId: userId, forceRefresh: true)
        .unwrap();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final sysDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secColor =
        sysDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _bumpHomeData();
          },
          child: RepositoryLoader<Map<String, dynamic>>(
            key: ValueKey(_dashVersion),
            load: _loadDashboard,
            builder: (context, dash) {
              final counts = _homeDashboardCounts(dash);
              final atRisk = dash['at_risk_tasks'] as List<dynamic>? ?? [];
              final unread =
                  (dash['unread_notifications'] as num?)?.toInt() ?? 0;
              final badgeUnread = _liveUnread >= 0 ? _liveUnread : unread;
              final activeCount = counts['activeProjects']!;
              final completed = counts['completed']!;
              final inProg = counts['inProgress']!;

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(loc?.translate('welcome_back') ?? 'Welcome Back',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: onSurface)),
                          const SizedBox(height: 2),
                          Text(loc?.translate('overview_sub') ?? "Here's your overview for today",
                              style: TextStyle(color: secColor, fontSize: 13)),
                        ],
                      ),
                      NotificationBellBadge(
                        iconColor: onSurface,
                        iconSize: 26,
                        onTap: () async {
                          await Navigator.pushNamed(context, R.notifications);
                          if (!mounted) return;
                          _bumpHomeData();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _miniStat(
                          Icons.access_time_outlined,
                          '$activeCount',
                          loc?.translate('active_projects') ?? 'Active Projects',
                          AppColors.primary),
                      const SizedBox(width: 12),
                      _miniStat(
                          Icons.check_circle_outline,
                          '$completed',
                          loc?.translate('tasks_done') ?? 'Tasks Done',
                          AppColors.success),
                      const SizedBox(width: 12),
                      _miniStat(
                          Icons.flag_outlined,
                          '$inProg',
                          loc?.translate('in_progress') ?? 'In progress',
                          AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AIBanner(
                    title: loc?.translate('workload_overview') ?? 'Workload overview',
                    subtitle: atRisk.isNotEmpty
                        ? '${atRisk.length} tasks flagged as at-risk — review due dates in Tasks.'
                        : 'No at-risk tasks on your latest dashboard sync.',
                    badge: badgeUnread > 0 ? '$badgeUnread unread' : '',
                    onTap: () => Navigator.pushNamed(context, R.aiInsights),
                  ),
                  const SizedBox(height: 10),
                  TSectionHeader(
                      title:
                          loc?.translate('quick_actions') ?? 'Quick Actions'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 100,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _quickAction(
                            context,
                            loc?.translate('new_project') ?? 'New Project',
                            'Start project',
                            Icons.create_new_folder_outlined,
                            AppColors.primary,
                            R.addProject,
                            isDark: true),
                        const SizedBox(width: 12),
                        _quickAction(
                            context,
                            loc?.translate('new_task') ?? 'New Task',
                            loc?.translate('create_quickly') ?? 'Create quickly',
                            Icons.add_task,
                            Colors.white,
                            R.addTask),
                        const SizedBox(width: 12),
                        _quickAction(
                            context,
                            loc?.translate('teams') ?? 'Teams',
                            loc?.translate('manage_groups') ?? 'Manage groups',
                            Icons.groups_outlined,
                            Colors.white,
                            R.teamsList),
                        const SizedBox(width: 12),
                        _quickAction(
                            context,
                            loc?.translate('members') ?? 'Members',
                            loc?.translate('find_experts') ?? 'Find experts',
                            Icons.person_search_outlined,
                            Colors.white,
                            R.search),
                        const SizedBox(width: 12),
                        _quickAction(
                            context,
                            loc?.translate('meetings') ?? 'Meetings',
                            loc?.translate('ai_smart_sync') ?? 'AI Smart Sync',
                            Icons.videocam_outlined,
                            Colors.white,
                            R.meeting),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TSectionHeader(
                      title: loc?.translate('recent_activity') ?? 'Recent Activity'),
                  const SizedBox(height: 12),
                  _HomeRecentActivityList(
                    key: ValueKey(_notifVersion),
                    onUpdated: _bumpHomeData,
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar:
          TBottomNav(current: 0, onTap: (i) => handleRoleNav(context, i)),
    );
  }

  Widget _miniStat(IconData icon, String value, String label, Color color) {
    return Builder(builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final onSurface = Theme.of(ctx).colorScheme.onSurface;
      final secColor =
          isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

      return Expanded(
        child: TCard(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: onSurface)),
              Text(label,
                  style: TextStyle(fontSize: 10, color: secColor),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    });
  }

  Widget _quickAction(BuildContext context, String title, String sub,
      IconData icon, Color color, String route,
      {bool isDark = false}) {
    final sysDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.primary
        : (sysDark
            ? const Color(0xFF1E293B)
            : (color == Colors.white ? Colors.white : color));
    final iconColor = isDark
        ? Colors.white
        : (sysDark ? AppColors.accent : AppColors.primary);
    final textColor = isDark
        ? Colors.white
        : (sysDark ? AppColors.darkTextPrimary : AppColors.textPrimary);
    final subColor = isDark
        ? Colors.white70
        : (sysDark ? AppColors.darkTextSecondary : AppColors.textSecondary);
    final borderColor = isDark
        ? null
        : Border.all(color: sysDark ? AppColors.darkBorder : AppColors.border);

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: borderColor,
          boxShadow: isDark
              ? [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(height: 4),
              Text(title,
                  style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              Text(sub, style: TextStyle(color: subColor, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeammateRecommendation {
  final api.ApiUser user;
  final double matchPercent;
  final List<String> highlightSkills;
  final String experienceLevel;

  const _TeammateRecommendation({
    required this.user,
    required this.matchPercent,
    required this.highlightSkills,
    this.experienceLevel = '',
  });
}

// ── Search Screen ─────────────────────────────────────────────────────────────
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '', _tab = 'All';
  List<api.ApiProject> _remoteProjects = const [];
  List<api.ApiUser> _remoteUsers = const [];
  List<api.ApiTask> _remoteTasks = const [];
  Object? _loadError;
  bool _loadingSuggestions = true;
  final Map<String, String> _connectStates = {};

  String _getConnectState(String uid) => _connectStates[uid] ?? 'Connect';

  void _toggleConnectState(String uid) {
    setState(() {
      final current = _getConnectState(uid);
      if (current == 'Connect') {
        _connectStates[uid] = 'Request Sent';
      } else if (current == 'Request Sent') {
        _connectStates[uid] = 'Connected';
      } else {
        _connectStates[uid] = 'Connect';
      }
    });
  }

  void _sendDirectMessage(api.ApiUser user) {
    Navigator.pushNamed(context, R.directChat, arguments: user);
  }

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  String _projectName(String projectId) {
    if (projectId.isEmpty) return '';
    for (final p in _remoteProjects) {
      if (p.id == projectId) return p.name;
    }
    return '';
  }

  bool _isSearchableTeammate(api.ApiUser u) {
    if (u.id.isEmpty) return false;
    final currentUserId =
        context.read<SessionController>().currentUser?.id ?? '';
    if (currentUserId.isNotEmpty && u.id == currentUserId) return false;
    final dn = u.displayName.toLowerCase();
    final email = u.email.toLowerCase();
    if (dn.startsWith('blacklist_') || dn.startsWith('guest')) return false;
    if (email.contains('blacklist') || email.startsWith('guest')) return false;
    return true;
  }

  List<api.ApiUser> get _browsableUsers =>
      _remoteUsers.where(_isSearchableTeammate).toList();

  List<api.ApiUser> get _myUniversityUsers {
    final me = context.read<SessionController>().currentUser;
    if (me?.universityName.isEmpty ?? true) return const [];
    final myNorm =
        UniversityOption.normalizeUniversityName(me!.universityName);
    return _browsableUsers.where((u) {
      if (u.universityName.isEmpty) return false;
      return UniversityOption.normalizeUniversityName(u.universityName) ==
          myNorm;
    }).toList();
  }

  api.ApiUser? _userById(String id) {
    for (final u in _remoteUsers) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<void> _showBestRecommendedUsers() async {
    final session = context.read<SessionController>();
    final meId = session.currentUser?.id ?? '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scroll) => FutureBuilder<List<_TeammateRecommendation>>(
          future: _fetchBestRecommendations(meId),
          builder: (context, snap) {
            final recs = snap.data ?? const [];
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Best recommended teammates',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'AI-ranked by skills, experience & performance',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (snap.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snap.hasError)
                  TCard(
                    child: Text(
                      snap.error.toString().replaceFirst('Exception: ', ''),
                      style: const TextStyle(color: AppColors.error),
                    ),
                  )
                else if (recs.isEmpty)
                  const TCard(
                    child: Text(
                      'No recommendations yet. Add skills to your profile and complete tasks to improve matches.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                else
                  ...recs.map((r) => _bestRecommendCard(r)),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<List<_TeammateRecommendation>> _fetchBestRecommendations(
    String meId,
  ) async {
    final session = context.read<SessionController>();
    final skills = session.currentUser?.skills ?? const <String>[];
    final result = await context.read<AppServices>().ai.recommendTeammates({
      'user_id': meId,
      'skills': skills,
    }, topN: 5).unwrap();

    final raw = result['recommendations'] ??
        result['teammates'] ??
        result['users'] ??
        result['data'];
    if (raw is! List) return const [];

    final out = <_TeammateRecommendation>[];
    for (final item in raw.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      final uid = map['user_id']?.toString() ?? '';
      if (uid.isEmpty || uid == meId) continue;

      final existing = _userById(uid);
      final user = existing ??
          api.ApiUser.fromJson({
            'id': uid,
            'display_name': map['display_name'],
            'full_name': map['full_name'],
            'user_type': map['user_type'],
            'professional_field': map['professional_field'],
            'experience_level': map['experience_level'],
            'skills': map['skills'],
          });
      if (!_isSearchableTeammate(user)) continue;

      final score = (map['match_percent'] as num?)?.toDouble() ??
          ((map['similarity_score'] as num?)?.toDouble() ?? 0) * 100;
      final recSkills = (map['skills'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          user.skills;

      out.add(_TeammateRecommendation(
        user: user,
        matchPercent: score.clamp(0, 100),
        highlightSkills: recSkills.take(6).toList(),
        experienceLevel: map['experience_level']?.toString() ?? '',
      ));
    }
    return out;
  }

  Widget _aiBestPicksBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TCard(
      margin: const EdgeInsets.only(bottom: 16),
      onTap: _showBestRecommendedUsers,
      color: isDark
          ? AppColors.primary.withValues(alpha: 0.15)
          : AppColors.primary.withValues(alpha: 0.06),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'See best AI teammate picks',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Tap for top matches based on your profile',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.keyboard_arrow_up, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _bestRecommendCard(_TeammateRecommendation rec) {
    final u = rec.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textPrimary;
    final secColor = isDark ? Colors.white70 : AppColors.textSecondary;

    return TCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () {
        Navigator.pop(context);
        _showTeammateProfile(u);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TAvatar(initials: u.initials, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.primaryName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    Text(
                      u.displayRole,
                      style: TextStyle(
                        fontSize: 12,
                        color: secColor,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    '${rec.matchPercent.round()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'match',
                    style: TextStyle(
                      fontSize: 11,
                      color: secColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (rec.highlightSkills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rec.highlightSkills
                  .map(
                    (s) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        s,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.accent : AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (rec.experienceLevel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                rec.experienceLevel,
                style: TextStyle(
                  fontSize: 11,
                  color:
                      isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showTeammateProfile(api.ApiUser u) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, scroll) => FutureBuilder<api.ApiUser?>(
            future: context
                .read<AppServices>()
                .users
                .getPublicProfile(u.id)
                .then((r) => r.data),
            builder: (context, snap) {
              final p = snap.data ?? u;
              final handle = p.displayName.isNotEmpty &&
                      p.displayName.toLowerCase() != 'user'
                  ? '@${p.displayName}'
                  : null;

              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                  Row(
                    children: [
                      TAvatar(initials: p.initials, radius: 32),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.primaryName,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (handle != null)
                              Text(
                                handle,
                                style: TextStyle(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            const SizedBox(height: 6),
                            TChip(label: p.displayRole),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (snap.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    if (p.bio.isNotEmpty) ...[
                      _profileSectionTitle('About'),
                      _profileInfoRow(Icons.info_outline, 'Bio', p.bio),
                    ],
                    _profileSectionTitle('Skills'),
                    _profileSkillsSection(p.skills),
                    _profileSectionTitle('Profile'),
                    _profileInfoRow(
                      Icons.person_outline,
                      'Account type',
                      p.userType.isNotEmpty
                          ? p.userType[0].toUpperCase() +
                              p.userType.substring(1)
                          : p.displayRole,
                    ),
                    if (p.professionalField.isNotEmpty)
                      _profileInfoRow(
                        Icons.category_outlined,
                        'Professional field',
                        p.professionalField,
                      ),
                    if (p.experienceLevel.isNotEmpty)
                      _profileInfoRow(
                        Icons.trending_up,
                        'Experience level',
                        p.experienceLevel,
                      ),
                    if (p.availability.isNotEmpty)
                      _profileInfoRow(
                        Icons.schedule_outlined,
                        'Availability',
                        p.availability,
                      ),
                    if (p.memberExperienceYears > 0)
                      _profileInfoRow(
                        Icons.history,
                        'Years of experience',
                        '${p.memberExperienceYears}',
                      ),
                    if (p.isStudent) ...[
                      _profileSectionTitle('Education'),
                      if (p.major.isNotEmpty)
                        _profileInfoRow(
                          Icons.school_outlined,
                          'Major',
                          p.major,
                        ),
                      if (p.currentLevel.isNotEmpty)
                        _profileInfoRow(
                          Icons.grade_outlined,
                          'Current level',
                          p.currentLevel,
                        ),
                      if (p.lookingForTeam != null)
                        _profileInfoRow(
                          Icons.group_add_outlined,
                          'Looking for team',
                          p.lookingForTeam! ? 'Yes' : 'No',
                        ),
                    ],
                    if (p.reasonForJoining.isNotEmpty)
                      _profileInfoRow(
                        Icons.flag_outlined,
                        'Reason for joining',
                        p.reasonForJoining,
                      ),
                    if (p.tasksCompleted > 0 ||
                        p.qualityScore > 0 ||
                        p.attendanceRate > 0 ||
                        p.memberOnTimeRate > 0) ...[
                      _profileSectionTitle('Performance'),
                      if (p.tasksCompleted > 0)
                        _profileInfoRow(
                          Icons.task_alt_outlined,
                          'Tasks completed',
                          '${p.tasksCompleted}',
                        ),
                      if (p.qualityScore > 0)
                        _profileInfoRow(
                          Icons.star_outline,
                          'Quality score',
                          '${(p.qualityScore * 5).toStringAsFixed(1)} / 5',
                        ),
                      if (p.attendanceRate > 0)
                        _profileInfoRow(
                          Icons.event_available_outlined,
                          'Attendance rate',
                          '${(p.attendanceRate * 100).round()}%',
                        ),
                      if (p.memberOnTimeRate > 0)
                        _profileInfoRow(
                          Icons.timer_outlined,
                          'On-time rate',
                          '${(p.memberOnTimeRate * 100).round()}%',
                        ),
                    ],
                    _profileSectionTitle('Portfolio'),
                    _profilePortfolioSection(p),
                    _profileSectionTitle('CV & Resume'),
                    _profileCvSection(p),
                    _profileSectionTitle('Previous Projects'),
                    _profilePreviousProjectsSection(p),
                    if (p.id !=
                        (context.read<SessionController>().currentUser?.id ??
                            '')) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setSheetState(() {
                                  _toggleConnectState(p.id);
                                });
                              },
                              icon: Icon(
                                _getConnectState(p.id) == 'Connected'
                                    ? Icons.check
                                    : _getConnectState(p.id) == 'Request Sent'
                                        ? Icons.hourglass_top
                                        : Icons.person_add_outlined,
                                size: 18,
                              ),
                              label: Text(_getConnectState(p.id)),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                _sendDirectMessage(p);
                              },
                              icon: const Icon(Icons.chat_bubble_outline,
                                  size: 18),
                              label: const Text('Send Message'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _profileSectionTitle(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _profileSkillsSection(List<String> skills) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (skills.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'No skills listed yet.',
          style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: skills
            .map(
              (skill) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? AppColors.accent.withValues(alpha: 0.4)
                        : AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  skill,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.accent : AppColors.primary,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _profilePortfolioSection(api.ApiUser p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.link, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p.primaryName}\'s Portfolio',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    'github.com/${p.displayName.isNotEmpty ? p.displayName : 'user'}',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new,
                size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _profileCvSection(api.ApiUser p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.picture_as_pdf,
                  color: AppColors.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p.primaryName}_Resume.pdf',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Text(
                    'PDF Document · Updated recently',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Downloading ${p.primaryName}\'s CV...')),
                );
              },
              icon: const Icon(Icons.download, size: 14),
              label: const Text('CV', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profilePreviousProjectsSection(api.ApiUser p) {
    final mockProjects = [
      {
        'name': 'Teamify Mobile App',
        'role': 'Lead Developer',
        'status': 'Completed',
        'progress': 100
      },
      {
        'name': 'AI Smart Sync Engine',
        'role': 'Contributor',
        'status': 'In Progress',
        'progress': 85
      },
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: mockProjects.map((item) {
          final progress = (item['progress'] as int) / 100.0;
          return TCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item['name'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    TChip(label: item['status'] as String),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Role: ${item['role']}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${item['progress']}%',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _profileInfoRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTaskDetail(api.ApiTask task) async {
    if (task.id.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final svc = context.read<AppServices>();
      final taskResult = await svc.tasks.getTask(task.id);
      if (!mounted) return;
      await taskResult.when(
        success: (fullTask) async {
          final pid = fullTask.projectId.isNotEmpty
              ? fullTask.projectId
              : task.projectId;
          if (pid.isEmpty) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Task has no linked project.')),
            );
            return;
          }
          final projectResult = await svc.projects.getProject(pid);
          if (!mounted) return;
          await projectResult.when(
            success: (project) async {
              final userId =
                  context.read<SessionController>().currentUser?.id ?? '';
              final isOwner =
                  project.ownerId.isNotEmpty && project.ownerId == userId;
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskDetailScreen(
                    initialTask: fullTask.toDisplayModel(),
                    projectId: pid,
                    isOwner: isOwner,
                  ),
                ),
              );
            },
            failure: (e) {
              messenger.showSnackBar(
                SnackBar(content: Text(e), backgroundColor: AppColors.error),
              );
            },
          );
        },
        failure: (e) {
          messenger.showSnackBar(
            SnackBar(content: Text(e), backgroundColor: AppColors.error),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _loadSuggestions() async {
    setState(() {
      _loadingSuggestions = true;
      _loadError = null;
    });
    try {
      final services = context.read<AppServices>();
      if (AppConfig.isDemoMode) {
        final userResult = await services.search.users('');
        final users = userResult.data ?? <api.ApiUser>[];
        if (!mounted) return;
        setState(() {
          _remoteProjects = const [];
          _remoteUsers = users;
          _remoteTasks = const [];
          _loadError = null;
          _loadingSuggestions = false;
        });
        return;
      }
      final projectsRes = await services.search.projects('');
      final usersRes = await services.search.users('');
      final projects = projectsRes.data ?? <api.ApiProject>[];
      final users = usersRes.data ?? <api.ApiUser>[];

      final allTasks = <api.ApiTask>[];
      if (projects.isNotEmpty) {
        final taskResults = await Future.wait(
          projects.map(
            (p) => services.tasks.listTasks(
              projectId: p.id,
              forceRefresh: false,
            ),
          ),
        );
        for (final r in taskResults) {
          r.when(
            success: (tasks) => allTasks.addAll(tasks),
            failure: (_) {},
          );
        }
        allTasks.sort((a, b) {
          final ad = a.dueDate;
          final bd = b.dueDate;
          if (ad.isEmpty && bd.isEmpty) return a.title.compareTo(b.title);
          if (ad.isEmpty) return 1;
          if (bd.isEmpty) return -1;
          return ad.compareTo(bd);
        });
      }

      if (!mounted) return;
      setState(() {
        _remoteProjects = projects;
        _remoteUsers = users;
        _remoteTasks = allTasks;
        _loadError = null;
        _loadingSuggestions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('Exception: ', '');
        _loadingSuggestions = false;
      });
    }
  }

  List<Map<String, dynamic>> get _results {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    final r = <Map<String, dynamic>>[];
    if (_tab == 'All' || _tab == 'Projects') {
      for (final p in _remoteProjects) {
        if (p.name.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q)) {
          r.add({
            'type': 'Project',
            'title': p.name,
            'sub': p.category,
            'icon': Icons.folder_outlined,
            'project': p,
          });
        }
      }
    }
    if (_tab == 'All' || _tab == 'Teammates' || _tab == 'My University') {
      final sourceUsers =
          _tab == 'My University' ? _myUniversityUsers : _browsableUsers;
      for (final u in sourceUsers) {
        final name = u.primaryName.toLowerCase();
        final display = u.displayName.toLowerCase();
        final field = u.professionalField.toLowerCase();
        final major = u.major.toLowerCase();
        final skills = u.skills.join(' ').toLowerCase();
        if (name.contains(q) ||
            display.contains(q) ||
            field.contains(q) ||
            major.contains(q) ||
            skills.contains(q)) {
          r.add({
            'type': 'Person',
            'title': u.primaryName,
            'sub': u.displayRole,
            'icon': Icons.person_outline,
            'user': u,
          });
        }
      }
    }
    if (_tab == 'All' || _tab == 'Tasks') {
      for (final t in _remoteTasks) {
        if (t.title.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q) ||
            t.status.toLowerCase().contains(q)) {
          final projectName = _projectName(t.projectId);
          r.add({
            'type': 'Task',
            'title': t.title,
            'sub': projectName.isNotEmpty
                ? 'In $projectName'
                : (t.status.isNotEmpty ? t.status : 'Task'),
            'icon': Icons.check_circle_outline,
            'task': t,
          });
        }
      }
    }
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final border = Theme.of(context).dividerColor;
    final secColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    final me = context.watch<SessionController>().currentUser;
    final hasUniversityFilter =
        me?.isStudent == true && (me?.universityName.isNotEmpty ?? false);

    final tabs = [
      'All',
      if (hasUniversityFilter) 'My University',
      'Teammates',
      'Projects',
      'Tasks',
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: surface,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
              hintText: 'Search name or skill...',
              hintStyle: TextStyle(color: secColor),
              border: InputBorder.none),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _ctrl.clear();
                  setState(() => _query = '');
                }),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: tabs.map((t) {
                  final sel = _tab == t;
                  return GestureDetector(
                    onTap: () => setState(() => _tab = t),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.primary
                            : (isDark ? const Color(0xFF1E293B) : Colors.white),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: sel ? AppColors.primary : border),
                      ),
                      child: Text(t,
                          style: TextStyle(
                              color: sel ? Colors.white : secColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: _loadError != null && !AppConfig.isDemoMode
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Unable to load search data',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: secColor)),
                          const SizedBox(height: 16),
                          TextButton(
                              onPressed: _loadSuggestions,
                              child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : _loadingSuggestions
                    ? const Center(child: CircularProgressIndicator())
                    : _query.isEmpty
                        ? _buildSuggestions()
                        : _results.isEmpty
                            ? Center(
                                child: Text('No results for "$_query"',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary)))
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _results.length,
                                itemBuilder: (_, i) {
                                  final r = _results[i];
                                  final user = r['user'] as api.ApiUser?;
                                  if (user != null) {
                                    return _personCard(user);
                                  }
                                  final task = r['task'] as api.ApiTask?;
                                  final project =
                                      r['project'] as api.ApiProject?;
                                  return TCard(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(14),
                                    onTap: task != null
                                        ? () => _openTaskDetail(task)
                                        : project != null
                                            ? () => Navigator.pushNamed(
                                                  context,
                                                  R.projectDetails,
                                                  arguments:
                                                      project.toDisplayModel(),
                                                )
                                            : null,
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.1),
                                              shape: BoxShape.circle),
                                          child: Icon(r['icon'] as IconData,
                                              color: AppColors.primary,
                                              size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(r['title'] as String,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isDark
                                                          ? Colors.white
                                                          : AppColors
                                                              .textPrimary)),
                                              Text(r['sub'],
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: isDark
                                                          ? Colors.white70
                                                          : AppColors
                                                              .textSecondary)),
                                            ],
                                          ),
                                        ),
                                        TChip(label: r['type'] as String),
                                      ],
                                    ),
                                  );
                                },
                              ),
          ),
        ],
      ),
      bottomNavigationBar:
          TBottomNav(current: 1, onTap: (i) => handleRoleNav(context, i)),
    );
  }

  Widget _buildSuggestions() {
    if (_tab == 'Projects') {
      final projects = _remoteProjects.map((p) => p.toDisplayModel()).toList();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TSectionHeader(title: 'Suggested Projects'),
          const SizedBox(height: 12),
          ...projects.map((p) => _projectCard(p)),
        ],
      );
    } else if (_tab == 'My University') {
      final users = _myUniversityUsers;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TSectionHeader(title: 'Students From Your University'),
          const SizedBox(height: 12),
          if (users.isEmpty)
            TCard(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  const Icon(Icons.school_outlined,
                      size: 40, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  const Text(
                    'No students from your university are available yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _tab = 'All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('View All'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            )
          else
            ...users.map(_personCard),
        ],
      );
    } else if (_tab == 'Teammates') {
      final users = _browsableUsers;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _aiBestPicksBanner(),
          const TSectionHeader(title: 'Recommended Teammates'),
          const SizedBox(height: 12),
          if (users.isEmpty)
            const TCard(
              child: Text(
                'No teammates to show yet.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ...users.map(_personCard),
        ],
      );
    } else if (_tab == 'Tasks') {
      final suggested = _remoteTasks.take(10).toList();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TSectionHeader(title: 'Suggested Tasks'),
          const SizedBox(height: 12),
          if (suggested.isEmpty)
            const TCard(
              child: Text(
                'No tasks yet. Create tasks in your projects to see them here.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ...suggested.map(_taskCard),
        ],
      );
    } else {
      // 'All' tab
      final projects = _remoteProjects.map((p) => p.toDisplayModel()).toList();
      final users = _browsableUsers;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TSectionHeader(title: 'Suggested Projects'),
          const SizedBox(height: 12),
          ...projects.take(2).map((p) => _projectCard(p)),
          const SizedBox(height: 24),
          _aiBestPicksBanner(),
          const TSectionHeader(title: 'Recommended People'),
          const SizedBox(height: 12),
          ...users.take(3).map(_personCard),
        ],
      );
    }
  }

  Widget _projectCard(dynamic p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => Navigator.pushNamed(context, R.projectDetails, arguments: p),
      child: Row(
        children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.folder_outlined,
                  color: AppColors.primary, size: 16)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(p.name,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.textPrimary)),
                Text(p.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? Colors.white70 : AppColors.textSecondary)),
              ])),
          Icon(Icons.arrow_forward_ios,
              size: 14,
              color: isDark ? Colors.white54 : AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _personCard(api.ApiUser u) {
    final me = context.read<SessionController>().currentUser;
    final meId = me?.id ?? '';
    final isMe = u.id == meId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final myUniNorm = (me?.isStudent == true && me?.universityName.isNotEmpty == true)
        ? UniversityOption.normalizeUniversityName(me!.universityName)
        : '';
    final uUniNorm = u.universityName.isNotEmpty
        ? UniversityOption.normalizeUniversityName(u.universityName)
        : '';
    final isSameUni =
        myUniNorm.isNotEmpty && uUniNorm.isNotEmpty && myUniNorm == uUniNorm;

    return TCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => _showTeammateProfile(u),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TAvatar(initials: u.initials, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            u.primaryName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isSameUni) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: AppColors.success
                                      .withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified,
                                    size: 10, color: AppColors.success),
                                SizedBox(width: 3),
                                Text(
                                  'Same University',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      u.displayRole,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? Colors.white70 : AppColors.textSecondary,
                      ),
                    ),
                    if (u.universityName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.school_outlined,
                              size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              u.universityName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white70
                                    : AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (u.skills.isNotEmpty)
                      Text(
                        u.skillsSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : AppColors.textHint,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.end,
            children: [
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => _showTeammateProfile(u),
                  icon: const Icon(Icons.person_outline, size: 20),
                  label: const Text(
                    'View Profile',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (!isMe) ...[
                SizedBox(
                  height: 44,
                  width: 140,
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleConnectState(u.id),
                    icon: Icon(
                      _getConnectState(u.id) == 'Connected'
                          ? Icons.check
                          : _getConnectState(u.id) == 'Request Sent'
                              ? Icons.hourglass_top
                              : Icons.person_add_outlined,
                      size: 20,
                    ),
                    label: Text(
                      _getConnectState(u.id),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => _sendDirectMessage(u),
                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                    label: const Text(
                      'Message',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ] else
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Text(
                    '(You)',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : AppColors.textHint,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _taskCard(api.ApiTask t) {
    final projectName = _projectName(t.projectId);
    final due = t.dueDate.isNotEmpty ? 'Due: ${t.dueDate}' : 'No due date';
    final sub = projectName.isNotEmpty
        ? '$due · $projectName'
        : (t.status.isNotEmpty ? '$due · ${t.status}' : due);

    return TCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => _openTaskDetail(t),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

// ── Student Home ──────────────────────────────────────────────────────────────
class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.currentUser;
    final displayName = user?.fullName ?? user?.displayName ?? 'Student';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final bannerBg = isDark
        ? AppColors.primary.withValues(alpha: 0.15)
        : const Color(0xFFEEF4FF);
    final border = Theme.of(context).dividerColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(10),
          children: [
            Text('Welcome Back',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: onSurface)),
            Text("Here's your overview for today",
                style: TextStyle(color: secColor, fontSize: 13)),
            const SizedBox(height: 6),
            // Profile card
            TCard(
                child: Row(children: [
              Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle),
                  child: const Center(
                      child: Icon(Icons.person_outline,
                          color: AppColors.primary, size: 26))),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(displayName,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: onSurface,
                        fontSize: 15)),
                if (user?.universityName != null &&
                    user!.universityName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.school_outlined,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      user.universityName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: onSurface,
                      ),
                    ),
                    if (user.isCustomUniversity) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Custom',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ]),
                ],
                if (user?.email != null && user!.email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.email_outlined, size: 13, color: secColor),
                    const SizedBox(width: 4),
                    Text(user.email,
                        style: TextStyle(fontSize: 12, color: secColor)),
                  ]),
                ],
              ]),
            ])),
            const SizedBox(height: 6),
            RepositoryLoader<Map<String, dynamic>>(
              load: () {
                final userId =
                    context.read<SessionController>().currentUser?.id;
                return context
                    .read<AppServices>()
                    .home
                    .getDashboard(userId: userId, forceRefresh: true)
                    .unwrap();
              },
              builder: (context, dash) {
                final counts = _homeDashboardCounts(dash);
                final atRisk = dash['at_risk_tasks'] as List<dynamic>? ?? [];
                final activeCount = counts['activeProjects']!;
                final completed = counts['completed']!;
                final inProg = counts['inProgress']!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      _stat(Icons.book_outlined, '$activeCount', 'Active',
                          AppColors.primary),
                      const SizedBox(width: 10),
                      _stat(Icons.check_circle_outline, '$completed', 'Done',
                          AppColors.success),
                      const SizedBox(width: 10),
                      _stat(Icons.flag_outlined, '$inProg', 'Active tasks',
                          AppColors.warning),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: bannerBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.auto_awesome,
                                color: AppColors.primary, size: 18),
                            const SizedBox(width: 6),
                            Text('Workload pulse',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: onSurface)),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            atRisk.isNotEmpty
                                ? '${atRisk.length} tasks may need attention soon.'
                                : 'No at-risk tasks detected on your latest sync.',
                            style: TextStyle(fontSize: 13, color: secColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Text('Quick Actions',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: onSurface)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, R.search),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Find People',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        SizedBox(height: 4),
                        Text('Discover teammates & experts',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.people_outline,
                          color: Colors.white, size: 22),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, R.addProject),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFF3B6BB3),
                    borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New Project',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        SizedBox(height: 4),
                        Text('Start project',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.create_new_folder_outlined,
                          color: Colors.white, size: 22),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, R.addTask),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFF3B6BB3),
                    borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New Task',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        SizedBox(height: 4),
                        Text('Create quickly',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 22),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, R.projectDetails),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('View Projects',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: onSurface,
                                fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('See all active',
                            style: TextStyle(color: secColor, fontSize: 13)),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.book_outlined,
                        color: Color(0xFF3B6BB3), size: 26),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, R.search),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Find Teammates',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: onSurface,
                                fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Join a team',
                            style: TextStyle(color: secColor, fontSize: 13)),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.search,
                        color: Color(0xFF3B6BB3), size: 26),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Recent Activity',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: onSurface)),
            const SizedBox(height: 12),
            const _HomeRecentActivityList(),
          ],
        ),
      ),
      bottomNavigationBar:
          TBottomNav(current: 0, onTap: (i) => handleRoleNav(context, i)),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) {
    return Builder(builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final onSurface = Theme.of(ctx).colorScheme.onSurface;
      final secColor =
          isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

      return Expanded(
          child: TCard(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: onSurface)),
                Text(label, style: TextStyle(fontSize: 10, color: secColor)),
              ])));
    });
  }
}

// ── Notifications Screen ──────────────────────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final DemoNotificationStore _demoStore = DemoNotificationStore.instance;

  List<NotificationViewModel> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  String _searchQuery = '';
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _demoStore.addListener(_onDemoStoreChanged);
    _load();
  }

  @override
  void dispose() {
    _demoStore.removeListener(_onDemoStoreChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onDemoStoreChanged() {
    if (AppConfig.isDemoMode && mounted) {
      setState(() {
        _items = List.from(_demoStore.items);
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (AppConfig.isDemoMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _items = List.from(_demoStore.items);
        _loading = false;
      });
      return;
    }

    try {
      final list = await context
          .read<AppServices>()
          .notifications
          .listNotifications(forceRefresh: true)
          .unwrap();

      if (!mounted) return;
      setState(() {
        _items = list
            .map((apiNotif) => NotificationViewModel(apiNotification: apiNotif))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (AppConfig.isDemoMode) {
        setState(() {
          _items = List.from(_demoStore.items);
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _markReadLocally(String id) {
    if (AppConfig.isDemoMode) {
      _demoStore.markAsRead(id);
    } else {
      setState(() {
        _items = _items
            .map((item) => item.id == id
                ? item.copyWith(
                    apiNotification:
                        item.apiNotification.copyWith(isRead: true))
                : item)
            .toList();
      });
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      if (AppConfig.isDemoMode) {
        _demoStore.markAllRead();
      } else {
        await context.read<AppServices>().notifications.markAllRead().unwrap();
      }
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((item) => item.copyWith(
                apiNotification: item.apiNotification.copyWith(isRead: true)))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update notifications: $e')),
      );
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _toggleReadState(NotificationViewModel item) {
    if (AppConfig.isDemoMode) {
      _demoStore.toggleReadState(item.id);
    } else {
      _markReadLocally(item.id);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(item.isRead
            ? 'Marked as Unread'
            : 'Marked as Read'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _confirmDelete(NotificationViewModel item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notification'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              if (AppConfig.isDemoMode) {
                _demoStore.deleteNotification(item.id);
              } else {
                setState(() {
                  _items.removeWhere((n) => n.id == item.id);
                });
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notification deleted.'),
                  backgroundColor: AppColors.error,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  int get _unreadCount => _items.where((i) => !i.isRead).length;

  List<NotificationViewModel> get _filteredItems {
    final query = _searchQuery.toLowerCase().trim();

    return _items.where((item) {
      // 1. Filter by category / unread tab
      if (_filter == 'unread' && item.isRead) return false;

      if (_filter == 'invitations') {
        final isInvite = item.category == NotificationType.teamInvitation ||
            item.category == NotificationType.invitationAccepted ||
            item.category == NotificationType.invitationRejected;
        if (!isInvite) return false;
      } else if (_filter == 'tasks') {
        final isTask = item.category == NotificationType.taskAssigned ||
            item.category == NotificationType.taskUpdated ||
            item.category == NotificationType.deadlineReminder;
        if (!isTask) return false;
      } else if (_filter == 'messages') {
        final isMsg = item.category == NotificationType.directMessage ||
            item.category == NotificationType.chatMention;
        if (!isMsg) return false;
      } else if (_filter == 'teams') {
        final isTeam = item.category == NotificationType.roleChanged ||
            item.category == NotificationType.memberRemoved;
        if (!isTeam) return false;
      } else if (_filter == 'announcements') {
        if (item.category != NotificationType.adminAnnouncement) return false;
      } else if (_filter == 'system') {
        if (item.category != NotificationType.systemNotification) return false;
      }

      // 2. Search query match
      if (query.isNotEmpty) {
        final titleMatch = item.title.toLowerCase().contains(query);
        final bodyMatch = item.body.toLowerCase().contains(query);
        final projMatch =
            (item.relatedProjectName ?? '').toLowerCase().contains(query);
        final taskMatch =
            (item.relatedTaskName ?? '').toLowerCase().contains(query);
        final teamMatch =
            (item.relatedTeamName ?? '').toLowerCase().contains(query);
        final userMatch =
            (item.relatedUserName ?? '').toLowerCase().contains(query);
        final catMatch = item.category.label.toLowerCase().contains(query);

        return titleMatch ||
            bodyMatch ||
            projMatch ||
            taskMatch ||
            teamMatch ||
            userMatch ||
            catMatch;
      }

      return true;
    }).toList();
  }

  Map<String, List<NotificationViewModel>> _groupItemsByDate(
      List<NotificationViewModel> list) {
    final Map<String, List<NotificationViewModel>> grouped = {
      'Today': [],
      'Yesterday': [],
      'Earlier': [],
    };

    for (final item in list) {
      final raw = item.createdAt.toLowerCase();
      if (raw.contains('min') ||
          raw.contains('hour') ||
          raw.contains('just now') ||
          raw.contains('today')) {
        grouped['Today']!.add(item);
      } else if (raw.contains('1 day') || raw.contains('yesterday')) {
        grouped['Yesterday']!.add(item);
      } else {
        grouped['Earlier']!.add(item);
      }
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final loc = AppLocalizations.of(context);
    final visible = _filteredItems;
    final grouped = _groupItemsByDate(visible);

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
        title: Row(
          children: [
            Text(
              loc?.translate('notifications') ?? 'Notifications',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _unreadCount > 99 ? '99+' : '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Search Field ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  icon: const Icon(Icons.search,
                      size: 18, color: AppColors.textSecondary),
                  border: InputBorder.none,
                  hintText: 'Search notifications by title, task, team…',
                  hintStyle: const TextStyle(
                      fontSize: 12, color: AppColors.textHint),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _searchQuery = '';
                          }),
                        )
                      : null,
                ),
              ),
            ),
          ),

          // ── Category Filter Chips & Mark All Read Bar ─────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('all', 'All'),
                        const SizedBox(width: 6),
                        _filterChip('unread', 'Unread ($_unreadCount)'),
                        const SizedBox(width: 6),
                        _filterChip('invitations', 'Invitations'),
                        const SizedBox(width: 6),
                        _filterChip('tasks', 'Tasks'),
                        const SizedBox(width: 6),
                        _filterChip('messages', 'Messages'),
                        const SizedBox(width: 6),
                        _filterChip('teams', 'Teams'),
                        const SizedBox(width: 6),
                        _filterChip('announcements', 'Announcements'),
                        const SizedBox(width: 6),
                        _filterChip('system', 'System'),
                      ],
                    ),
                  ),
                ),
                if (_unreadCount > 0) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Mark all read',
                    onPressed: _markingAll ? null : _markAllRead,
                    icon: const Icon(Icons.done_all,
                        size: 20, color: AppColors.primary),
                  ),
                ],
              ],
            ),
          ),

          // ── Main Content Area: Skeleton, Empty State, or Grouped Cards ──────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _loading && _items.isEmpty
                  ? const NotificationSkeletonList(itemCount: 4)
                  : _error != null && _items.isEmpty
                      ? NotificationEmptyStateView(
                          title: 'Error Loading Notifications',
                          message: _error!,
                          icon: Icons.error_outline,
                          actionLabel: 'Retry',
                          onActionPressed: _load,
                        )
                      : visible.isEmpty
                          ? NotificationEmptyStateView(
                              title: _searchQuery.isNotEmpty
                                  ? 'No matching results'
                                  : _filter == 'unread'
                                      ? 'No unread notifications'
                                      : 'No notifications in this category',
                              message: _searchQuery.isNotEmpty
                                  ? 'No notifications matched "$_searchQuery". Try clearing search.'
                                  : 'You are all caught up for this view.',
                              icon: Icons.notifications_off_outlined,
                            )
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              children: [
                                for (final entry in grouped.entries)
                                  if (entry.value.isNotEmpty) ...[
                                    NotificationGroupHeader(title: entry.key),
                                    for (final item in entry.value)
                                      Dismissible(
                                        key: Key(item.id),
                                        background: Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 12, left: 16, right: 16),
                                          padding:
                                              const EdgeInsets.only(left: 20),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          alignment: Alignment.centerLeft,
                                          child: Row(
                                            children: [
                                              Icon(
                                                item.isRead
                                                    ? Icons
                                                        .mark_email_unread_outlined
                                                    : Icons
                                                        .mark_email_read_outlined,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                item.isRead
                                                    ? 'Mark Unread'
                                                    : 'Mark Read',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        secondaryBackground: Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 12, left: 16, right: 16),
                                          padding:
                                              const EdgeInsets.only(right: 20),
                                          decoration: BoxDecoration(
                                            color: AppColors.error,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          alignment: Alignment.centerRight,
                                          child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(Icons.delete_outline,
                                                  color: Colors.white),
                                            ],
                                          ),
                                        ),
                                        confirmDismiss: (dir) async {
                                          if (dir ==
                                              DismissDirection.startToEnd) {
                                            _toggleReadState(item);
                                            return false; // keep in list
                                          } else {
                                            _confirmDelete(item);
                                            return false;
                                          }
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 6),
                                          child: TCard(
                                            margin: EdgeInsets.zero,
                                            padding: const EdgeInsets.all(14),
                                            onTap: () {
                                              Navigator.pushNamed(
                                                context,
                                                R.notificationDetails,
                                                arguments: item,
                                              );
                                            },
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(10),
                                                  decoration: BoxDecoration(
                                                    color: item.color
                                                        .withValues(
                                                            alpha: 0.12),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(item.icon,
                                                      color: item.color,
                                                      size: 20),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              item.title,
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: theme
                                                                    .colorScheme
                                                                    .onSurface,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ),
                                                          if (!item.isRead)
                                                            Container(
                                                              width: 8,
                                                              height: 8,
                                                              decoration:
                                                                  const BoxDecoration(
                                                                color: AppColors
                                                                    .primary,
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        item.body,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: isDark
                                                              ? AppColors
                                                                  .darkTextSecondary
                                                              : AppColors
                                                                  .textSecondary,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        children: [
                                                          if (item.createdAt
                                                              .isNotEmpty)
                                                            Text(
                                                              formatRelativeTime(
                                                                  item.createdAt),
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11,
                                                                color: AppColors
                                                                    .textHint,
                                                              ),
                                                            ),
                                                          const Spacer(),
                                                          // Email Badge
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: item
                                                                      .emailDelivered
                                                                  ? AppColors
                                                                      .success
                                                                      .withValues(
                                                                          alpha:
                                                                              0.1)
                                                                  : theme
                                                                      .dividerColor
                                                                      .withValues(
                                                                          alpha:
                                                                              0.1),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Icon(
                                                                  item.emailDelivered
                                                                      ? Icons
                                                                          .mark_email_read_outlined
                                                                      : Icons
                                                                          .phonelink_ring_outlined,
                                                                  size: 10,
                                                                  color: item
                                                                          .emailDelivered
                                                                      ? AppColors
                                                                          .success
                                                                      : AppColors
                                                                          .textSecondary,
                                                                ),
                                                                const SizedBox(
                                                                    width: 4),
                                                                Text(
                                                                  item.emailDelivered
                                                                      ? 'Email Sent'
                                                                      : 'In-App Only',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize: 9,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: item
                                                                            .emailDelivered
                                                                        ? AppColors
                                                                            .success
                                                                        : AppColors
                                                                            .textSecondary,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(
                                                    Icons.chevron_right,
                                                    size: 18,
                                                    color: AppColors.textHint),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final sel = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

/// Recent notifications on the home dashboard (tap opens task details when linked).
class _HomeRecentActivityList extends StatelessWidget {
  const _HomeRecentActivityList({super.key, this.onUpdated});

  final VoidCallback? onUpdated;

  static const double _maxHeight = 180;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _maxHeight,
      child: RepositoryLoader<List<api.ApiNotification>>(
        load: () => context
            .read<AppServices>()
            .notifications
            .listNotifications(forceRefresh: true)
            .unwrap(),
        isEmpty: (items) => items.isEmpty,
        emptyMessage: 'No recent notifications',
        builder: (context, items) => ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length > 3 ? 3 : items.length,
          itemBuilder: (_, i) {
            final a = items[i];
            return TCard(
              margin: const EdgeInsets.only(bottom: 10),
              onTap: () => handleNotificationTap(
                context,
                a,
                onUpdated: onUpdated,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        a.createdAt.isNotEmpty
                            ? formatRelativeTime(a.createdAt)
                            : '',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.textHint,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
