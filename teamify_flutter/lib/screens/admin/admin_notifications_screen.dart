import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/admin_user_picker.dart';
import '../../widgets/widgets.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  String _target = 'all';
  bool _sending = false;
  bool _loadingHistory = false;
  List<dynamic> _history = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final res = await context
          .read<AppServices>()
          .admin
          .listBroadcastHistory()
          .unwrap();
      if (mounted) setState(() => _history = res['items'] as List? ?? []);
    } catch (_) {
      if (mounted) setState(() => _history = []);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _sendAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);

    try {
      String? specificId;
      if (_target == 'specific') {
        final user =
            await showAdminUserPicker(context, title: 'Select recipient');
        if (!mounted) return;
        if (user == null) return;
        specificId = user.id;
      }

      await context
          .read<AppServices>()
          .admin
          .broadcastNotification(
            _target,
            _titleCtrl.text.trim(),
            _bodyCtrl.text.trim(),
            userId: specificId,
          )
          .unwrap();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Announcement successfully broadcasted!'),
              backgroundColor: AppColors.success),
        );
        _titleCtrl.clear();
        _bodyCtrl.clear();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Broadcast failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Announcement Center',
            style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Compose'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const TSectionHeader(title: 'Broadcast Announcement'),
                const SizedBox(height: 16),
                TCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Target Audience',
                            border: OutlineInputBorder()),
                        child: DropdownButton<String>(
                          value: _target,
                          isExpanded: true,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                                value: 'all', child: Text('All Users')),
                            DropdownMenuItem(
                                value: 'students',
                                child: Text('Students Only')),
                            DropdownMenuItem(
                                value: 'freelancers',
                                child: Text('Freelancers Only')),
                            DropdownMenuItem(
                                value: 'specific',
                                child: Text('Specific User (picker)')),
                          ],
                          onChanged: (v) =>
                              setState(() => _target = v ?? 'all'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Title', border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Title required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _bodyCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            labelText: 'Message Body',
                            border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Body required'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _sending ? null : _sendAnnouncement,
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Send Broadcast'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _loadingHistory
              ? const Center(child: CircularProgressIndicator())
              : _history.isEmpty
                  ? const Center(
                      child: Text('No broadcast history yet',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _history.length,
                        itemBuilder: (_, i) {
                          final h = _history[i] as Map<String, dynamic>;
                          return TCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(h['title']?.toString() ?? ''),
                              subtitle: Text(
                                '${h['target_audience']} · ${h['recipient_count']} recipients\n${h['body']}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                (h['sent_at'] ?? '')
                                    .toString()
                                    .replaceAll('T', ' ')
                                    .split('.')
                                    .first,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }
}
