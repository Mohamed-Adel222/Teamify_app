import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../core/course_link.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../core/network/api_result.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme_controller.dart';
import '../../core/localization/app_localizations.dart';
import '../../services/app_services.dart';
import '../../models/models.dart';
import '../../widgets/widgets.dart';
import '../../data/models/api_user.dart';
import '../../data/models/api_helpers.dart';
import '../../data/models/api_project.dart';
import '../../data/models/university_option_model.dart';
import '../../widgets/university_selector_widgets.dart';

// ── Profile stats parsing (GET /api/users/<id>/stats) ─────────────────────────
class ProfileDisplayStats {
  final String projects;
  final String tasksDone;
  final String score;
  final String location;
  final String joined;
  final String roleTitle;
  final num commitment;
  final num teamwork;
  final num quality;

  const ProfileDisplayStats({
    required this.projects,
    required this.tasksDone,
    required this.score,
    required this.location,
    required this.joined,
    required this.roleTitle,
    required this.commitment,
    required this.teamwork,
    required this.quality,
  });
}

int _profileInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString()) ?? 0;
}

String _profileFormatScore(dynamic v) {
  if (v == null) return '—';
  final n = v is num ? v.toDouble() : double.tryParse(v.toString());
  if (n == null || n <= 0) return '—';
  if (n == n.roundToDouble()) return '${n.round()}';
  return n.toStringAsFixed(1);
}

String _profileDefaultRole(ApiUser user, String fallback) {
  if (user.professionalField.isNotEmpty) return user.professionalField;
  if (user.experienceLevel.isNotEmpty) {
    return '${user.experienceLevel} ${user.displayRole}';
  }
  return fallback;
}

String _profileDefaultJoined(ApiUser user) {
  if (user.joinedAt.isEmpty) return 'Member';
  final dt = DateTime.tryParse(user.joinedAt);
  if (dt == null) return 'Member';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'Member since ${months[dt.month - 1]} ${dt.year}';
}

ProfileDisplayStats profileDisplayStats(
  ApiUser user,
  Map<String, dynamic> raw, {
  required String defaultRole,
  required String defaultLocation,
}) {
  final summary = raw['summary'] as Map<String, dynamic>? ?? {};
  final tasks = raw['tasks'] as Map<String, dynamic>? ?? {};
  final ratings = raw['ratings'] as Map<String, dynamic>? ?? {};
  final feedback = raw['feedback'] as Map<String, dynamic>? ?? {};
  final projects = raw['projects'] as Map<String, dynamic>? ?? {};
  final performance = raw['performance'] as Map<String, dynamic>? ?? {};

  final projectsCount = _profileInt(
    summary['projects'] ??
        summary['completed_projects'] ??
        projects['accessible_count'],
  );
  final tasksDone = _profileInt(
    summary['tasks_done'] ?? summary['completed_tasks'] ?? tasks['completed'],
  );

  dynamic scoreVal = summary['score'] ??
      summary['rating'] ??
      feedback['avg_rating'] ??
      ratings['average'];
  if (scoreVal == null && feedback['avg_quality'] != null) {
    scoreVal = feedback['avg_quality'];
  }

  final location = summary['location']?.toString().trim().isNotEmpty == true
      ? summary['location'].toString()
      : (user.availability.isNotEmpty ? user.availability : defaultLocation);

  final joined = summary['joined']?.toString().trim().isNotEmpty == true
      ? summary['joined'].toString()
      : _profileDefaultJoined(user);

  final roleTitle = summary['role_title']?.toString().trim().isNotEmpty == true
      ? summary['role_title'].toString()
      : _profileDefaultRole(user, defaultRole);

  final onTime = performance['on_time_rate'];
  final commitment = _profileInt(
    summary['commitment'] ?? (onTime is num ? onTime * 100 : null),
  );
  final teamwork = _profileInt(summary['teamwork']);
  final quality = _profileInt(
    summary['quality'] ??
        ((performance['quality_score'] as num?) != null
            ? (performance['quality_score'] as num) * 100
            : null),
  );

  return ProfileDisplayStats(
    projects: '$projectsCount',
    tasksDone: '$tasksDone',
    score: _profileFormatScore(scoreVal),
    location: location,
    joined: joined,
    roleTitle: roleTitle,
    commitment: commitment,
    teamwork: teamwork > 0 ? teamwork : commitment,
    quality: quality > 0 ? quality : commitment,
  );
}

// ── Profile Base Widget ───────────────────────────────────────────────────────
class _ProfileBase extends StatelessWidget {
  final String name, role, initials, email, location, joined;
  final String projects, tasksDone, score;
  final String? targetUserId;
  final bool isAdmin;
  final String? universityName;
  final bool isCustomUniversity;

  const _ProfileBase({
    required this.name,
    required this.role,
    required this.initials,
    required this.email,
    required this.location,
    required this.joined,
    required this.projects,
    required this.tasksDone,
    required this.score,
    this.targetUserId,
    this.isAdmin = false,
    this.universityName,
    this.isCustomUniversity = false,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = targetUserId ??
        (context.read<SessionController>().currentUser?.id ?? 'demo_user_me');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceBg = isDark ? const Color(0xFF1E293B) : AppColors.background;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text('Profile',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: onSurface)),
            Text('Manage your account',
                style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                    fontSize: 13)),
            const SizedBox(height: 16),
            TCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    TAvatar(initials: initials, radius: 28),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(name,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: onSurface,
                                  fontSize: 16)),
                          Text(role,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.textSecondary)),
                        ])),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, R.editProfile),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              color: surfaceBg,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('Edit Profile',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: onSurface,
                                  fontWeight: FontWeight.w500))),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  if (email.trim().isNotEmpty) ...[
                    _infoRow(context, Icons.email_outlined, email.trim()),
                    const SizedBox(height: 6),
                  ],
                  if (universityName != null &&
                      universityName!.trim().isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.school_outlined,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          universityName!.trim(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: onSurface,
                          ),
                        ),
                        if (isCustomUniversity) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
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
                      ],
                    ),
                    const SizedBox(height: 6),
                  ] else if (location.trim().isNotEmpty &&
                      location.trim() != 'University') ...[
                    _infoRow(
                        context, Icons.location_on_outlined, location.trim()),
                    const SizedBox(height: 6),
                  ],
                  if (joined.trim().isNotEmpty)
                    _infoRow(
                        context, Icons.calendar_today_outlined, joined.trim()),
                ])),
            const SizedBox(height: 12),
            Row(children: [
              _statBox(context, projects, 'Projects'),
              const SizedBox(width: 10),
              _statBox(context, tasksDone, 'Tasks Done'),
              const SizedBox(width: 10),
              _statBox(context, score, 'Score'),
            ]),
            const SizedBox(height: 14),
            _ProfileFeedbackSection(
              targetUserId: currentUserId,
              targetUserName: name,
            ),
            const SizedBox(height: 16),
            Text('Account',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: onSurface)),
            const SizedBox(height: 10),
            _menuTile(context, Icons.settings_outlined, 'Settings',
                onTap: () => Navigator.pushNamed(context, R.settings)),
            const SizedBox(height: 8),
            _menuTile(
                context, Icons.auto_fix_high_outlined, 'AI Resume Builder',
                onTap: () => Navigator.pushNamed(context, R.resumeBuilder)),
            const SizedBox(height: 8),
            _menuTile(context, Icons.folder_copy_outlined, 'My Projects',
                onTap: () => Navigator.pushNamed(context, R.projectsList)),
            if (!isAdmin) ...[
              const SizedBox(height: 8),
              _menuTile(context, Icons.history, 'Activity',
                  onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyActivityScreen(),
                        ),
                      )),
              const SizedBox(height: 8),
              _menuTile(context, Icons.gavel_outlined, 'File a Dispute',
                  onTap: () => showFileDisputeSheet(context)),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar:
          TBottomNav(current: 4, onTap: (i) => handleRoleNav(context, i)),
    );
  }

  Widget _infoRow(BuildContext ctx, IconData icon, String text) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final color =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 13, color: color)),
    ]);
  }

  Widget _statBox(BuildContext ctx, String value, String label) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E293B) : AppColors.background;
    final onSurface = Theme.of(ctx).colorScheme.onSurface;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: onSurface)),
          Text(label, style: TextStyle(fontSize: 11, color: secondary)),
        ]),
      ),
    );
  }

  Widget _menuTile(BuildContext ctx, IconData icon, String title,
      {required VoidCallback onTap, Color? color}) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E293B) : AppColors.background;
    final defaultColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final arrowColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 20, color: color ?? defaultColor),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: color ?? defaultColor))),
          Icon(Icons.arrow_forward_ios, size: 14, color: color ?? arrowColor),
        ]),
      ),
    );
  }
}

