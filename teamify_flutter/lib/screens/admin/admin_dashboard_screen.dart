import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import 'admin_screens.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppServices>().admin.getDashboardStats().unwrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _refresh,
          )
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Error: ${snapshot.error}',
                        style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    TButton(label: 'Retry', onTap: _refresh),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data ?? {};
          final cards = data['cards'] as Map<String, dynamic>? ?? {};
          final charts = data['charts'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Health & Storage Row
              Row(
                children: [
                  Expanded(
                    child: _dashboardStatusCard(
                      'System Health',
                      '${cards['system_health'] ?? 100}%',
                      Icons.health_and_safety_outlined,
                      AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dashboardStatusCard(
                      'Storage Used',
                      '${cards['storage_usage_mb'] ?? 0.0} MB',
                      Icons.storage_outlined,
                      AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // KPI Stats Grid
              const TSectionHeader(title: 'Key Platform Metrics'),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _metricCard('Total Users', '${cards['total_users'] ?? 0}',
                      Icons.people_outline, AppColors.primary),
                  _metricCard(
                      'Active Users (30d)',
                      '${cards['active_users'] ?? 0}',
                      Icons.offline_pin_outlined,
                      AppColors.success),
                  _metricCard(
                      'Total Projects',
                      '${cards['total_projects'] ?? 0}',
                      Icons.assignment_outlined,
                      AppColors.accent),
                  _metricCard(
                      'Pending Disputes',
                      '${cards['pending_disputes'] ?? 0}',
                      Icons.gavel_outlined,
                      AppColors.error),
                  _metricCard('Open Tasks', '${cards['open_tasks'] ?? 0}',
                      Icons.pending_actions_outlined, AppColors.warning),
                  _metricCard(
                      'AI Requests Today',
                      '${cards['ai_requests_today'] ?? 0}',
                      Icons.auto_awesome_outlined,
                      AppColors.primary),
                ],
              ),
              const SizedBox(height: 24),

              // Ratio Charts Section
              const TSectionHeader(title: 'Freelancer vs Student Ratio'),
              const SizedBox(height: 12),
              TCard(
                padding: const EdgeInsets.all(16),
                child: _buildRatioChart(
                    charts['ratios'] as Map<String, dynamic>? ?? {}),
              ),
              const SizedBox(height: 24),

              // Growth Analytics Section
              const TSectionHeader(title: 'User Growth Trend (Last 6 Months)'),
              const SizedBox(height: 12),
              TCard(
                padding: const EdgeInsets.all(16),
                child: _buildGrowthChart(charts['user_growth'] as List? ?? []),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: AdminBottomNav(current: 0, ctx: context),
    );
  }

  Widget _dashboardStatusCard(
      String label, String value, IconData icon, Color color) {
    return TCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return TCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          Text(title,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildRatioChart(Map<String, dynamic> ratios) {
    final int freelancers = ratios['freelancers'] ?? 0;
    final int students = ratios['students'] ?? 0;
    final int others = ratios['others'] ?? 0;
    final int total = freelancers + students + others;

    if (total == 0) {
      return const Center(
          child: Text('No user data available',
              style: TextStyle(color: AppColors.textSecondary)));
    }

    final double fPct = freelancers / total;
    final double sPct = students / total;
    final double oPct = others / total;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
                flex: (fPct * 100).round().clamp(1, 100),
                child: Container(height: 12, color: AppColors.primary)),
            Expanded(
                flex: (sPct * 100).round().clamp(1, 100),
                child: Container(height: 12, color: AppColors.success)),
            if (oPct > 0)
              Expanded(
                  flex: (oPct * 100).round().clamp(1, 100),
                  child: Container(height: 12, color: AppColors.border)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ratioLegend('Freelancers: $freelancers', AppColors.primary),
            _ratioLegend('Students: $students', AppColors.success),
            if (oPct > 0) _ratioLegend('Others: $others', AppColors.border),
          ],
        ),
      ],
    );
  }

  Widget _ratioLegend(String label, Color color) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildGrowthChart(List<dynamic> growthData) {
    if (growthData.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(
            child: Text('No growth trend data',
                style: TextStyle(color: AppColors.textSecondary))),
      );
    }

    // Find maximum count for scale
    int maxVal = 1;
    for (var d in growthData) {
      final int c = (d as Map)['count'] ?? 0;
      if (c > maxVal) maxVal = c;
    }

    return SizedBox(
      height: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: growthData.map((d) {
          final map = d as Map;
          final int count = map['count'] ?? 0;
          final String month = map['month'] ?? '';
          final double ratio = count / maxVal;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 24,
                height: 100 * ratio + 8,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                month.split('-').last,
                style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
