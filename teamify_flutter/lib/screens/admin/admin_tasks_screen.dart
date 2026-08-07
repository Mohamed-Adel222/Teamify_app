import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import '../../widgets/admin_user_picker.dart';

class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({super.key});

  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _filterPriority = ''; // '', 'low', 'medium', 'high'
  String _filterStatus = ''; // '', 'pending', 'in_progress', 'done'
  int _currentPage = 1;
  int _totalPages = 1;
  bool _loading = false;
  List<dynamic> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim();
        _currentPage = 1;
      });
      _loadTasks();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final res = await context
          .read<AppServices>()
          .admin
          .listTasks(
            search: _searchQuery,
            priority: _filterPriority,
            status: _filterStatus,
            page: _currentPage,
          )
          .unwrap();

      setState(() {
        _tasks = res['items'] as List? ?? [];
        _totalPages = res['pages'] ?? 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load tasks: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateTask(String taskId,
      {String? status, String? assignedTo}) async {
    try {
      await context
          .read<AppServices>()
          .admin
          .updateTask(taskId, status: status, assignedTo: assignedTo)
          .unwrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Task updated successfully'),
            backgroundColor: AppColors.success),
      );
      _loadTasks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      await context.read<AppServices>().admin.deleteTask(taskId).unwrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Task permanently deleted'),
            backgroundColor: AppColors.success),
      );
      _loadTasks();
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
        title: const Text('Task Management',
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
                      hintText: 'Search tasks by title...',
                      border: InputBorder.none,
                      prefixIcon:
                          Icon(Icons.search, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Filters Row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButton<String>(
                          value: _filterPriority,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                                value: '',
                                child: Text('All Priorities',
                                    style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'low',
                                child: Text('Low Priority',
                                    style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'medium',
                                child: Text('Medium Priority',
                                    style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'high',
                                child: Text('High Priority',
                                    style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _filterPriority = val ?? '';
                              _currentPage = 1;
                            });
                            _loadTasks();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
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
                            DropdownMenuItem(
                                value: '',
                                child: Text('All Statuses',
                                    style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'pending',
                                child: Text('Pending',
                                    style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'in_progress',
                                child: Text('In Progress',
                                    style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(
                                value: 'done',
                                child: Text('Completed',
                                    style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _filterStatus = val ?? '';
                              _currentPage = 1;
                            });
                            _loadTasks();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tasks List
          Expanded(
            child: _loading && _tasks.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _tasks.isEmpty
                    ? const Center(
                        child: Text('No tasks found matching filters',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: _loadTasks,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _tasks.length,
                          itemBuilder: (context, index) {
                            final t = _tasks[index] as Map<String, dynamic>;
                            final String priority = t['priority'] ?? 'medium';
                            final String status = t['status'] ?? 'pending';

                            return TCard(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            t['title'] ?? 'Task',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15),
                                          ),
                                        ),
                                        TChip(
                                          label: priority.toUpperCase(),
                                          bg: priority == 'high'
                                              ? AppColors.error
                                                  .withValues(alpha: 0.1)
                                              : priority == 'medium'
                                                  ? AppColors.warning
                                                      .withValues(alpha: 0.1)
                                                  : AppColors.success
                                                      .withValues(alpha: 0.1),
                                          textColor: priority == 'high'
                                              ? AppColors.error
                                              : priority == 'medium'
                                                  ? AppColors.warning
                                                  : AppColors.success,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                        'Project: ${t['project_name'] ?? 'Unknown'}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary)),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Assigned To: ${t['assigned_user_name'] ?? 'Unassigned'}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                    if (t['due_date'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text('Due Date: ${t['due_date']}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary)),
                                    ],
                                    const Divider(height: 20),
                                    // Row of Actions
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(
                                              Icons.person_add_alt_1_outlined,
                                              size: 16),
                                          label: const Text('Reassign',
                                              style: TextStyle(fontSize: 11)),
                                          onPressed: () => _showReassignDialog(
                                              t['id'].toString()),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          icon: const Icon(Icons.rule_outlined,
                                              size: 16),
                                          label: const Text('Status',
                                              style: TextStyle(fontSize: 11)),
                                          onPressed: () => _showStatusDialog(
                                              t['id'].toString(), status),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          icon: const Icon(Icons.delete_outline,
                                              color: AppColors.error, size: 16),
                                          label: const Text('Delete',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.error)),
                                          onPressed: () =>
                                              _showDeleteConfirmation(
                                                  t['id'].toString()),
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
                            _loadTasks();
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
                            _loadTasks();
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

  Future<void> _showReassignDialog(String taskId) async {
    final user = await showAdminUserPicker(context, title: 'Assign Task To');
    if (user == null || !mounted) return;
    await _updateTask(taskId, assignedTo: user.id);
  }

  void _showStatusDialog(String taskId, String currentStatus) {
    showDialog(
      context: context,
      builder: (context) {
        String selStatus = currentStatus;
        return AlertDialog(
          title: const Text('Change Task Status'),
          content: DropdownButtonFormField<String>(
            initialValue: currentStatus,
            items: const [
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(
                  value: 'in_progress', child: Text('In Progress')),
              DropdownMenuItem(value: 'done', child: Text('Completed')),
            ],
            onChanged: (val) {
              if (val != null) selStatus = val;
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateTask(taskId, status: selStatus);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(String taskId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Force Delete Task'),
          content: const Text(
              'Are you sure you want to permanently delete this task? This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                Navigator.pop(context);
                _deleteTask(taskId);
              },
              child: const Text('Delete permanently'),
            ),
          ],
        );
      },
    );
  }
}