// ── Profile stats loader (fresh from API + Hive cache) ────────────────────────
class _ProfileStatsLoader extends StatefulWidget {
  final ApiUser user;
  final String defaultRole;
  final String defaultLocation;
  final bool isAdmin;
  final Widget Function(
    BuildContext context,
    ProfileDisplayStats stats,
    VoidCallback refresh,
    bool refreshing,
  ) builder;

  const _ProfileStatsLoader({
    required this.user,
    required this.defaultRole,
    required this.defaultLocation,
    required this.builder,
    this.isAdmin = false,
  });

  @override
  State<_ProfileStatsLoader> createState() => _ProfileStatsLoaderState();
}

class _ProfileStatsLoaderState extends State<_ProfileStatsLoader> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _load(forceRefresh: true));
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (AppConfig.isDemoMode) {
      setState(() {
        _stats = {
          'summary': {'projects_count': 5, 'tasks_done': 18, 'score': 4.8},
          'location': 'San Francisco, CA',
        };
        _loading = false;
        _refreshing = false;
        _error = null;
      });
      return;
    }
    setState(() {
      if (_stats == null) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });

    final users = context.read<AppServices>().users;
    final result = await users.getUserStats(
      widget.user.id,
      forceRefresh: forceRefresh,
    );

    if (!mounted) return;
    result.when(
      success: (data) {
        setState(() {
          _stats = data;
          _loading = false;
          _refreshing = false;
          _error = null;
        });
      },
      failure: (e) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _error = e;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _stats == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _load(forceRefresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final raw = _stats ?? {};
    final display = profileDisplayStats(
      widget.user,
      raw,
      defaultRole: widget.defaultRole,
      defaultLocation: widget.defaultLocation,
    );
    return widget.builder(
      context,
      display,
      () => _load(forceRefresh: true),
      _refreshing,
    );
  }
}

// ── Freelancer Profile ────────────────────────────────────────────────────────
class FreelancerProfileScreen extends StatelessWidget {
  const FreelancerProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.currentUser ??
        (AppConfig.isDemoMode
            ? const ApiUser(
                id: 'demo_user_me',
                displayName: 'alex_dev',
                fullName: 'Alex Chen',
                email: 'alex.chen@example.com',
                role: 'member',
                userType: 'freelancer',
              )
            : null);
    final name = user?.fullName ?? user?.displayName ?? 'Freelancer';
    final initials = name.length >= 2
        ? '${name.split(' ').first[0]}${name.split(' ').length > 1 ? name.split(' ')[1][0] : name[1]}'
        : name[0];

    if (user == null) return const SizedBox.shrink();

    return _ProfileStatsLoader(
      user: user,
      defaultRole: 'Freelance Developer',
      defaultLocation: 'Remote',
      builder: (context, d, refresh, refreshing) {
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: _ProfileBase(
            name: name,
            role: d.roleTitle,
            initials: initials.toUpperCase(),
            email: user.email,
            location: d.location,
            joined: d.joined,
            projects: d.projects,
            tasksDone: d.tasksDone,
            score: d.score,
          ),
        );
      },
    );
  }
}

// ── Student Profile ───────────────────────────────────────────────────────────
class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.currentUser ??
        (AppConfig.isDemoMode
            ? const ApiUser(
                id: 'demo_user_me',
                displayName: 'alex_dev',
                fullName: 'Alex Chen',
                email: 'alex.chen@example.com',
                role: 'member',
                userType: 'student',
                universityId: 'uni_cairo',
                universityName: 'Cairo University',
              )
            : null);
    final name = user?.fullName ?? user?.displayName ?? 'Student';
    final initials = name.length >= 2
        ? '${name.split(' ').first[0]}${name.split(' ').length > 1 ? name.split(' ')[1][0] : name[1]}'
        : name[0];

    if (user == null) return const SizedBox.shrink();

    return _ProfileStatsLoader(
      user: user,
      defaultRole: 'Student Developer',
      defaultLocation: 'University',
      builder: (context, d, refresh, _) {
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: _ProfileBase(
            name: name,
            role: d.roleTitle,
            initials: initials.toUpperCase(),
            email: user.email,
            location: d.location,
            universityName: user.universityName,
            isCustomUniversity: user.isCustomUniversity,
            joined: d.joined,
            projects: d.projects,
            tasksDone: d.tasksDone,
            score: d.score,
          ),
        );
      },
    );
  }
}

// ── Admin Profile ─────────────────────────────────────────────────────────────
class AdminProfileScreen extends StatelessWidget {
  const AdminProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.currentUser ??
        (AppConfig.isDemoMode
            ? const ApiUser(
                id: 'demo_user_me',
                displayName: 'alex_dev',
                fullName: 'Alex Chen',
                email: 'alex.chen@example.com',
                role: 'admin',
                userType: 'admin',
              )
            : null);
    final name = user?.fullName ?? user?.displayName ?? 'Admin';
    final initials = name.length >= 2
        ? '${name.split(' ').first[0]}${name.split(' ').length > 1 ? name.split(' ')[1][0] : name[1]}'
        : name[0];

    if (user == null) return const SizedBox.shrink();

