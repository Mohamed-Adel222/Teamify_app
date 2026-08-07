import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/models/api_user.dart';
import '../../core/network/api_result.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import 'package:provider/provider.dart';

/// Searchable user picker dialog for admin reassignment flows.
Future<ApiUser?> showAdminUserPicker(
  BuildContext context, {
  String title = 'Select User',
  String? excludeUserId,
}) async {
  return showDialog<ApiUser>(
    context: context,
    builder: (ctx) => _AdminUserPickerDialog(
      title: title,
      excludeUserId: excludeUserId,
    ),
  );
}

class _AdminUserPickerDialog extends StatefulWidget {
  const _AdminUserPickerDialog({required this.title, this.excludeUserId});

  final String title;
  final String? excludeUserId;

  @override
  State<_AdminUserPickerDialog> createState() => _AdminUserPickerDialogState();
}

class _AdminUserPickerDialogState extends State<_AdminUserPickerDialog> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  List<ApiUser> _users = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
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
    try {
      final res = await context
          .read<AppServices>()
          .admin
          .listUsers(perPage: 200)
          .unwrap();
      final items = (res['items'] as List? ?? [])
          .map((e) => ApiUser.fromJson(e as Map<String, dynamic>))
          .where((u) => u.id != widget.excludeUserId)
          .toList();
      if (mounted) setState(() => _users = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ApiUser> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      return u.primaryName.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.displayRole.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search by name or email…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: AppColors.error)))
                      : filtered.isEmpty
                          ? const Center(child: Text('No users found'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final u = filtered[i];
                                return ListTile(
                                  leading:
                                      TAvatar(initials: u.initials, radius: 18),
                                  title: Text(u.primaryName),
                                  subtitle:
                                      Text('${u.email} · ${u.displayRole}'),
                                  onTap: () => Navigator.pop(context, u),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
      ],
    );
  }
}
