import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

class AdminDisputesScreen extends StatefulWidget {
  const AdminDisputesScreen({super.key});

  @override
  State<AdminDisputesScreen> createState() => _AdminDisputesScreenState();
}

class _AdminDisputesScreenState extends State<AdminDisputesScreen> {
  String _filterStatus = ''; // '', 'open', 'resolved', 'dismissed'
  String _filterCategory =
      ''; // '', 'payment', 'behaviour', 'quality', 'deadline', 'other'
  int _currentPage = 1;
  int _totalPages = 1;
  bool _loading = false;
  List<dynamic> _disputes = [];

  @override
  void initState() {
    super.initState();
    _loadDisputes();
  }

  Future<void> _loadDisputes() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final res = await context
          .read<AppServices>()
          .admin
          .listDisputes(
            status: _filterStatus,
            category: _filterCategory,
            page: _currentPage,
          )
          .unwrap();

      setState(() {
        _disputes = res['items'] as List? ?? [];
        _totalPages = res['pages'] ?? 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load disputes: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveDispute(
      String disputeId, String action, String resolution) async {
    try {
      await context
          .read<AppServices>()
          .admin
          .resolveDispute(disputeId, action, resolution)
          .unwrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Dispute marked as $action successfully'),
            backgroundColor: AppColors.success),
      );
      _loadDisputes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openDisputeDetail(String disputeId) async {
    try {
      final res = await context
          .read<AppServices>()
          .admin
          .getDisputeDetail(disputeId)
          .unwrap();
      if (!mounted) return;
      final dispute = res['dispute'] as Map<String, dynamic>? ?? {};
      final reporter = dispute['reporter'] as Map<String, dynamic>?;
      final accused = dispute['accused'] as Map<String, dynamic>?;
      final resolutionCtrl = TextEditingController();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Dispute #${dispute['id']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(dispute['subject']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Category: ${dispute['category']}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 12),
                  Text(dispute['description']?.toString() ?? ''),
                  const Divider(height: 24),
                  if (reporter != null)
                    Text(
                        'Reporter: ${reporter['full_name'] ?? reporter['display_name']} (${reporter['email']})'),
                  if (accused != null)
                    Text(
                        'Accused: ${accused['full_name'] ?? accused['display_name']} (${accused['email']})'),
                  if (dispute['project_name'] != null)
                    Text('Project: ${dispute['project_name']}'),
                  if (dispute['status'] == 'open' ||
                      dispute['status'] == 'pending') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: resolutionCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Resolution notes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _resolveDispute(disputeId, 'resolve',
                                  resolutionCtrl.text.trim());
                            },
                            child: const Text('Resolve'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _resolveDispute(disputeId, 'reject',
                                  resolutionCtrl.text.trim());
                            },
                            child: const Text('Dismiss'),
                          ),
                        ),
                      ],
                    ),
                  ] else if (dispute['resolution'] != null)
                    Text('Resolution: ${dispute['resolution']}',
                        style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not load dispute: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Disputes Management',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Filters
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
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
                      value: _filterStatus,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                            value: '',
                            child: Text('All Statuses',
                                style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                            value: 'open',
                            child:
                                Text('Open', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                            value: 'resolved',
                            child: Text('Resolved',
                                style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                            value: 'dismissed',
                            child: Text('Dismissed',
                                style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _filterStatus = val ?? '';
                          _currentPage = 1;
                        });
                        _loadDisputes();
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
                      value: _filterCategory,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                            value: '',
                            child: Text('All Categories',
                                style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                            value: 'payment',
                            child: Text('Payment',
                                style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                            value: 'behaviour',
                            child: Text('Behaviour',
                                style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                            value: 'quality',
                            child: Text('Quality',
                                style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                            value: 'deadline',
                            child: Text('Deadline',
                                style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(
                            value: 'other',
                            child:
                                Text('Other', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _filterCategory = val ?? '';
                          _currentPage = 1;
                        });
                        _loadDisputes();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Disputes List
          Expanded(
            child: _loading && _disputes.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _disputes.isEmpty
                    ? const Center(
                        child: Text('No disputes registered',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: _loadDisputes,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _disputes.length,
                          itemBuilder: (context, index) {
                            final d = _disputes[index] as Map<String, dynamic>;
                            final String status = d['status'] ?? 'open';
                            final isClosed =
                                status == 'resolved' || status == 'dismissed';

                            return TCard(
                              margin: const EdgeInsets.only(bottom: 10),
                              onTap: () =>
                                  _openDisputeDetail(d['id'].toString()),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('DISPUTE #${d['id']}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: AppColors.primary)),
                                        TChip(
                                          label: status.toUpperCase(),
                                          bg: status == 'resolved'
                                              ? AppColors.success
                                                  .withValues(alpha: 0.1)
                                              : status == 'dismissed'
                                                  ? AppColors.error
                                                      .withValues(alpha: 0.1)
                                                  : AppColors.warning
                                                      .withValues(alpha: 0.1),
                                          textColor: status == 'resolved'
                                              ? AppColors.success
                                              : status == 'dismissed'
                                                  ? AppColors.error
                                                  : AppColors.warning,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                        'Subject: ${d['subject'] ?? 'Grievance'}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14)),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Category: ${d['category']?.toUpperCase() ?? 'OTHER'}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary)),
                                    const SizedBox(height: 8),
                                    Text(
                                      d['description'] ?? '',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                            'Reporter: ${d['reporter_name'] ?? 'User'}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                                fontWeight: FontWeight.bold)),
                                        Text(
                                            'Accused: ${d['accused_name'] ?? 'User'}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    if (isClosed &&
                                        d['resolution'] != null) ...[
                                      const Divider(height: 20),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                            color: AppColors.border
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        child: Text(
                                          'Resolution: ${d['resolution']}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic,
                                              color: AppColors.textPrimary),
                                        ),
                                      ),
                                    ],
                                    if (!isClosed) ...[
                                      const Divider(height: 24),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.success),
                                            onPressed: () => _showResolveDialog(
                                                d['id'].toString(), 'resolve'),
                                            child: const Text('Resolve',
                                                style: TextStyle(fontSize: 12)),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton(
                                            onPressed: () => _showResolveDialog(
                                                d['id'].toString(), 'reject'),
                                            child: const Text('Dismiss',
                                                style: TextStyle(fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ],
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
                            _loadDisputes();
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
                            _loadDisputes();
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

  void _showResolveDialog(String disputeId, String action) {
    final resolutionCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              Text(action == 'resolve' ? 'Resolve Dispute' : 'Dismiss Dispute'),
          content: TextField(
            controller: resolutionCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Enter formal decision/resolution notes...'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final notes = resolutionCtrl.text.trim();
                if (notes.isEmpty) return;
                Navigator.pop(context);
                _resolveDispute(disputeId, action, notes);
              },
              child: const Text('Submit Decision'),
            ),
          ],
        );
      },
    );
  }
}