    return _ProfileStatsLoader(
      user: user,
      defaultRole: 'System Administrator',
      defaultLocation: 'Remote',
      isAdmin: true,
      builder: (context, d, refresh, _) {
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: _ProfileBase(
            name: name,
            role: d.roleTitle,
            initials: initials.toUpperCase(),
            email: user.email,
            location: d.location,
            joined: d.joined,
            projects: d.projects,
            tasksDone: d.tasksDone,
            score: d.score,
            isAdmin: true,
          ),
        );
      },
    );
  }
}

// ── Edit Profile ──────────────────────────────────────────────────────────────
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _email;
  final _phone = TextEditingController();
  final _bio = TextEditingController();
  final _portfolio = TextEditingController();
  UniversityOption? _selectedUniversity;
  final _customUniCtrl = TextEditingController();

  String? _avatarFileId;
  Uint8List? _avatarBytes;
  bool _loadingProfile = true;
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<SessionController>().currentUser;
    _name = TextEditingController(text: user?.fullName ?? '');
    _username = TextEditingController(text: user?.displayName ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _initUniversity(user);
    // Phone/bio/avatar come from the server for this user only (not session cache).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  void _initUniversity(ApiUser? user) {
    if (user == null || user.universityName.isEmpty) return;
    if (user.isCustomUniversity) {
      _selectedUniversity =
          UniversityOption.create(id: 'uni_other', name: 'Other', isCustom: true);
      _customUniCtrl.text = user.universityName;
    } else {
      _selectedUniversity = UniversityOption.create(
        id: user.universityId.isNotEmpty ? user.universityId : 'uni_custom',
        name: user.universityName,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _phone.dispose();
    _bio.dispose();
    _portfolio.dispose();
    _customUniCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final session = context.read<SessionController>();
    if (AppConfig.isDemoMode) {
      final user = session.currentUser;
      if (user != null) {
        _name.text = user.fullName;
        _username.text = user.displayName;
        _email.text = user.email;
        _phone.text = user.phone;
        _bio.text = user.bio;
        _portfolio.text = user.portfolioUrl;
        _avatarFileId =
            user.avatarFileId.isNotEmpty ? user.avatarFileId : null;
        _initUniversity(user);
      }
      setState(() => _loadingProfile = false);
      return;
    }
    final svc = context.read<AppServices>().users;
    final sessionUserId = session.currentUser?.id;

    final res = await svc.getProfile(
      userId: sessionUserId,
      forceRefresh: true,
    );
    if (!mounted) return;
    res.when(
      success: (user) {
        if (user == null) {
          setState(() => _loadingProfile = false);
          return;
        }
        // Ignore stale cache if it belongs to another account.
        if (sessionUserId != null &&
            user.id.isNotEmpty &&
            user.id != sessionUserId) {
          setState(() => _loadingProfile = false);
          return;
        }
        _name.text = user.fullName;
        _username.text = user.displayName;
        _email.text = user.email;
        _phone.text = user.phone;
        _bio.text = user.bio;
        _portfolio.text = user.portfolioUrl;
        _avatarFileId = user.avatarFileId.isNotEmpty ? user.avatarFileId : null;
        _avatarBytes = null;
        setState(() => _loadingProfile = false);
        _loadAvatarBytes(_avatarFileId);
      },
      failure: (_) => setState(() => _loadingProfile = false),
    );
  }

  Future<void> _loadAvatarBytes(String? fileId) async {
    if (fileId == null || fileId.isEmpty) return;
    final res = await context.read<AppServices>().files.downloadFile(fileId);
    if (!mounted) return;
    res.when(
      success: (bytes) {
        if (bytes.isEmpty) return;
        setState(() => _avatarBytes = Uint8List.fromList(bytes));
      },
      failure: (_) {},
    );
  }

  Future<void> _pickAvatar() async {
    final fileService = context.read<AppServices>().files;
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    final bytes = picked.bytes;
    if (path == null && bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Cannot access image data.')),
      );
      return;
    }

    setState(() {
      _uploadingAvatar = true;
      if (bytes != null) _avatarBytes = bytes;
    });
    final uploadRes = await fileService.uploadFile(
      filePath: path ?? '',
      filename: picked.name,
      fileBytes: bytes,
    );
    if (!mounted) return;

    uploadRes.when(
      success: (file) {
        if (!mounted) return;
        setState(() {
          _avatarFileId = file.id;
          _uploadingAvatar = false;
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Photo selected — tap Save Changes to keep it'),
            backgroundColor: AppColors.success,
          ),
        );
      },
      failure: (msg) {
        if (!mounted) return;
        setState(() => _uploadingAvatar = false);
        messenger.showSnackBar(
          SnackBar(content: Text(msg)),
        );
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    final username = _username.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username is required')),
      );
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]{3,30}$').hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Username must be 3–30 characters: letters, numbers, underscores only',
          ),
        ),
      );
      return;
    }

    UniversityOption? uniToSend = _selectedUniversity;
    if (_selectedUniversity?.id == 'uni_other') {
      final customErr =
          UniversityOption.validateCustomUniversityName(_customUniCtrl.text);
      if (customErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(customErr)),
        );
        return;
      }
      uniToSend = UniversityOption.custom(_customUniCtrl.text);
    }

    setState(() => _saving = true);

    final svc = context.read<AppServices>().users;
    final session = context.read<SessionController>();

    if (AppConfig.isDemoMode) {
      final current = session.currentUser;
      if (current != null) {
        final updated = current.copyWith(
          displayName: username,
          fullName: _name.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          bio: _bio.text.trim(),
          portfolioUrl: _portfolio.text.trim(),
          avatarFileId: _avatarFileId ?? current.avatarFileId,
          universityId: uniToSend?.id ?? current.universityId,
          universityName: uniToSend?.name ?? current.universityName,
          isCustomUniversity: uniToSend?.isCustom ?? current.isCustomUniversity,
        );
        session.setCurrentUser(updated);
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
      return;
    }

    final payload = <String, dynamic>{
      'full_name': _name.text.trim(),
      'display_name': username,
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'bio': _bio.text.trim(),
      'portfolio_url': _portfolio.text.trim(),
    };
    if (_avatarFileId != null) {
      payload['avatar_file_id'] = int.tryParse(_avatarFileId!) ?? _avatarFileId;
    }

    final res = await svc.updateProfile(payload);
    if (!mounted) return;

    setState(() => _saving = false);

    res.when(
      success: (user) {
        if (user != null) session.setCurrentUser(user);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      },
      failure: (msg) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      },
    );
  }

  ImageProvider? get _avatarImage {
    if (_avatarBytes == null || _avatarBytes!.isEmpty) return null;
    return MemoryImage(_avatarBytes!);
  }

  @override
  Widget build(BuildContext context) {
    final initials = _name.text.isNotEmpty ? _name.text[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Edit Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Stack(
                    children: [
                      TAvatar(
                        initials: initials,
                        radius: 40,
                        backgroundImage: _avatarImage,
                      ),
                      if (_uploadingAvatar)
                        const Positioned.fill(
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.black38,
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _uploadingAvatar ? null : _pickAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TCard(child: Builder(builder: (ctx) {
                  final onSurface = Theme.of(ctx).colorScheme.onSurface;
                  final secColor = Theme.of(ctx).brightness == Brightness.dark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary;

                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Full Name',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _name,
                            style: TextStyle(color: onSurface),
                            decoration: _inputDec('Your full name')),
                        const SizedBox(height: 12),
                        Text('Username',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        const SizedBox(height: 4),
                        Text(
                          'Unique handle — letters, numbers, and underscores only',
                          style: TextStyle(fontSize: 12, color: secColor),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _username,
                            style: TextStyle(color: onSurface),
                            decoration: _inputDec('e.g. mohamed_dev'),
                            autocorrect: false,
                            enableSuggestions: false),
                        const SizedBox(height: 12),
                        Text('Email',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _email,
                            style: TextStyle(color: onSurface),
                            decoration: _inputDec('Your email'),
                            keyboardType: TextInputType.emailAddress),
                        if (context
                                .read<SessionController>()
                                .currentUser
                                ?.isStudent ==
                            true) ...[
                          const SizedBox(height: 12),
                          UniversitySelectorField(
                            selectedOption: _selectedUniversity,
                            onSelected: (opt) {
                              setState(() {
                                _selectedUniversity = opt;
                              });
                            },
                          ),
                          if (_selectedUniversity?.id == 'uni_other') ...[
                            const SizedBox(height: 12),
                            CustomUniversityField(
                              controller: _customUniCtrl,
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Text('Phone',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _phone,
                            style: TextStyle(color: onSurface),
                            decoration: _inputDec('Your phone'),
                            keyboardType: TextInputType.phone),
                        const SizedBox(height: 12),
                        Text('Bio',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _bio,
                            style: TextStyle(color: onSurface),
                            maxLines: 3,
                            decoration: _inputDec('About you')),
                        const SizedBox(height: 12),
                        Text('GitHub / Portfolio Link',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        const SizedBox(height: 4),
                        Text(
                          'Shown on your public profile so others can view your work',
                          style: TextStyle(fontSize: 12, color: secColor),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _portfolio,
                            style: TextStyle(color: onSurface),
                            decoration:
                                _inputDec('e.g. github.com/your_username'),
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            enableSuggestions: false),
                      ]);
                })),
                const SizedBox(height: 16),
                TButton(
                  label: _saving ? 'Saving…' : 'Save Changes',
                  onTap: _saving ? null : _save,
                ),
                const SizedBox(height: 8),
                TButton(
                    label: 'Cancel',
                    outline: true,
                    onTap: () => Navigator.pop(context)),
              ],
            ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary)),
      );
}

// ── Completed Projects ────────────────────────────────────────────────────────
class CompletedProjectsScreen extends StatelessWidget {
  const CompletedProjectsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Completed Projects',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: RepositoryLoader<List<ProjectModel>>(
        load: () async {
          final list = await context
              .read<AppServices>()
              .projects
              .listCompletedProjects()
              .unwrap();
          return list.map((project) => project.toDisplayModel()).toList();
        },
        isEmpty: (projects) => projects.isEmpty,
        emptyMessage: 'No completed projects found',
        builder: (context, projects) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: projects.length,
          itemBuilder: (_, i) {
            final p = projects[i];
            return TCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.folder_outlined,
                          color: AppColors.primary, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(p.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                        Text(p.company,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ])),
                  TChip(
                      label: '${p.progress}%',
                      bg: AppColors.success.withValues(alpha: 0.1),
                      textColor: AppColors.success),
                ]));
          },
        ),
      ),
    );
  }
}

