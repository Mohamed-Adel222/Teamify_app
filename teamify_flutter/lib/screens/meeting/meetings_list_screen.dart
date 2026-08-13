import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/observability/app_logger.dart';
import '../../core/theme.dart';
import '../../data/models/api_meeting.dart';
import '../../data/models/api_helpers.dart';
import '../../services/app_services.dart';
import 'meeting_preview_screen.dart';
import 'meeting_screens.dart';

class MeetingsListScreen extends StatefulWidget {
  const MeetingsListScreen({super.key});

  @override
  State<MeetingsListScreen> createState() => _MeetingsListScreenState();
}

class _MeetingsListScreenState extends State<MeetingsListScreen> {
  String _tab = 'All';
  bool _loading = true;
  String? _error;
  List<ApiMeeting> _meetings = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  List<ApiMeeting> get _filtered {
    if (_tab == 'Upcoming') {
      return _meetings.where((m) => m.isLive || m.isScheduled).toList();
    }
    if (_tab == 'Ended') {
      return _meetings.where((m) => m.isEnded).toList();
    }
    return _meetings;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await context.read<AppServices>().meetings.listMeetings();
    if (!mounted) return;
    if (!result.isSuccess) {
      AppLogger.error('Failed to load meetings', result.error);
      setState(() {
        _loading = false;
        _error = result.error ?? 'Could not load meetings';
      });
      return;
    }
    setState(() {
      _meetings = result.data ?? [];
      _loading = false;
    });
  }

  Future<void> _createFromChat() async {
    final roomsResult = await context.read<AppServices>().chat.listRooms();
    if (!mounted) return;
    if (!roomsResult.isSuccess || (roomsResult.data ?? []).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            roomsResult.error ??
                'Open a team chat or DM first, then start a meeting from there.',
          ),
        ),
      );
      return;
    }
    final rooms = roomsResult.data!;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Start an instant meeting',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            for (final room in rooms)
              ListTile(
                title: Text(room['name']?.toString() ?? 'Chat ${room['id']}'),
                subtitle: Text(
                  room['is_group'] == true ? 'Team chat' : 'Direct message',
                ),
                onTap: () => Navigator.pop(ctx, room),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final roomId = int.tryParse(selected['id']?.toString() ?? '');
    if (roomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That chat does not have a valid room id.')),
      );
      return;
    }
    try {
      final meeting = await context
          .read<AppServices>()
          .meetings
          .createMeeting(
            chatRoomId: roomId,
            projectId: int.tryParse(selected['project_id']?.toString() ?? ''),
            title: '${selected['name'] ?? 'Team'} meeting',
          )
          .unwrap();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingPreviewScreen(publicId: meeting.publicId),
        ),
      );
      await _load();
    } catch (e, st) {
      AppLogger.error('Create meeting failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create meeting: $e')),
        );
      }
    }
  }

  void _open(ApiMeeting meeting) {
    if (meeting.isEnded) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingSummaryScreen(
            roomName: meeting.title,
            roomId: meeting.chatRoomId,
            projectId: meeting.projectId,
            initialSession: meeting.session,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingPreviewScreen(publicId: meeting.publicId),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Meetings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_call),
            onPressed: _createFromChat,
            tooltip: 'Start meeting',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _chip('All'),
                const SizedBox(width: 8),
                _chip('Upcoming'),
                const SizedBox(width: 8),
                _chip('Ended'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                                onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _filtered.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 80),
                                  Center(
                                    child: Text(
                                      'No meetings yet. Start one from Team Chat or a DM.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) =>
                                    _card(_filtered[i]),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    final selected = _tab == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _tab = label),
    );
  }

  Widget _card(ApiMeeting m) {
    final when = m.startsAt ?? m.createdAt ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                _statusPill(m),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (m.hostName.isNotEmpty) 'Host: ${m.hostName}',
                if ((m.projectName ?? '').isNotEmpty) m.projectName!,
                if (when.isNotEmpty) formatRelativeTime(when),
                '${m.participantCount} participants',
              ].join(' · '),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => _open(m),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      m.isLive ? AppColors.success : AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(m.isEnded ? 'View summary' : 'Join'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(ApiMeeting m) {
    final color = m.isLive
        ? AppColors.success
        : m.isEnded
            ? AppColors.textSecondary
            : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        m.status.toUpperCase(),
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
