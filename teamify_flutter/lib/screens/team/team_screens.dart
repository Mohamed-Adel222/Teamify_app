import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/models.dart' as api;
import '../../core/theme.dart';
import '../../services/app_services.dart';
import '../../core/network/api_result.dart';
import '../../models/models.dart';
import '../../widgets/widgets.dart';
import '../../widgets/project_member_detail_tile.dart';
import '../project/project_screens.dart';
import '../chat/chat_room_utils.dart';

class _ProjectTeam {
  final String id;
  final String name;
  final String description;
  final List<UserModel> members;
  final int memberCount;
  final int projectsCount;

  const _ProjectTeam({
    required this.id,
    required this.name,
    required this.description,
    required this.members,
    required this.memberCount,
    required this.projectsCount,
  });
}

// ── Teams List Screen ────────────────────────────────────────────────────────
class TeamsListScreen extends StatefulWidget {
  const TeamsListScreen({super.key});

  @override
  State<TeamsListScreen> createState() => _TeamsListScreenState();
}

class _TeamsListScreenState extends State<TeamsListScreen> {
  Future<List<_ProjectTeam>>? _teamsFuture;
  bool _initialLoadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    _teamsFuture = _loadTeams();
  }

  Future<List<_ProjectTeam>> _loadTeams() async {
    final services = context.read<AppServices>();
    final projects =
        await services.projects.listProjects(forceRefresh: true).unwrap();

    final teams = await Future.wait(projects.map((project) async {
      final memberUsers =
          await services.projects.listMembers(project.id).unwrap();
      final members = memberUsers.map((u) => u.toDisplayModel()).toList();
      final memberCount = project.memberCount > 0
          ? project.memberCount
          : (members.isNotEmpty ? members.length : 1);

      return _ProjectTeam(
        id: project.id,
        name: project.name,
        description: _displayDescription(project.description),
        members: members,
        memberCount: memberCount,
        projectsCount: 1,
      );
    }));

    return teams;
  }

  String _displayDescription(String raw) {
    var text = raw.trim();
    if (text.startsWith('[Visibility:')) {
      final end = text.indexOf(']');
      if (end != -1 && end + 1 < text.length) {
        text = text.substring(end + 1).trim();
      }
    }
    return text.isNotEmpty ? text : 'Project team';
  }

  Future<void> _createTeam() async {
    final created = await Navigator.of(context).push<api.ApiProject>(
      MaterialPageRoute(builder: (_) => const AddProjectScreen()),
    );
    if (!mounted || created == null) return;

    try {
      final projectId = int.tryParse(created.id);
      if (projectId != null) {
        await context.read<AppServices>().chat.createRoom({
          'name': created.name,
          'project_id': projectId,
          'is_group': true,
        }).unwrap();
      }
    } catch (_) {
      // Team saved — chat room is optional; meeting can still use project context.
    }

    if (!mounted) return;
    setState(() {
      _teamsFuture = _loadTeams();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Team created successfully'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _reload() {
    setState(() {
      _teamsFuture = _loadTeams();
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
        title:
            const Text('Teams', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _teamsFuture;
        },
        child: _teamsFuture == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : FutureBuilder<List<_ProjectTeam>>(
                future: _teamsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 80),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: _reload,
                            child: const Text('Retry'),
                          ),
                        ),
                      ],
                    );
                  }
                  final teams = snapshot.data ?? [];
                  if (teams.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Text(
                            'No teams yet. Create a project — each project is a team in Teamify.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: teams.length,
                    itemBuilder: (_, i) {
                      final t = teams[i];
                      return TCard(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12)),
                                  child: const Icon(Icons.people_outline,
                                      color: AppColors.primary, size: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(t.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: AppColors.textPrimary)),
                                      Text(
                                        t.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                SizedBox(
                                  height: 30,
                                  width: 70,
                                  child: Stack(
                                    children: List.generate(
                                        t.members.length > 3
                                            ? 3
                                            : t.members.length, (index) {
                                      final user = t.members[index];
                                      return Positioned(
                                        left: index * 18.0,
                                        child: TAvatar(
                                            initials: user.initials,
                                            radius: 15),
                                      );
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${t.memberCount} members',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                                const Spacer(),
                                const Icon(Icons.folder_outlined,
                                    size: 14, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text('${t.projectsCount} projects',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => openProjectTeamChat(
                                  context,
                                  projectId: t.id,
                                  projectName: t.name,
                                ),
                                icon: const Icon(Icons.chat_bubble_outline,
                                    size: 18),
                                label: const Text('Team chat'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: TButton(
          label: '+ Create Team',
          onTap: _createTeam,
        ),
      ),
    );
  }
}

// ── Members List Screen (Improved) ───────────────────────────────────────────
class MembersListScreen extends StatefulWidget {
  const MembersListScreen({super.key});

  @override
  State<MembersListScreen> createState() => _MembersListScreenState();
}

class _MembersListScreenState extends State<MembersListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<api.ApiUser> _users = [];
  bool _loading = true;
  String? _loadError;
  bool _initialLoadDone = false;

  List<api.ApiUser> get _filteredUsers {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      final haystack = [
        u.primaryName,
        u.displayName,
        u.email,
        u.displayRole,
        u.professionalField,
        u.availability,
        u.experienceLevel,
        ...u.skills,
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

  Future<void> _load() async {
    setState(() {
      if (_users.isEmpty) _loading = true;
      _loadError = null;
    });
    try {
      final result =
          await context.read<AppServices>().search.users('', perPage: 100);
      if (!mounted) return;
      result.when(
        success: (items) {
          setState(() {
            _users =
                items.where((u) => u.role.toLowerCase() != 'guest').toList();
            _loading = false;
            _loadError = null;
          });
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

  Widget _roleChip(api.ApiUser user) {
    final role = user.displayRole;
    final isFreelancer = role == 'Freelancer';
    final isAdmin = role == 'Admin';
    return TChip(
      label: role,
      bg: isAdmin
          ? const Color(0xFFFEF3C7)
          : isFreelancer
              ? const Color(0xFFEFF6FF)
              : const Color(0xFFF0FDF4),
      textColor: isAdmin
          ? const Color(0xFFD97706)
          : isFreelancer
              ? const Color(0xFF2563EB)
              : const Color(0xFF16A34A),
      fontSize: 10,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers;
    final query = _searchController.text.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Members',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border)),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by name or skill...',
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.textSecondary, size: 20),
                  suffixIcon: query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              query.isEmpty
                                  ? 'No members found'
                                  : 'No members match "$query"',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final user = filtered[i];
                                return TCard(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  child: ProjectMemberDetailTile(
                                    user: user,
                                    useAccountRole: true,
                                    showJoinedAt: true,
                                    trailing: _roleChip(user),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