// ── Ratings ───────────────────────────────────────────────────────────────────
class RatingsScreen extends StatefulWidget {
  const RatingsScreen({super.key});

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  Future<_RatingViewModel>? _future;

  Future<_RatingViewModel> _fetch() async {
    final userId = context.read<SessionController>().currentUser?.id ?? '';
    final services = context.read<AppServices>();
    if (userId.isEmpty) {
      return const _RatingViewModel(avg: 0, reviews: []);
    }
    final avg = await services.ratings.getUserAverageRating(userId).unwrap();
    final reviews = await services.ratings.getUserRatings(userId).unwrap();
    return _RatingViewModel(avg: avg, reviews: reviews);
  }

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Ratings & Reviews',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: _future == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<_RatingViewModel>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(snap.error.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          TextButton(
                            onPressed: _reload,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final vm = snap.data!;
                final avgStr = vm.avg > 0 ? vm.avg.toStringAsFixed(1) : '—';
                final fullStars = vm.avg.round().clamp(0, 5);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TCard(
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          Column(children: [
                            Text(avgStr,
                                style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary)),
                            Row(
                                children: List.generate(
                                    5,
                                    (i) => Icon(
                                        i < fullStars
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: Colors.amber,
                                        size: 20))),
                            Text(
                                vm.reviews.isEmpty
                                    ? 'No reviews yet'
                                    : 'Based on ${vm.reviews.length} review${vm.reviews.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                          ]),
                        ])),
                    const SizedBox(height: 12),
                    if (vm.reviews.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'When teammates rate you on completed projects, scores appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      ...vm.reviews.map((r) {
                        final score = (r['score'] as num?)?.toInt() ?? 0;
                        final comment = r['comment']?.toString() ?? '';
                        final created = r['created_at']?.toString() ?? '';
                        return TCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const TAvatar(initials: 'R', radius: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        const Text('Teammate',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textPrimary,
                                                fontSize: 13)),
                                        Row(
                                            children: List.generate(
                                                score.clamp(0, 5),
                                                (_) => const Icon(Icons.star,
                                                    size: 12,
                                                    color: Colors.amber))),
                                      ])),
                                  Text(
                                      created.contains('T')
                                          ? created.split('T').first
                                          : created,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary)),
                                ]),
                                if (comment.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(comment,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                ],
                              ]),
                        );
                      }),
                  ],
                );
              },
            ),
    );
  }
}

class _RatingViewModel {
  final double avg;
  final List<Map<String, dynamic>> reviews;

  const _RatingViewModel({required this.avg, required this.reviews});
}

// ── Performance (Courses / Performance / Feedback tabs) ───────────────────────
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});
  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          indicator: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20)),
          dividerColor: Colors.transparent,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Courses'),
            Tab(text: 'Performance'),
            Tab(text: 'Feedback')
          ],
        ),
      ),
      body: TabBarView(
          controller: _tab,
          children: const [_CoursesTab(), _PerfTab(), _FeedbackTab()]),
      bottomNavigationBar:
          TBottomNav(current: 4, onTap: (i) => handleRoleNav(context, i)),
    );
  }
}

class _CoursesTab extends StatelessWidget {
  const _CoursesTab();

