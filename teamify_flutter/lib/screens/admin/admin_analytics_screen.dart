import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/files/file_downloader.dart';
import '../../core/theme.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import 'dart:typed_data';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  String _metric = 'users';
  int _days = 30;
  bool _loading = false;
  List<dynamic> _series = [];
  Map<String, dynamic>? _overview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final admin = context.read<AppServices>().admin;
      final ts = await admin
          .getAnalyticsTimeSeries(metric: _metric, days: _days)
          .unwrap();
      final overview = await admin.getAnalyticsOverview().unwrap();
      if (mounted) {
        setState(() {
          _series = ts['data'] as List? ?? [];
          _overview = overview;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load analytics: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportAnalytics() async {
    try {
      final result =
          await context.read<AppServices>().admin.exportAnalytics('analytics');
      if (!mounted) return;
      await result.when(
        success: (bytes) async {
          if (bytes.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No analytics data to export yet.'),
                backgroundColor: AppColors.error,
              ),
            );
            return;
          }
          await saveDownloadedBytes(
            filename: 'analytics.csv',
            bytes: Uint8List.fromList(bytes),
            mimeType: 'text/csv',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Analytics exported as analytics.csv')),
          );
        },
        failure: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Export failed: $error'),
              backgroundColor: AppColors.error,
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _overview?['users'] as Map? ?? {};
    final tasks = _overview?['tasks'] as Map? ?? {};
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Platform Analytics',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.download), onPressed: _exportAnalytics),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading && _overview == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Metric', border: OutlineInputBorder()),
                        child: DropdownButton<String>(
                          value: _metric,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                                value: 'users', child: Text('Total Users')),
                            DropdownMenuItem(
                                value: 'new_users', child: Text('New Users')),
                            DropdownMenuItem(
                                value: 'projects', child: Text('Projects')),
                            DropdownMenuItem(
                                value: 'tasks_completed',
                                child: Text('Tasks Completed')),
                            DropdownMenuItem(
                                value: 'ai_requests',
                                child: Text('AI Requests')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _metric = v);
                            _load();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Range', border: OutlineInputBorder()),
                        child: DropdownButton<int>(
                          value: _days,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 7, child: Text('7 days')),
                            DropdownMenuItem(value: 30, child: Text('30 days')),
                            DropdownMenuItem(value: 90, child: Text('90 days')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _days = v);
                            _load();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _kpiCard('Users', '${users['total'] ?? '—'}'),
                    _kpiCard('Active', '${users['active'] ?? '—'}'),
                    _kpiCard('Task completion',
                        '${tasks['completion_rate'] ?? '—'}%'),
                    _kpiCard('Overdue tasks', '${tasks['overdue'] ?? '—'}'),
                  ],
                ),
                const SizedBox(height: 20),
                TSectionHeader(title: 'Daily trend (${_series.length} points)'),
                const SizedBox(height: 8),
                if (_series.isEmpty)
                  const TCard(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'No snapshot data yet. Daily job will populate this chart.')))
                else
                  TCard(
                    child: SizedBox(
                      height: 220,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _series.length,
                        itemBuilder: (_, i) {
                          final pt = _series[i] as Map<String, dynamic>;
                          final val = (pt['value'] as num?)?.toDouble() ?? 0;
                          final maxVal = _series.fold<double>(0, (m, e) {
                            final v =
                                ((e as Map)['value'] as num?)?.toDouble() ?? 0;
                            return v > m ? v : m;
                          }).clamp(1, double.infinity);
                          final h = (val / maxVal * 160).clamp(4.0, 160.0);
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('${val.toInt()}',
                                    style: const TextStyle(fontSize: 10)),
                                Container(
                                    width: 18,
                                    height: h,
                                    color: AppColors.primary
                                        .withValues(alpha: 0.85)),
                                const SizedBox(height: 4),
                                Text((pt['date'] ?? '').toString().substring(5),
                                    style: const TextStyle(fontSize: 9)),
                              ],
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

  Widget _kpiCard(String label, String value) {
    return SizedBox(
      width: 160,
      child: TCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
