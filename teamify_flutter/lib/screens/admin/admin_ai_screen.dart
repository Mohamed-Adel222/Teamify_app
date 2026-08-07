import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

class AdminAiScreen extends StatefulWidget {
  const AdminAiScreen({super.key});

  @override
  State<AdminAiScreen> createState() => _AdminAiScreenState();
}

class _AdminAiScreenState extends State<AdminAiScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI Monitor & Limits', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Plans & Limits'),
            Tab(text: 'Users'),
            Tab(text: 'Logs'),
            Tab(text: 'Alerts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _OverviewTab(),
          _PlansTab(),
          _UsersTab(),
          _LogsTab(),
          _AlertsTab(),
        ],
      ),
    );
  }
}

// ── Overview Tab ─────────────────────────────────────────────────────────────
class _OverviewTab extends StatefulWidget {
  const _OverviewTab();
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}
class _OverviewTabState extends State<_OverviewTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await context.read<AppServices>().admin.getAiUsageOverview();
    if (!mounted) return;
    setState(() {
      _data = res.data?['metrics'] ?? res.data ?? {};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final d = _data ?? {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _metricCard('Requests (Today)', '${d['total_ai_requests'] ?? 0}', Icons.bar_chart, AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Requests (Month)', '${d['total_ai_requests_month'] ?? 0}', Icons.calendar_today, AppColors.accent)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _metricCard('Active Users', '${d['active_ai_users'] ?? 0}', Icons.people, AppColors.success)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Reached Limits', '${d['users_reached_limits'] ?? 0}', Icons.warning_amber_rounded, AppColors.warning)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _metricCard('Failed Requests', '${d['failed_ai_calls'] ?? d['failed_ai_requests'] ?? 0}', Icons.error_outline, AppColors.error)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Avg Latency', '${d['average_response_time'] ?? '0.0'}s', Icons.timer_outlined, AppColors.success)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _metricCard('Tokens Used', '${d['token_usage'] ?? d['total_tokens_used'] ?? 0}', Icons.generating_tokens, AppColors.primaryDark)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('Est. Cost', '\$${d['estimated_ai_cost'] ?? '0.00'}', Icons.monetization_on_outlined, AppColors.warning)),
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
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Plans Tab ────────────────────────────────────────────────────────────────
class _PlansTab extends StatefulWidget {
  const _PlansTab();
  @override
  State<_PlansTab> createState() => _PlansTabState();
}
class _PlansTabState extends State<_PlansTab> {
  List<dynamic> _plans = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await context.read<AppServices>().admin.getAiPlans();
    if (!mounted) return;
    setState(() {
      _plans = res.data?['items'] as List? ?? [];
      _loading = false;
    });
  }

  void _editPlan(Map<String, dynamic> plan) {
    final dailyCtrl = TextEditingController(text: plan['daily_limit']?.toString());
    final monthlyCtrl = TextEditingController(text: plan['monthly_limit']?.toString());
    final tokenCtrl = TextEditingController(text: plan['token_limit']?.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${plan['name']} Plan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: dailyCtrl, decoration: const InputDecoration(labelText: 'Daily Request Limit'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: monthlyCtrl, decoration: const InputDecoration(labelText: 'Monthly Request Limit'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: tokenCtrl, decoration: const InputDecoration(labelText: 'Token Limit'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final req = {
                'daily_limit': int.tryParse(dailyCtrl.text) ?? plan['daily_limit'],
                'monthly_limit': int.tryParse(monthlyCtrl.text) ?? plan['monthly_limit'],
                'token_limit': int.tryParse(tokenCtrl.text) ?? plan['token_limit'],
              };
              await context.read<AppServices>().admin.updateAiPlanLimits(plan['id'], req);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan updated successfully')));
                _load();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _plans.length,
        itemBuilder: (_, i) {
          final p = _plans[i] as Map<String, dynamic>;
          return TCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.edit, color: AppColors.primary), onPressed: () => _editPlan(p)),
                    ],
                  ),
                  const Divider(),
                  Text('Daily Limit: ${p['daily_limit']}'),
                  Text('Monthly Limit: ${p['monthly_limit']}'),
                  Text('Token Limit: ${p['token_limit']}'),
                  Text('Subscribers: ${p['subscribers']}'),
                  Text('Est. Cost/User: \$${p['estimated_cost']}'),
                  const SizedBox(height: 8),
                  Text('Features: ${(p['features'] as List?)?.join(', ') ?? 'None'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Users Tab ────────────────────────────────────────────────────────────────
class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}
class _UsersTabState extends State<_UsersTab> {
  List<dynamic> _users = [];
  bool _loading = true;

  final _searchCtrl = TextEditingController();
  String _search = '';
  String _plan = 'All';
  String _status = 'All';
  String _sort = 'Usage';

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await context.read<AppServices>().admin.getUserAiUsage(
      search: _search, planId: _plan, status: _status, sortBy: _sort, page: 1
    );
    if (!mounted) return;
    setState(() {
      _users = res.data?['items'] as List? ?? [];
      _loading = false;
    });
  }

  void _showDetails(String userId) async {
    final res = await context.read<AppServices>().admin.getUserAiUsageDetails(userId);
    if (!mounted || res.data == null) return;
    final u = res.data!;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _UserDetailsSheet(
        user: u,
        onAction: _load,
      ),
    );
  }

  Color _getStatusColor(String s) {
    if (s == 'Limit Reached') return AppColors.error;
    if (s == 'Near Limit') return AppColors.warning;
    if (s == 'Suspended') return Colors.grey;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search users...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.cardBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onChanged: (v) { _search = v; _load(); },
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _dropdown(_plan, ['All', 'Free', 'Premium', 'Business'], (v) { _plan = v!; _load(); }),
                    const SizedBox(width: 8),
                    _dropdown(_status, ['All', 'Normal', 'Near Limit', 'Limit Reached', 'Suspended'], (v) { _status = v!; _load(); }),
                    const SizedBox(width: 8),
                    _dropdown(_sort, ['Usage', 'Tokens', 'Cost', 'Remaining'], (v) { _sort = v!; _load(); }),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i] as Map<String, dynamic>;
                final pct = (u['used_month'] ?? 0) / (u['monthly_limit'] ?? 1);
                return TCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => _showDetails(u['user_id']),
                    title: Text('${u['user_name']} (${u['plan_name']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${u['role']} • ${u['used_month']}/${u['monthly_limit']} month'),
                        LinearProgressIndicator(value: (pct as num).clamp(0.0, 1.0).toDouble(), color: _getStatusColor(u['status'] ?? '')),
                      ],
                    ),
                    trailing: TChip(
                      label: u['status'] ?? 'Normal',
                      bg: _getStatusColor(u['status'] ?? '').withValues(alpha: 0.1),
                      textColor: _getStatusColor(u['status'] ?? ''),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown(String val, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8), color: AppColors.cardBg),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: val,
          isDense: true,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _UserDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onAction;

  const _UserDetailsSheet({required this.user, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AppServices>().admin;
    final uid = user['user_id'];
    return Container(
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.8,
      child: ListView(
        children: [
          Text('User AI Details', style: Theme.of(context).textTheme.titleLarge),
          const Divider(),
          Text('Name: ${user['user_name']}'),
          Text('Plan: ${user['plan_name']}'),
          Text('Status: ${user['status']}'),
          const SizedBox(height: 12),
          Text('Daily: ${user['used_today']} / ${user['daily_limit']}'),
          Text('Monthly: ${user['used_month']} / ${user['monthly_limit']}'),
          Text('Tokens: ${user['tokens_used']} / ${user['token_limit']}'),
          Text('Cost: \$${user['estimated_cost']}'),
          const Divider(),
          const Text('Admin Actions', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Reset Daily'),
                onPressed: () async {
                  await admin.resetUserDailyUsage(uid);
                  onAction();
                  if(context.mounted) Navigator.pop(context);
                },
              ),
              ActionChip(
                label: const Text('Reset Monthly'),
                onPressed: () async {
                  await admin.resetUserMonthlyUsage(uid);
                  onAction();
                  if(context.mounted) Navigator.pop(context);
                },
              ),
              if (user['status'] == 'Suspended')
                ActionChip(
                  label: const Text('Restore Access'),
                  onPressed: () async {
                    await admin.restoreUserAiAccess(uid);
                    onAction();
                    if(context.mounted) Navigator.pop(context);
                  },
                )
              else
                ActionChip(
                  label: const Text('Suspend Access'),
                  backgroundColor: AppColors.error.withValues(alpha: 0.2),
                  onPressed: () async {
                    await admin.suspendUserAiAccess(uid);
                    onAction();
                    if(context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Change Plan:', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: ['Free', 'Premium', 'Business'].map((p) => ActionChip(
              label: Text(p),
              onPressed: () async {
                await admin.changeUserPlan(uid, 'plan_${p.toLowerCase()}');
                onAction();
                if(context.mounted) Navigator.pop(context);
              },
            )).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Logs Tab ─────────────────────────────────────────────────────────────────
class _LogsTab extends StatefulWidget {
  const _LogsTab();
  @override
  State<_LogsTab> createState() => _LogsTabState();
}
class _LogsTabState extends State<_LogsTab> {
  List<dynamic> _logs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await context.read<AppServices>().admin.getAiRequestLogs();
    if (!mounted) return;
    setState(() {
      _logs = res.data?['items'] as List? ?? [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _logs.length,
        itemBuilder: (_, i) {
          final l = _logs[i] as Map<String, dynamic>;
          final ok = l['status'] == 'success';
          return TCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(ok ? Icons.check_circle : Icons.error, color: ok ? AppColors.success : AppColors.error),
              title: Text('${l['feature']} - ${l['user_name']}'),
              subtitle: Text('${l['timestamp']} • Tokens: ${l['tokens']} • ${l['latency']}s\n${l['error'] ?? ''}'),
              isThreeLine: l['error'] != null,
            ),
          );
        },
      ),
    );
  }
}

// ── Alerts Tab ───────────────────────────────────────────────────────────────
class _AlertsTab extends StatefulWidget {
  const _AlertsTab();
  @override
  State<_AlertsTab> createState() => _AlertsTabState();
}
class _AlertsTabState extends State<_AlertsTab> {
  List<dynamic> _alerts = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await context.read<AppServices>().admin.getAiUsageAlerts();
    if (!mounted) return;
    setState(() {
      _alerts = res.data?['items'] as List? ?? [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 48, color: AppColors.success),
            const SizedBox(height: 16),
            const Text('No active AI alerts.', style: TextStyle(color: AppColors.textSecondary)),
            TextButton(onPressed: _load, child: const Text('Refresh'))
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _alerts.length,
        itemBuilder: (_, i) {
          final a = _alerts[i] as Map<String, dynamic>;
          return TCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
              title: Text(a['type'] ?? 'Alert', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${a['message']}\n${a['timestamp']}'),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.check, color: AppColors.success),
                onPressed: () async {
                  await context.read<AppServices>().admin.resolveAiUsageAlert(a['id']);
                  _load();
                  if(context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alert resolved')));
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