  Future<List<Map<String, dynamic>>> _loadCourses(BuildContext context) async {
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
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryLoader<List<Map<String, dynamic>>>(
      load: () => _loadCourses(context),
      isEmpty: (courses) => courses.isEmpty,
      emptyMessage:
          'No AI course recommendations yet. Complete more projects to unlock suggestions.',
      builder: (context, courses) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Courses',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const Text('AI-recommended for you',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.star_outline,
                        color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text(
                        'These courses are personalized based on your career goals and current skill level',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary))),
              ])),
          const SizedBox(height: 20),
          const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recommended for You',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
              ]),
          const SizedBox(height: 10),
          ...courses.map((c) {
            final title =
                c['title']?.toString() ?? c['name']?.toString() ?? 'Course';
            final level = c['level']?.toString() ?? 'General';
            final platform = c['platform']?.toString() ??
                c['provider']?.toString() ??
                'Online';
            final duration = c['duration']?.toString() ?? '';
            final rating = c['rating']?.toString() ?? '';
            return TCard(
                margin: const EdgeInsets.only(bottom: 10),
                onTap: () => openCourseLink(context, c),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary))),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(level,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new,
                            size: 16, color: AppColors.textSecondary),
                      ]),
                      Text(
                          duration.isNotEmpty
                              ? '$platform · $duration'
                              : platform,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      if (rating.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.star, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(rating,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ]),
                      ],
                    ]));
          }),
        ],
      ),
    );
  }
}

class _PerfTab extends StatefulWidget {
  const _PerfTab();
  @override
  State<_PerfTab> createState() => _PerfTabState();
}

class _PerfTabState extends State<_PerfTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _load(forceRefresh: true));
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final user = context.read<SessionController>().currentUser;
    if (user == null) return;
    setState(() => _loading = _stats == null);
    final result = await context.read<AppServices>().users.getUserStats(
          user.id,
          forceRefresh: forceRefresh,
        );
    if (!mounted) return;
    result.when(
      success: (data) => setState(() {
        _stats = data;
        _loading = false;
      }),
      failure: (_) => setState(() => _loading = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().currentUser;
    if (user == null) return const SizedBox.shrink();
    if (_loading && _stats == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final d = profileDisplayStats(
      user,
      _stats ?? {},
      defaultRole: user.displayRole,
      defaultLocation: 'Remote',
    );
    final score = d.score;
    final commitment = d.commitment;
    final teamwork = d.teamwork;
    final quality = d.quality;

    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Performance',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)),
      const Text('AI-generated rating',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      const SizedBox(height: 16),
      TCard(
          child: Column(children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 2),
              gradient: const LinearGradient(
                  colors: [Color(0xFF4ECDC4), Color(0xFF2D5FA6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(score,
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const Text('Overall Score',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 12),
        const Text('Performance overview',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.success,
                fontWeight: FontWeight.w600)),
      ])),
      const SizedBox(height: 16),
      const Text('Performance Metrics',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)),
      const SizedBox(height: 10),
      ...[
        {
          'icon': Icons.remove_red_eye_outlined,
          'label': 'Commitment',
          'value': commitment,
          'color': AppColors.success
        },
        {
          'icon': Icons.people_outline,
          'label': 'Teamwork',
          'value': teamwork,
          'color': AppColors.primary
        },
        {
          'icon': Icons.chat_bubble_outline,
          'label': 'Quality',
          'value': quality,
          'color': AppColors.primaryDark
        },
      ].map((m) => TCard(
          margin: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(m['icon'] as IconData, color: m['color'] as Color, size: 22),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(m['label'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text('${m['value']}',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                      ]),
                  const SizedBox(height: 6),
                  TBar(
                      value: ((m['value'] as num).toDouble()) / 100,
                      color: m['color'] as Color,
                      height: 6),
                ])),
          ]))),
      const SizedBox(height: 8),
      const Text('6-Month Trend',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)),
      const SizedBox(height: 10),
      TCard(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const SizedBox(height: 60),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun']
                    .map((m) => Text(m,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textSecondary)))
                    .toList()),
          ])),
    ]);
  }
}

class _FeedbackTab extends StatefulWidget {
  const _FeedbackTab();
  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  int _stars = 0;
  final _ctrl = TextEditingController();
  bool _aiAssisting = false;
  bool _submitting = false;
  int _listVersion = 0;
  String? _selectedProjectId;
  List<ApiProject> _projects = [];
  bool _loadingProjects = true;
  String _aiSuggestion =
      'Consider mentioning specific achievements or areas for improvement to make your feedback more actionable.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProjects());
  }

  Future<void> _loadProjects() async {
    try {
      final projects =
          await context.read<AppServices>().projects.listProjects().unwrap();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _selectedProjectId = projects.isNotEmpty ? projects.first.id : null;
        _loadingProjects = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _runAiAssist() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select a star rating first, then use AI assist.')));
      return;
    }
    setState(() => _aiAssisting = true);
    try {
      final result =
          await context.read<AppServices>().ai.generateFeedbackAssist(
                rating: _stars,
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().currentUser;
    if (user == null) return const SizedBox.shrink();

    return RepositoryLoader<List<Map<String, dynamic>>>(
      key: ValueKey(_listVersion),
      load: () => context
          .read<AppServices>()
          .feedback
          .getUserFeedback(user.id, forceRefresh: _listVersion > 0)
          .unwrap(),
      builder: (context, feedbackList) {
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Feedback',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const Text('Share your thoughts',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          if (_loadingProjects)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (_projects.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Join a project before submitting feedback.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                key: ValueKey(_selectedProjectId),
                initialValue: _selectedProjectId,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _projects
                    .map((p) => DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedProjectId = v),
              ),
            ),
          TCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Rate Your Experience',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Row(
                    children: List.generate(
                        5,
                        (i) => GestureDetector(
                              onTap: () => setState(() => _stars = i + 1),
                              child: Icon(
                                  i < _stars ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: 32),
                            ))),
                const SizedBox(height: 12),
                const Text('Your Feedback',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                      color: const Color(0xFFF5F5FA),
                      borderRadius: BorderRadius.circular(10)),
                  child: Stack(children: [
                    TextField(
                        controller: _ctrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            hintText: 'Share your thoughts...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12))),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: TextButton.icon(
                        onPressed: _aiAssisting ? null : _runAiAssist,
                        icon: _aiAssisting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome,
                                size: 14, color: AppColors.primary),
                        label: Text(
                          _aiAssisting ? '…' : 'AI assist',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.primary),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                TButton(
                    label: _submitting ? 'Submitting…' : '✈ Submit Feedback',
                    onTap: _submitting
                        ? null
                        : () async {
                            if (_stars == 0) return;
                            final projectId = _selectedProjectId;
                            if (projectId == null || projectId.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Select a project before submitting feedback.'),
                                ),
                              );
                              return;
                            }
                            final feedback =
                                context.read<AppServices>().feedback;
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _submitting = true);
                            try {
                              await feedback
                                  .submitFeedback(
                                    targetUserId: user.id,
                                    projectId: projectId,
                                    rating: _stars,
                                    comment: _ctrl.text.trim(),
                                  )
                                  .unwrap();
                              if (!mounted) return;
                              setState(() {
                                _stars = 0;
                                _ctrl.clear();
                                _listVersion++;
                              });
                            } catch (e) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            } finally {
                              if (mounted) setState(() => _submitting = false);
                            }
                          }),
              ])),
          const SizedBox(height: 12),
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 18)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('AI Suggestion',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontSize: 13)),
                      Text(_aiSuggestion,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ])),
              ])),
          const SizedBox(height: 16),
          const Text('Recent Feedback',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          if (feedbackList.isEmpty)
            const Text('No feedback yet.',
                style: TextStyle(color: AppColors.textSecondary))
          else
            ...feedbackList.map((f) => TCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(
                            f['reviewer_name']?.toString() ??
                                f['author_name']?.toString() ??
                                'Teammate',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                        const Spacer(),
                        Row(
                            children: List.generate(
                                5,
                                (i) => Icon(
                                    i <
                                            ((f['avg_rating'] as num?)
                                                    ?.toInt() ??
                                                (f['rating'] as num?)
                                                    ?.toInt() ??
                                                0)
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 14,
                                    color: Colors.amber))),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                          f['feedback_text']?.toString() ??
                              f['content']?.toString() ??
                              '',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      Text(
                          f['created_at'] != null &&
                                  f['created_at'].toString().isNotEmpty
                              ? formatRelativeTime(f['created_at'].toString())
                              : 'Recently',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textHint)),
                    ]))),
        ]);
      },
    );
  }
}

