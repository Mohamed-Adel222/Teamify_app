import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchAction = ''; // '', 'LOGIN', 'UPDATE', 'DELETE'
  String _searchEntity = ''; // '', 'User', 'Project', 'Task'
  int _currentPage = 1;
  int _totalPages = 1;
  bool _loading = false;
  List<dynamic> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _searchCtrl.addListener(() {
      setState(() => _currentPage = 1);
      _loadLogs();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final res = await context
          .read<AppServices>()
          .admin
          .listLogs(
            action: _searchAction,
            entity: _searchEntity,
            search: _searchCtrl.text.trim(),
            page: _currentPage,
            perPage: 20,
          )
          .unwrap();

      setState(() {
        _logs = res['items'] as List? ?? [];
        _totalPages = res['pages'] ?? 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load logs: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('System Audit Logs',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () {
              setState(() => _currentPage = 1);
              _loadLogs();
            },
          )
        ],
      ),
      body: Column(
        children: [
          // Filter Row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search logs by action, entity, or details…',
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search,
                          color: AppColors.textSecondary, size: 20),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButton<String>(
                          value: _searchAction,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                                value: '',
                                child: Text('All Actions',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'LOGIN',
                                child: Text('Login Only',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'CREATE',
                                child: Text('Create Only',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'UPDATE',
                                child: Text('Update Only',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'DELETE',
                                child: Text('Delete Only',
                                    style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _searchAction = val ?? '';
                              _currentPage = 1;
                            });
                            _loadLogs();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButton<String>(
                          value: _searchEntity,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                                value: '',
                                child: Text('All Entities',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'User',
                                child: Text('User Entity',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Project',
                                child: Text('Project Entity',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Task',
                                child: Text('Task Entity',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Dispute',
                                child: Text('Dispute Entity',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'FileMetadata',
                                child: Text('File Entity',
                                    style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _searchEntity = val ?? '';
                              _currentPage = 1;
                            });
                            _loadLogs();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Logs List
          Expanded(
            child: _loading && _logs.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? const Center(
                        child: Text('No system audit logs found',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: () async {
                          setState(() => _currentPage = 1);
                          await _loadLogs();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final log = _logs[index] as Map<String, dynamic>;
                            final action = log['action'] ?? 'ACTION';
                            final entity = log['entity'] ?? 'General';
                            final details = log['details'] ?? '';
                            final userName =
                                log['user_name'] ?? 'System/Unknown';
                            final createdAt = (log['created_at'] ?? '')
                                .toString()
                                .replaceAll('T', ' ')
                                .split('.')
                                .first;

                            final isDelete =
                                action.toString().contains('DELETE') ||
                                    action.toString().contains('REJECT');
                            final isCreate =
                                action.toString().contains('CREATE') ||
                                    action.toString().contains('APPROVE');

                            return TCard(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              isDelete
                                                  ? Icons.delete_outline
                                                  : isCreate
                                                      ? Icons.add_circle_outline
                                                      : Icons.info_outline,
                                              color: isDelete
                                                  ? AppColors.error
                                                  : isCreate
                                                      ? AppColors.success
                                                      : AppColors.primary,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$action on $entity',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: AppColors.textPrimary),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          createdAt,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 16),
                                    Text(
                                      details,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.person_outline,
                                                size: 12,
                                                color: AppColors.textSecondary),
                                            const SizedBox(width: 4),
                                            Text(
                                              'By: $userName',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textSecondary),
                                            ),
                                          ],
                                        ),
                                        TChip(
                                          label: 'ID: ${log['id']}',
                                          bg: AppColors.border
                                              .withValues(alpha: 0.2),
                                          textColor: AppColors.textSecondary,
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
                            _loadLogs();
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
                            _loadLogs();
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
}
