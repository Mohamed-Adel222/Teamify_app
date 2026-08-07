import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import '../../widgets/admin_user_picker.dart';

class AdminProjectsScreen extends StatefulWidget {
  const AdminProjectsScreen({super.key});

  @override
  State<AdminProjectsScreen> createState() => _AdminProjectsScreenState();
}

class _AdminProjectsScreenState extends State<AdminProjectsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _filterStatus =
      ''; // '', 'active', 'completed', 'delayed', 'high_risk'
  int _currentPage = 1;
  int _totalPages = 1;
  bool _loading = false;
  List<dynamic> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim();
        _currentPage = 1;
      });
      _loadProjects();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final res = await context
          .read<AppServices>()
          .admin
          .listProjects(
            search: _searchQuery,
            status: _filterStatus,
            page: _currentPage,
          )
          .unwrap();

      setState(() {
        _projects = res['items'] as List? ?? [];
        _totalPages = res['pages'] ?? 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load projects: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reassignOwner(String projectId, String newOwnerId) async {
    try {
      await context
          .read<AppServices>()
          .admin
          .reassignProject(projectId, newOwnerId)
          .unwrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Project ownership transferred successfully'),
            backgroundColor: AppColors.success),
      );
      _loadProjects();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _deleteProject(String projectId) async {
    try {
      await context.read<AppServices>().admin.deleteProject(projectId).unwrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Project force-deleted successfully'),
            backgroundColor: AppColors.success),
      );
      _loadProjects();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Project Management',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Filters & Search
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search by project name or description...',
                      border: InputBorder.none,
                      prefixIcon:
                          Icon(Icons.search, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Filter Dropdown
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButton<String>(
                    value: _filterStatus,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All Projects')),
                      DropdownMenuItem(
                          value: 'active', child: Text('Active Only')),
                      DropdownMenuItem(
                          value: 'completed', child: Text('Completed Only')),
                      DropdownMenuItem(
                          value: 'delayed', child: Text('Delayed Only')),
                      DropdownMenuItem(
                          value: 'high_risk', child: Text('High Risk Only')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _filterStatus = val ?? '';
                        _currentPage = 1;
                      });
                      _loadProjects();
                    },
                  ),
                ),
              ],
            ),
          ),

          // Project List
          Expanded(
            child: _loading && _projects.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _projects.isEmpty
                    ? const Center(
                        child: Text('No projects found matching filters',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: _loadProjects,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _projects.length,
                          itemBuilder: (context, index) {
                            final p = _projects[index] as Map<String, dynamic>;
                            final double progress =
                                ((p['progress'] ?? 0) as num).toDouble() /
                                    100.0;
                            final String risk = p['risk_level'] ?? 'Healthy';

                            return TCard(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p['name'] ?? 'Project',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                        ),
                                        TChip(
                                          label: risk.toUpperCase(),
                                          bg: risk == 'High Risk'
                                              ? AppColors.error
                                                  .withValues(alpha: 0.1)
                                              : risk == 'Medium Risk'
                                                  ? AppColors.warning
                                                      .withValues(alpha: 0.1)
                                                  : AppColors.success
                                                      .withValues(alpha: 0.1),
                                          textColor: risk == 'High Risk'
                                              ? AppColors.error
                                              : risk == 'Medium Risk'
                                                  ? AppColors.warning
                                                  : AppColors.success,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      p['description'] ??
                                          'No description provided.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                    const SizedBox(height: 12),
                                    // Owner and members info
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                            'Owner: ${p['owner_name'] ?? 'System'}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold)),
                                        Text(
                                            'Members: ${p['member_count'] ?? 1}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color:
                                                    AppColors.textSecondary)),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    // Progress Bar
                                    Row(
                                      children: [
                                        Expanded(
                                            child: TBar(
                                                value: progress,
                                                color: AppColors.primary)),
                                        const SizedBox(width: 8),
                                        Text('${(progress * 100).round()}%',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const Divider(height: 24),
                                    // Actions
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(
                                              Icons
                                                  .transfer_within_a_station_outlined,
                                              size: 16),
                                          label: const Text('Reassign Owner',
                                              style: TextStyle(fontSize: 11)),
                                          onPressed: () => _showReassignDialog(
                                              p['id'].toString()),
                                        ),
                                        const SizedBox(width: 12),
                                        TextButton.icon(
                                          icon: const Icon(Icons.delete_outline,
                                              color: AppColors.error, size: 16),
                                          label: const Text('Delete',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.error)),
                                          onPressed: () =>
                                              _showDeleteConfirmation(
                                                  p['id'].toString()),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),

          // Pagination Bar
          if (_totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _currentPage > 1
                        ? () {
                            setState(() => _currentPage--);
                            _loadProjects();
                          }
                        : null,
                  ),
                  Text('Page $_currentPage of $_totalPages',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _currentPage < _totalPages
                        ? () {
                            setState(() => _currentPage++);
                            _loadProjects();
                          }
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showReassignDialog(String projectId) async {
    final user =
        await showAdminUserPicker(context, title: 'Select New Project Owner');
    if (user == null || !mounted) return;
    await _reassignOwner(projectId, user.id);
  }

  void _showDeleteConfirmation(String projectId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Force Delete Project'),
          content: const Text(
              'Are you sure you want to permanently delete this project? All associated tasks and data will be destroyed.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                Navigator.pop(context);
                _deleteProject(projectId);
              },
              child: const Text('Delete permanently'),
            ),
          ],
        );
      },
    );
  }
}