// ── Activity & Disputes ───────────────────────────────────────────────────────
Future<void> showFileDisputeSheet(BuildContext context) async {
  final subjectCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final accusedCtrl = TextEditingController();
  var submitting = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('File a Dispute',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                TextField(
                  controller: accusedCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Accused user ID',
                    hintText: 'Enter the user ID you are reporting',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 16),
                TButton(
                  label: submitting ? 'Submitting…' : 'Submit Dispute',
                  onTap: submitting
                      ? null
                      : () async {
                          final accusedId =
                              int.tryParse(accusedCtrl.text.trim());
                          final subject = subjectCtrl.text.trim();
                          final description = descCtrl.text.trim();
                          if (accusedId == null ||
                              subject.isEmpty ||
                              description.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'User ID, subject, and description are required.'),
                              ),
                            );
                            return;
                          }
                          setSheetState(() => submitting = true);
                          final result = await context
                              .read<AppServices>()
                              .disputes
                              .fileDispute({
                            'accused_id': accusedId,
                            'subject': subject,
                            'description': description,
                          });
                          if (!context.mounted) return;
                          setSheetState(() => submitting = false);
                          result.when(
                            success: (_) {
                              Navigator.pop(sheetCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Dispute submitted'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            },
                            failure: (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e)),
                              );
                            },
                          );
                        },
                ),
              ],
            ),
          );
        },
      );
    },
  );

  subjectCtrl.dispose();
  descCtrl.dispose();
  accusedCtrl.dispose();
}

class MyActivityScreen extends StatelessWidget {
  const MyActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Activity',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RepositoryLoader<List<Map<String, dynamic>>>(
        load: () => context.read<AppServices>().logs.getMyActivity().unwrap(),
        isEmpty: (items) => items.isEmpty,
        emptyMessage: 'No recent activity yet.',
        builder: (context, items) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final item = items[i];
            final action = item['action']?.toString() ??
                item['type']?.toString() ??
                'Event';
            final details = item['details']?.toString() ??
                item['description']?.toString() ??
                '';
            final when = item['timestamp']?.toString() ??
                item['created_at']?.toString() ??
                '';
            return TCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  if (details.isNotEmpty)
                    Text(details,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  if (when.isNotEmpty)
                    Text(when,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textHint)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}



// ── Settings Screen ───────────────────────────────────────────────────────────
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isAdmin =
        context.watch<SessionController>().currentUser?.isAdmin == true;
    final darkMode = context.watch<ThemeController>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: Text(loc?.translate('settings') ?? 'Settings',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TSectionHeader(title: loc?.translate('settings') ?? 'Preferences'),
          const SizedBox(height: 12),
          TCard(
              child: Column(children: [
            _tile(context, Icons.mail_outline,
                loc?.translate('email_notifications') ?? 'Email Notifications', '',
                onTap: () =>
                    Navigator.pushNamed(context, R.emailNotificationSettings)),
            Divider(height: 1, color: theme.dividerColor),
            ListTile(
              onTap: () => darkMode.toggle(),
              leading: Icon(Icons.dark_mode_outlined,
                  color: theme.colorScheme.onSurface, size: 22),
              title: Text(loc?.translate('dark_mode') ?? 'Dark Mode',
                  style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: theme.colorScheme.onSurface)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    darkMode.isDark ? 'On' : 'Off',
                    style: TextStyle(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: darkMode.isDark,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => darkMode.setDarkMode(v),
                  ),
                ],
              ),
            ),
          ])),
          TSectionHeader(
              title: loc?.translate('security_privacy') ?? 'Security & Privacy'),
          const SizedBox(height: 12),
          TCard(
              child: Column(children: [
            _tile(context, Icons.lock_outline,
                loc?.translate('privacy_policy') ?? 'Privacy Policy', '',
                onTap: () => Navigator.pushNamed(context, R.privacyPolicy)),
            if (isAdmin) ...[
              Divider(height: 1, color: theme.dividerColor),
              _tile(context, Icons.security_outlined,
                  loc?.translate('security_center') ?? 'Security Center', '',
                  onTap: () => Navigator.pushNamed(context, R.securityCenter)),
            ],
          ])),
          const SizedBox(height: 24),
          TSectionHeader(title: loc?.translate('account') ?? 'Account'),
          const SizedBox(height: 12),
          TCard(
            onTap: () => _showLogoutDialog(context),
            child: Row(
              children: [
                const Icon(Icons.logout, color: AppColors.error, size: 22),
                const SizedBox(width: 12),
                Text(loc?.translate('logout') ?? 'Log out',
                    style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios,
                    size: 14, color: AppColors.textHint),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Center(
              child: Text('Teamify v2.0.4 Build 102',
                  style: TextStyle(color: AppColors.textHint, fontSize: 11))),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log out',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await SessionController.performAppLogout(context);
            },
            child: const Text('Log out',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String value,
      {required VoidCallback onTap}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: onSurface, size: 22),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w500, fontSize: 14, color: onSurface)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value.isNotEmpty)
            Text(value, style: TextStyle(color: secondary, fontSize: 13)),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios, size: 14, color: secondary),
        ],
      ),
    );
  }
}

