import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../data/models/admin_announcement_model.dart';
import '../../services/app_services.dart';
import '../../widgets/admin_announcement_widgets.dart';
import '../../widgets/widgets.dart';

/// Broadcast history from `GET /admin/notifications/history`, plus an entry
/// point for sending a new announcement.
class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<AdminAnnouncement> _items = const [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result =
        await context.read<AppServices>().admin.listBroadcastHistory();
    if (!mounted) return;
    result.when(
      success: (data) {
        final rows = (data['items'] as List?) ?? const [];
        setState(() {
          _items = rows
              .whereType<Map>()
              .map((row) => AdminAnnouncement.fromBroadcast(
                  Map<String, dynamic>.from(row)))
              .toList();
          _loading = false;
        });
      },
      failure: (error) => setState(() {
        _error = error;
        _loading = false;
      }),
    );
  }

  List<AdminAnnouncement> get _filteredItems {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) return _items;
    return _items.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.message.toLowerCase().contains(query) ||
          item.audience.label.toLowerCase().contains(query);
    }).toList();
  }

  void _handleAction(String action, AdminAnnouncement item) {
    switch (action) {
      case 'preview':
        _openPreview(item);
        break;
      case 'resend':
        _openCreate(prefill: item);
        break;
    }
  }

  Future<void> _openPreview(AdminAnnouncement item) async {
    final sent = await Navigator.pushNamed(
      context,
      R.adminAnnouncementsPreview,
      arguments: item,
    );
    if (sent == true) _load();
  }

  Future<void> _openCreate({AdminAnnouncement? prefill}) async {
    final sent = await Navigator.pushNamed(
      context,
      R.adminAnnouncementsCreate,
      arguments: prefill,
    );
    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 18, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Admin Announcements',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Create Announcement',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AnnouncementSearchBar(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val),
              onClear: () => setState(() {
                _searchCtrl.clear();
                _searchQuery = '';
              }),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TButton(label: 'Retry', onTap: _load),
            ],
          ),
        ),
      );
    }

    final visible = _filteredItems;
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: AnnouncementEmptyState(
                title: 'No announcements sent yet',
                message: _searchQuery.isEmpty
                    ? 'Broadcasts you send to users will be listed here.'
                    : 'No announcements match your search.',
                onCreatePressed: _searchQuery.isEmpty ? _openCreate : null,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: visible.length,
        itemBuilder: (ctx, i) {
          final item = visible[i];
          return AnnouncementCard(
            announcement: item,
            onTap: () => _openPreview(item),
            onActionSelected: (act) => _handleAction(act, item),
          );
        },
      ),
    );
  }
}
