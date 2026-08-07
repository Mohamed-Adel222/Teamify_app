import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

class AdminFilesScreen extends StatefulWidget {
  const AdminFilesScreen({super.key});

  @override
  State<AdminFilesScreen> createState() => _AdminFilesScreenState();
}

class _AdminFilesScreenState extends State<AdminFilesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _currentPage = 1;
  int _totalPages = 1;
  bool _loading = false;
  List<dynamic> _files = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim();
        _currentPage = 1;
      });
      _loadFiles();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final res = await context
          .read<AppServices>()
          .admin
          .listFiles(
            search: _searchQuery,
            page: _currentPage,
          )
          .unwrap();

      setState(() {
        _files = res['items'] as List? ?? [];
        _totalPages = res['pages'] ?? 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load files: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteFile(String fileId) async {
    try {
      await context.read<AppServices>().admin.deleteFile(fileId).unwrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('File record permanently deleted'),
            backgroundColor: AppColors.success),
      );
      _loadFiles();
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
        title: const Text('File Management',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search uploads by filename...',
                  border: InputBorder.none,
                  prefixIcon:
                      Icon(Icons.search, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),

          // File List
          Expanded(
            child: _loading && _files.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? const Center(
                        child: Text('No files found on server',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: _loadFiles,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            final f = _files[index] as Map<String, dynamic>;
                            final double sizeMb =
                                ((f['size_bytes'] ?? 0) as num).toDouble() /
                                    (1024.0 * 1024.0);
                            final String uploadDate = (f['created_at'] ?? '')
                                .toString()
                                .split('T')
                                .first;

                            return TCard(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                      Icons.insert_drive_file_outlined,
                                      color: AppColors.primary,
                                      size: 20),
                                ),
                                title: Text(f['filename'] ?? 'File',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                subtitle: Text(
                                  'Owner: ${f['owner_name'] ?? 'System'} · Size: ${sizeMb.toStringAsFixed(2)} MB · Uploaded: $uploadDate',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppColors.error),
                                  onPressed: () => _showDeleteConfirmation(
                                      f['id'].toString()),
                                  tooltip: 'Delete File',
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
                            _loadFiles();
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
                            _loadFiles();
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

  void _showDeleteConfirmation(String fileId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete File Pointer'),
          content: const Text(
              'Are you sure you want to permanently delete this file metadata from the database? Users will lose access immediately.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                Navigator.pop(context);
                _deleteFile(fileId);
              },
              child: const Text('Delete permanently'),
            ),
          ],
        );
      },
    );
  }
}