// ── Privacy Policy ────────────────────────────────────────────────────────────
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = <({String title, String body})>[
    (
      title: '1. Information We Collect',
      body:
          'Teamify collects information you provide when you register (name, email, role), '
          'project and task data you create in the app, messages sent in team chat, '
          'files you upload, and usage data such as login times and device type for security.',
    ),
    (
      title: '2. How We Use Your Data',
      body:
          'We use your data to operate the platform (projects, tasks, chat, meetings), '
          'personalize AI features (mentor insights, task suggestions, CV builder), '
          'send notifications, and protect accounts through security monitoring.',
    ),
    (
      title: '3. AI and Automated Processing',
      body:
          'Some features use machine learning on the server (task classification, delay '
          'prediction, mentor recommendations, chat summarization). AI outputs are '
          'suggestions only and do not replace human decisions on hiring or evaluation.',
    ),
    (
      title: '4. Data Sharing',
      body:
          'Your profile and project content are visible to teammates and admins as '
          'configured by your organization. We do not sell personal data. Third-party '
          'services (e.g. speech-to-text) may process data only when you use those features.',
    ),
    (
      title: '5. Security',
      body:
          'We use authentication tokens, encrypted connections (HTTPS), and access controls '
          'by role. You are responsible for keeping your password confidential and reporting '
          'suspicious activity via Security Center.',
    ),
    (
      title: '6. Your Rights',
      body:
          'You may update your profile, request export of your data, or ask for account '
          'deletion through your administrator. Contact support if you need help exercising '
          'these rights.',
    ),
    (
      title: '7. Contact',
      body:
          'For privacy questions, contact your Teamify administrator or the support channel '
          'provided by your organization. Last updated: May 2026.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Privacy Policy',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AIBanner(
            title: 'Your privacy matters',
            subtitle:
                'How Teamify collects, uses, and protects your information',
          ),
          const SizedBox(height: 16),
          ..._sections.map((s) => TCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            fontSize: 15)),
                    const SizedBox(height: 8),
                    Text(s.body,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppColors.textSecondary)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ── Demo Feedback Models & Shared Store ──────────────────────────────────────
class DemoUserFeedback {
  final String id;
  final String targetUserId;
  final String reviewerId;
  final String reviewerName;
  final String reviewerRole;
  final double rating;
  final Map<String, int> categoryRatings;
  final String reviewText;
  final bool recommended;
  final DateTime createdAt;

  const DemoUserFeedback({
    required this.id,
    required this.targetUserId,
    required this.reviewerId,
    required this.reviewerName,
    required this.reviewerRole,
    required this.rating,
    required this.categoryRatings,
    required this.reviewText,
    required this.recommended,
    required this.createdAt,
  });
}

final List<DemoUserFeedback> globalDemoFeedbackStore = [
  DemoUserFeedback(
    id: 'fb_1',
    targetUserId: 'demo_user_me',
    reviewerId: 'user_client_1',
    reviewerName: 'Sarah Jenkins',
    reviewerRole: 'Project Owner',
    rating: 5.0,
    categoryRatings: const {
      'Communication': 5,
      'Technical Skills': 5,
      'Teamwork': 5,
      'Problem Solving': 4,
      'Professionalism': 5,
    },
    reviewText:
        'Alex delivered top-tier Flutter code ahead of deadline. Exceptional attention to detail and clear daily async updates!',
    recommended: true,
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  DemoUserFeedback(
    id: 'fb_2',
    targetUserId: 'demo_user_me',
    reviewerId: 'user_manager_1',
    reviewerName: 'Michael Chang',
    reviewerRole: 'Engineering Manager',
    rating: 4.8,
    categoryRatings: const {
      'Communication': 5,
      'Technical Skills': 5,
      'Teamwork': 4,
      'Problem Solving': 5,
      'Professionalism': 5,
    },
    reviewText:
        'Great architecture design and proactive communication during sprint planning. Highly recommended team member.',
    recommended: true,
    createdAt: DateTime.now().subtract(const Duration(days: 12)),
  ),
];

class ProfileFeedbackStats {
  final double avgRating;
  final int totalReviews;
  final int performanceScore;
  final String reputationBadge;
  final Color reputationColor;
  final double recommendationPct;
  final Map<String, double> categoryAverages;

  const ProfileFeedbackStats({
    required this.avgRating,
    required this.totalReviews,
    required this.performanceScore,
    required this.reputationBadge,
    required this.reputationColor,
    required this.recommendationPct,
    required this.categoryAverages,
  });

  factory ProfileFeedbackStats.fromList(List<DemoUserFeedback> reviews) {
    if (reviews.isEmpty) {
      return const ProfileFeedbackStats(
        avgRating: 0.0,
        totalReviews: 0,
        performanceScore: 0,
        reputationBadge: 'No Reputation',
        reputationColor: AppColors.textSecondary,
        recommendationPct: 0.0,
        categoryAverages: {
          'Communication': 0.0,
          'Technical Skills': 0.0,
          'Teamwork': 0.0,
          'Problem Solving': 0.0,
          'Professionalism': 0.0,
        },
      );
    }

    final total = reviews.length;
    final sumRating = reviews.fold<double>(0.0, (acc, r) => acc + r.rating);
    final avg = sumRating / total;

    final recCount = reviews.where((r) => r.recommended).length;
    final recPct = (recCount / total) * 100.0;

    final score = (avg / 5.0 * 100.0).round().clamp(0, 100);

    String badge = 'Good';
    Color badgeColor = Colors.orange;
    if (score >= 90) {
      badge = 'Outstanding';
      badgeColor = AppColors.success;
    } else if (score >= 80) {
      badge = 'Excellent';
      badgeColor = AppColors.primary;
    } else if (score >= 70) {
      badge = 'Very Good';
      badgeColor = const Color(0xFF0D9488);
    } else if (score >= 60) {
      badge = 'Good';
      badgeColor = Colors.orange;
    } else {
      badge = 'Needs Improvement';
      badgeColor = Colors.redAccent;
    }

    final categories = [
      'Communication',
      'Technical Skills',
      'Teamwork',
      'Problem Solving',
      'Professionalism',
    ];

    final Map<String, double> catAvgs = {};
    for (final cat in categories) {
      int catSum = 0;
      int count = 0;
      for (final r in reviews) {
        if (r.categoryRatings.containsKey(cat) && r.categoryRatings[cat]! > 0) {
          catSum += r.categoryRatings[cat]!;
          count++;
        }
      }
      catAvgs[cat] = count > 0 ? (catSum / count) : 0.0;
    }

    return ProfileFeedbackStats(
      avgRating: avg,
      totalReviews: total,
      performanceScore: score,
      reputationBadge: badge,
      reputationColor: badgeColor,
      recommendationPct: recPct,
      categoryAverages: catAvgs,
    );
  }
}

class _FeedbackDialog extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;
  final VoidCallback onSubmitted;

  const _FeedbackDialog({
    required this.targetUserId,
    required this.targetUserName,
    required this.onSubmitted,
  });

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  int _overallRating = 5;
  final Map<String, int> _categoryRatings = {
    'Communication': 5,
    'Technical Skills': 5,
    'Teamwork': 5,
    'Problem Solving': 5,
    'Professionalism': 5,
  };
  final _reviewCtrl = TextEditingController();
  bool _recommended = true;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _reviewCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a review text.')),
      );
      return;
    }
    if (_overallRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an overall rating.')),
      );
      return;
    }

    final session = context.read<SessionController>();
    final me = session.currentUser;
    final myId = me?.id ?? 'demo_user_me';
    final myName = me?.fullName ?? me?.displayName ?? 'Alex Chen';
    final myRole = me?.userType == 'client'
        ? 'Client'
        : (me?.role == 'admin' ? 'Manager' : 'Team Member');

    final existingIndex = globalDemoFeedbackStore.indexWhere(
      (r) => r.reviewerId == myId && r.targetUserId == widget.targetUserId,
    );

    final newFeedback = DemoUserFeedback(
      id: 'fb_${DateTime.now().millisecondsSinceEpoch}',
      targetUserId: widget.targetUserId,
      reviewerId: myId,
      reviewerName: myName,
      reviewerRole: myRole,
      rating: _overallRating.toDouble(),
      categoryRatings: Map.from(_categoryRatings),
      reviewText: text,
      recommended: _recommended,
      createdAt: DateTime.now(),
    );

    if (existingIndex >= 0) {
      globalDemoFeedbackStore[existingIndex] = newFeedback;
    } else {
      globalDemoFeedbackStore.insert(0, newFeedback);
    }

    widget.onSubmitted();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Feedback submitted successfully!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.rate_review, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Leave Feedback for ${widget.targetUserName}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Rate performance & teamwork quality',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overall Rating *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: List.generate(5, (i) {
                final starIndex = i + 1;
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    starIndex <= _overallRating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: Colors.amber,
                    size: 32,
                  ),
                  onPressed: () => setState(() => _overallRating = starIndex),
                );
              }),
            ),
            const SizedBox(height: 16),
            const Text('Category Ratings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ..._categoryRatings.keys.map((cat) {
              final val = _categoryRatings[cat]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(cat, style: const TextStyle(fontSize: 12)),
                    Row(
                      children: List.generate(5, (i) {
                        final starIndex = i + 1;
                        return InkWell(
                          onTap: () =>
                              setState(() => _categoryRatings[cat] = starIndex),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(
                              starIndex <= val ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 20,
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            const Text('Review Text (Max 500 chars) *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _reviewCtrl,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'Share details about communication, quality of work, and reliability...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Recommend this user?',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Switch(
                  value: _recommended,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _recommended = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Submit Feedback'),
        ),
      ],
    );
  }
}

class _ProfileFeedbackSection extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;

  const _ProfileFeedbackSection({
    required this.targetUserId,
    required this.targetUserName,
  });

  @override
  State<_ProfileFeedbackSection> createState() =>
      _ProfileFeedbackSectionState();
}

class _ProfileFeedbackSectionState extends State<_ProfileFeedbackSection> {
  void _refresh() {
    setState(() {});
  }

  String _initials(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final border = Theme.of(context).dividerColor;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final sectionBg = isDark ? const Color(0xFF0F172A) : AppColors.background;

    final session = context.watch<SessionController>();
    final me = session.currentUser;
    final myId = me?.id ?? 'demo_user_me';
    final isSelf = myId == widget.targetUserId;

    final userReviews = globalDemoFeedbackStore
        .where((r) => r.targetUserId == widget.targetUserId)
        .toList();

    final stats = ProfileFeedbackStats.fromList(userReviews);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sectionBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.workspace_premium,
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Feedback & Performance',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: onSurface),
                  ),
                ],
              ),
              if (!isSelf)
                ElevatedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => _FeedbackDialog(
                      targetUserId: widget.targetUserId,
                      targetUserName: widget.targetUserName,
                      onSubmitted: _refresh,
                    ),
                  ),
                  icon: const Icon(Icons.star, size: 16),
                  label: const Text('Leave Feedback'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
            ],
          ),
          if (isSelf) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'You cannot review your own profile.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Overview Grid Stats
          Row(
            children: [
              Expanded(
                child: _feedbackStatCard(
                  context: context,
                  title: 'Overall Rating',
                  value: '${stats.avgRating.toStringAsFixed(1)} ★',
                  subtitle: '${stats.totalReviews} reviews',
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _feedbackStatCard(
                  context: context,
                  title: 'Performance',
                  value: '${stats.performanceScore} / 100',
                  subtitle: 'Calculated score',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _feedbackStatCard(
                  context: context,
                  title: 'Reputation',
                  value: stats.reputationBadge,
                  subtitle:
                      '${stats.recommendationPct.toStringAsFixed(0)}% recommend',
                  color: stats.reputationColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category Breakdown
          Text('Category Breakdown',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: onSurface)),
          const SizedBox(height: 8),
          ...stats.categoryAverages.entries.map((entry) {
            final catName = entry.key;
            final catVal = entry.value;
            final pct = catVal / 5.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(catName,
                        style: TextStyle(fontSize: 12, color: secondary)),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: border,
                      color: AppColors.primary,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${catVal.toStringAsFixed(1)} ★',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: onSurface),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),

          // Recent Reviews List / Empty state
          Text('Recent Reviews',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: onSurface)),
          const SizedBox(height: 8),
          if (userReviews.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  Icon(Icons.rate_review_outlined, size: 40, color: secondary),
                  const SizedBox(height: 8),
                  Text(
                    'No feedback has been submitted yet.',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: secondary,
                        fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ...userReviews.take(5).map((rev) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TAvatar(
                            initials: _initials(rev.reviewerName), radius: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(rev.reviewerName,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: onSurface)),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      rev.reviewerRole,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < rev.rating.round()
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: Colors.amber,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${rev.createdAt.year}-${rev.createdAt.month}-${rev.createdAt.day}',
                          style: TextStyle(fontSize: 11, color: secondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(rev.reviewText,
                        style: TextStyle(fontSize: 12.5, color: onSurface)),
                    if (rev.recommended) ...[
                      const SizedBox(height: 6),
                      const Row(
                        children: [
                          Icon(Icons.thumb_up_alt_outlined,
                              size: 12, color: AppColors.success),
                          SizedBox(width: 4),
                          Text('Recommends this user',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _feedbackStatCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final border = Theme.of(context).dividerColor;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 10, color: secondary)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 9, color: secondary)),
        ],
      ),
    );
  }
}

class UserProfileDetailScreen extends StatelessWidget {
  final ApiUser user;
  const UserProfileDetailScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final name = user.fullName.isNotEmpty ? user.fullName : user.displayName;
    final initials = name.length >= 2
        ? '${name.split(' ').first[0]}${name.split(' ').length > 1 ? name.split(' ')[1][0] : name[1]}'
        : name[0];

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _ProfileStatsLoader(
        user: user,
        defaultRole: user.displayRole,
        defaultLocation: 'Remote',
        builder: (context, d, refresh, _) {
          return RefreshIndicator(
            onRefresh: () async => refresh(),
            child: _ProfileBase(
              name: name,
              role: d.roleTitle,
              initials: initials.toUpperCase(),
              email: user.email,
              location: d.location,
              joined: d.joined,
              projects: d.projects,
              tasksDone: d.tasksDone,
              score: d.score,
              targetUserId: user.id,
            ),
          );
        },
      ),
    );
  }
}
