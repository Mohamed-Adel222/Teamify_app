import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/audio/meeting_browser_speech.dart';
import '../../core/audio/meeting_speech_recorder.dart';
import '../../core/files/file_downloader.dart';
import '../../core/files/file_actions.dart';
import '../../core/network/api_result.dart';
import '../../core/network/websocket_manager.dart';
import '../../core/theme.dart';
import '../../core/routes.dart';
import '../../core/session/session_controller.dart';
import '../../data/models/models.dart';
import '../../data/models/notification_preferences_model.dart';
import '../../services/notification_event_dispatcher.dart';
import '../../models/models.dart';
import '../../config/app_config.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import '../meeting/meeting_screens.dart';
import 'chat_room_utils.dart';

String _initialsFromName(String name) {
  final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'U';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

TextDirection getTextDirection(String text) {
  if (text.isEmpty) return TextDirection.ltr;
  for (int i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    // Ignore whitespace, ASCII punctuation, digits (0-9), and basic symbols
    if (code <= 0x0040 ||
        (code >= 0x005B && code <= 0x0060) ||
        (code >= 0x007B && code <= 0x007F)) {
      continue;
    }
    // Check for Arabic Unicode Ranges
    if ((code >= 0x0600 && code <= 0x06FF) ||
        (code >= 0x0750 && code <= 0x077F) ||
        (code >= 0x08A0 && code <= 0x08FF) ||
        (code >= 0xFB50 && code <= 0xFDFF) ||
        (code >= 0xFE70 && code <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    // Latin script
    if ((code >= 0x0041 && code <= 0x005A) ||
        (code >= 0x0061 && code <= 0x007A)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}

TextAlign getTextAlign(TextDirection dir) =>
    dir == TextDirection.rtl ? TextAlign.right : TextAlign.left;

enum MockUserPresence { online, away, offline }

MockUserPresence _getMockPresence(String identifier) {
  final lower = identifier.toLowerCase();
  if (lower.contains('you') || lower.contains('alex')) {
    return MockUserPresence.online;
  }
  final hash = identifier.hashCode.abs();
  final mod = hash % 3;
  if (mod == 0) return MockUserPresence.online;
  if (mod == 1) return MockUserPresence.away;
  return MockUserPresence.offline;
}

Color _getPresenceColor(MockUserPresence presence) {
  switch (presence) {
    case MockUserPresence.online:
      return AppColors.success;
    case MockUserPresence.away:
      return Colors.orange;
    case MockUserPresence.offline:
      return Colors.grey;
  }
}

String _getPresenceLabel(MockUserPresence presence) {
  switch (presence) {
    case MockUserPresence.online:
      return 'Online';
    case MockUserPresence.away:
      return 'Away';
    case MockUserPresence.offline:
      return 'Last seen recently';
  }
}

DateTime? _parseMessageDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  var parsed = DateTime.tryParse(iso);
  if (parsed != null) return parsed.toLocal();
  // SQLite / API sometimes returns "2026-05-25 10:00:00" without "T".
  final normalized = iso.contains(' ') && !iso.contains('T')
      ? iso.replaceFirst(' ', 'T')
      : iso;
  parsed = DateTime.tryParse(normalized);
  if (parsed != null) return parsed.toLocal();
  if (!iso.endsWith('Z') && !iso.contains('+')) {
    parsed = DateTime.tryParse('${normalized}Z');
    if (parsed != null) return parsed.toLocal();
  }
  return null;
}

String _formatChatDateLabel(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  const months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  final month = months[dt.month - 1];
  if (dt.year == now.year) return '${dt.day} $month';
  return '${dt.day} $month ${dt.year}';
}

class _ChatListItem {
  final String? dateLabel;
  final ChatMessage? message;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const _ChatListItem.date(this.dateLabel)
      : message = null,
        isFirstInGroup = false,
        isLastInGroup = false;

  const _ChatListItem.msg(
    this.message, {
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  }) : dateLabel = null;
}

bool _sameMessageGroup(ChatMessage a, ChatMessage b) {
  if (a.isMe != b.isMe) return false;
  if (a.senderId.isNotEmpty && b.senderId.isNotEmpty) {
    if (a.senderId != b.senderId) return false;
  } else if (a.senderName != b.senderName) {
    return false;
  }
  final da = a.createdAt;
  final db = b.createdAt;
  if (da == null || db == null) return true;
  return db.difference(da).inMinutes.abs() <= 4;
}

List<_ChatListItem> _chatListItems(List<ChatMessage> messages) {
  final sorted = [...messages]..sort((a, b) {
      final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return da.compareTo(db);
    });
  final items = <_ChatListItem>[];
  String? lastLabel;
  for (var i = 0; i < sorted.length; i++) {
    final m = sorted[i];
    if (m.createdAt == null) continue;
    final label = _formatChatDateLabel(m.createdAt!);
    if (label != lastLabel) {
      items.add(_ChatListItem.date(label));
      lastLabel = label;
    }
    final prev = i > 0 ? sorted[i - 1] : null;
    final next = i < sorted.length - 1 ? sorted[i + 1] : null;
    final first = prev == null || !_sameMessageGroup(prev, m);
    final last = next == null || !_sameMessageGroup(m, next);
    items.add(_ChatListItem.msg(m, isFirstInGroup: first, isLastInGroup: last));
  }
  return items;
}

String _formatMsgTime(String? iso) {
  final dt = _parseMessageDate(iso);
  if (dt == null) return '—';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String _formatMsgTimeFromDateTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String _mimeForFilename(String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.txt')) return 'text/plain';
  if (n.endsWith('.csv')) return 'text/csv';
  return 'application/octet-stream';
}

ChatMessage _messageFromRow(Map<String, dynamic> m, String? myId) {
  final senderId = m['sender_id']?.toString() ?? '';
  final senderName = m['sender_name']?.toString() ?? 'User';
  final created = m['created_at']?.toString() ?? '';
  final createdAt = _parseMessageDate(created);
  final attachment = m['attachment'] is Map
      ? Map<String, dynamic>.from(m['attachment'] as Map)
      : null;
  final fileId = m['file_id']?.toString() ?? attachment?['file_id']?.toString();
  return ChatMessage(
    id: m['id']?.toString() ?? '',
    senderId: senderId,
    senderName: senderName,
    senderInitials: _initialsFromName(senderName),
    message: m['content']?.toString() ?? '',
    time: _formatMsgTime(created),
    isMe: myId != null && senderId == myId,
    messageType: m['message_type']?.toString() ?? 'text',
    fileId: fileId,
    fileName: attachment?['filename']?.toString(),
    mimeType: attachment?['mime_type']?.toString(),
    createdAt: createdAt,
  );
}

// ── Chat List ─────────────────────────────────────────────────────────────────
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  int _reloadToken = 0;

  Future<List<ChatRoom>> _loadRooms() {
    return context
        .read<AppServices>()
        .chat
        .listRooms(forceRefresh: true)
        .unwrap()
        .then((rows) => rows.map(chatRoomFromApi).toList());
  }

  Future<void> _invalidateAndReload() async {
    await context.read<AppServices>().chat.invalidateRooms();
    if (mounted) setState(() => _reloadToken++);
  }

  Future<void> _showNewTeamChatSheet() async {
    final services = context.read<AppServices>();
    List<ApiProject> projects;
    try {
      projects =
          await services.projects.listProjects(forceRefresh: true).unwrap();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load projects: $e')),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        if (projects.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Create a project first — each project has a team chat.',
              textAlign: TextAlign.center,
            ),
          );
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Team project chat',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: projects.length,
                  itemBuilder: (_, i) {
                    final p = projects[i];
                    return ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(p.name),
                      subtitle: const Text('Open team conversation'),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await openProjectTeamChat(
                          context,
                          projectId: p.id,
                          projectName: p.name,
                        );
                        await _invalidateAndReload();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _roomTile(BuildContext context, ChatRoom r) {
    return TCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => Navigator.pushNamed(
        context,
        r.isGroup ? R.groupChat : R.directChat,
        arguments: r,
      ),
      child: Row(children: [
        Stack(
          children: [
            TAvatar(
              initials: r.initials,
              radius: 24,
              bg: r.isGroup ? AppColors.primary : AppColors.accent,
            ),
            if (AppConfig.isDemoMode)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: r.isGroup
                        ? AppColors.success
                        : _getPresenceColor(_getMockPresence(r.name)),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      r.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    r.time,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                r.lastMessage,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        const Center(
          child: Text(
            'No conversations yet',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TButton(
            label: 'Start team chat',
            onTap: _showNewTeamChatSheet,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Messages',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'New team chat',
            onPressed: _showNewTeamChatSheet,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _invalidateAndReload,
        child: RepositoryLoader<List<ChatRoom>>(
          key: ValueKey(_reloadToken),
          load: _loadRooms,
          builder: (context, rooms) {
            if (rooms.isEmpty) return _emptyState();
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: rooms.length,
              itemBuilder: (_, i) => _roomTile(context, rooms[i]),
            );
          },
        ),
      ),
      bottomNavigationBar:
          TBottomNav(current: 3, onTap: (i) => handleRoleNav(context, i)),
    );
  }
}

// ── Conversation (group + direct) ─────────────────────────────────────────────
/// Shared shell for direct + group conversations (same backend room model).
abstract class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class GroupChatScreen extends ConversationScreen {
  const GroupChatScreen({super.key});
}

class DirectChatScreen extends ConversationScreen {
  const DirectChatScreen({super.key});
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _ctrl = TextEditingController();
  final List<ChatMessage> _messages = [];
  final Set<String> _seenIds = {};
  final MeetingSpeechRecorder _voiceRecorder = MeetingSpeechRecorder();
  final MeetingBrowserSpeech _voiceSpeech = MeetingBrowserSpeech();
  String _voiceDraft = '';
  StreamSubscription<SocketPayload>? _socketSub;
  WebSocketManager? _ws;
  bool _loadingHistory = true;
  bool _recordingVoice = false;
  bool _transcribingVoice = false;
  String? _roomId;
  String? _projectId;
  String _roomName = 'Chat';
  int _memberCount = 0;
  bool _sendingAttachment = false;
  final ScrollController _chatScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    final rid = _roomId;
    if (rid != null) {
      _ws?.leaveRoom(rid);
    }
    if (_recordingVoice) {
      unawaited(_voiceSpeech.stop(null));
    }
    _voiceRecorder.dispose();
    _ctrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    _ws = context.read<WebSocketManager>();
    final args = ModalRoute.of(context)?.settings.arguments;
    final room = args is ChatRoom
        ? args
        : (args is ApiUser
            ? ChatRoom(
                id: 'dm_${args.id}',
                name: args.primaryName,
                lastMessage: 'Tap to message',
                time: 'Just now',
                initials: args.initials,
                isGroup: false,
              )
            : null);
    if (room == null) {
      setState(() => _loadingHistory = false);
      return;
    }
    setState(() {
      _roomId = room.id;
      _roomName = room.name;
      _projectId = room.projectId;
    });
    try {
      final roomData =
          await context.read<AppServices>().chat.getRoom(room.id).unwrap();
      if (mounted) {
        _projectId ??= projectIdFromChatRoomPayload(roomData);
        final members =
            (roomData['members'] as List?)?.whereType<Map<String, dynamic>>();
        _memberCount = members?.length ?? 0;
        if (_projectId != null || _memberCount > 0) setState(() {});
      }
    } catch (_) {}
    await _loadHistory();
    await _ws?.connect();
    _subscribeSocket();
  }

  void _subscribeSocket() {
    final ws = _ws;
    final rid = _roomId;
    if (ws == null || rid == null) return;
    if (ws.isConnected) ws.joinRoom(rid);
    _socketSub?.cancel();
    _socketSub = ws.stream.listen((payload) {
      if (payload.event == SocketEvent.connected) {
        ws.joinRoom(rid);
        return;
      }
      if (payload.event == SocketEvent.chatMessage) {
        final d = payload.data;
        final msgRoom = d['room_id']?.toString();
        if (msgRoom != rid) return;
        _appendServerMessage(Map<String, dynamic>.from(d));
      } else if (payload.event == SocketEvent.messageDeleted) {
        final d = payload.data;
        final msgRoom = d['room_id']?.toString();
        if (msgRoom != rid) return;
        final id = d['message_id']?.toString() ?? d['id']?.toString();
        if (id != null && id.isNotEmpty) {
          _removeMessageById(id);
        }
      }
    });
  }

  void _appendServerMessage(Map<String, dynamic> d) {
    if (!mounted) return;
    final session = context.read<SessionController>();
    final myId = session.currentUser?.id;
    final id = d['id']?.toString() ?? '';
    final content = d['content']?.toString() ?? '';
    if (id.isNotEmpty && _seenIds.contains(id)) {
      setState(() {
        _messages.removeWhere((m) =>
            m.isPending &&
            m.isMe &&
            m.message == content &&
            (myId == null || m.senderId == myId));
      });
      return;
    }
    if (id.isNotEmpty) _seenIds.add(id);
    final incoming = _messageFromRow(d, myId);
    setState(() {
      _messages.removeWhere((m) =>
          m.isPending &&
          m.isMe &&
          m.message == content &&
          (myId == null || m.senderId == myId));
      _messages.add(incoming);
    });
  }

  void _confirmPendingFromServer(String pendingId, Map<String, dynamic> row) {
    if (!mounted) return;
    final session = context.read<SessionController>();
    final myId = session.currentUser?.id;
    final incoming = _messageFromRow(row, myId);
    final id = incoming.id;
    if (id.isNotEmpty && _seenIds.contains(id)) {
      setState(() => _messages.removeWhere((m) => m.id == pendingId));
      return;
    }
    if (id.isNotEmpty) _seenIds.add(id);
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == pendingId);
      if (idx >= 0) {
        _messages[idx] = incoming;
      } else {
        _messages.removeWhere((m) =>
            m.isPending &&
            m.isMe &&
            m.message == incoming.message &&
            (myId == null || m.senderId == myId));
        if (id.isEmpty || !_messages.any((m) => m.id == id)) {
          _messages.add(incoming);
        }
      }
    });
  }

  void _failPending(String pendingId, String message) {
    if (!mounted) return;
    setState(() => _messages.removeWhere((m) => m.id == pendingId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleSendResult(
    String pendingId,
    ApiResult<Map<String, dynamic>> result,
  ) {
    if (!mounted) return;
    if (result.isSuccess && result.data != null) {
      final raw = result.data!;
      final row = raw['data'];
      if (row is Map) {
        _confirmPendingFromServer(
          pendingId,
          Map<String, dynamic>.from(row),
        );
        return;
      }
      if (raw.containsKey('id') && raw.containsKey('content')) {
        _confirmPendingFromServer(pendingId, raw);
        return;
      }
    }
    if (result.isOfflineQueued) return;
    _failPending(pendingId, result.error ?? 'Could not send message');
  }

  Future<void> _confirmPendingViaRestIfNeeded(
    String pendingId,
    String rid,
    Map<String, dynamic> payload,
  ) async {
    await Future.delayed(const Duration(seconds: 8));
    if (!mounted) return;
    if (!_messages.any((m) => m.id == pendingId && m.isPending)) return;
    final ws = _ws ?? context.read<WebSocketManager>();
    if (ws.isConnected) return;
    final result =
        await context.read<AppServices>().chat.sendMessage(rid, payload);
    _handleSendResult(pendingId, result);
  }

  void _removeMessageById(String id) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((m) => m.id == id);
      _seenIds.remove(id);
    });
  }

  Future<void> _confirmDeleteMessage(ChatMessage m) async {
    final rid = _roomId;
    if (rid == null) return;

    if (m.isPending) {
      _removeMessageById(m.id);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
            'This message will be removed for everyone in this chat.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final result =
        await context.read<AppServices>().chat.deleteMessage(rid, m.id);
    if (!mounted) return;

    if (result.isSuccess) {
      _removeMessageById(m.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${result.error}')),
      );
    }
  }

  Future<void> _loadHistory() async {
    final rid = _roomId;
    if (rid == null) return;
    final svc = context.read<AppServices>();
    try {
      final raw = await svc.chat.getMessages(rid).unwrap();
      if (!mounted) return;
      final session = context.read<SessionController>();
      final myId = session.currentUser?.id;
      setState(() {
        _messages
          ..clear()
          ..addAll(raw.map((m) => _messageFromRow(m, myId)));
        _seenIds
          ..clear()
          ..addAll(_messages.map((e) => e.id).where((id) => id.isNotEmpty));
        _loadingHistory = false;
      });
      _scrollChatToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _openMeeting() async {
    final rid = _roomId;
    if (rid == null) return;

    final session = context.read<SessionController>();
    final me = session.currentUser;
    final hostName = me?.fullName ?? me?.displayName ?? 'Alex Chen';
    final meetingId = 'm_${DateTime.now().millisecondsSinceEpoch}';
    final meetingTitle = '$_roomName Sync';
    final now = DateTime.now();

    final systemMsg = ChatMessage(
      id: 'msg_$meetingId',
      senderId: me?.id ?? 'system',
      senderName: hostName,
      senderInitials: _initialsFromName(hostName),
      message: '📹 $hostName started a meeting',
      time: _formatMsgTimeFromDateTime(now),
      isMe: true,
      messageType: 'meeting',
      fileId: meetingId,
      fileName: meetingTitle,
      mimeType: 'LIVE',
      createdAt: now,
    );

    setState(() {
      _messages.add(systemMsg);
    });
    _scrollChatToEnd();

    final newDemoMeeting = DemoMeeting(
      id: meetingId,
      title: meetingTitle,
      projectName: _roomName,
      dateTimeLabel: 'Today, ${_formatMsgTimeFromDateTime(now)}',
      scheduledAt: now,
      hostName: hostName,
      hostInitials: _initialsFromName(hostName),
      participantCount: _memberCount > 0 ? _memberCount : 4,
      participantNames: [hostName, 'Sarah Miller', 'David Ross'],
      status: 'Live',
      description: 'Live meeting started directly from project chat.',
    );
    globalMockMeetings.insert(0, newDemoMeeting);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PermissionsPreviewSheet(meeting: newDemoMeeting),
    );
  }

  Widget _meetingChatCard(ChatMessage m) {
    final isLive = m.mimeType == 'LIVE' || m.message.contains('started');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLive
              ? AppColors.success.withValues(alpha: 0.5)
              : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.videocam, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Builder(
                  builder: (_) {
                    final dir = getTextDirection(m.message);
                    return Text(
                      m.message,
                      textDirection: dir,
                      textAlign: getTextAlign(dir),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isLive
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    if (isLive) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      isLive ? 'LIVE' : 'ENDED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isLive
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            m.fileName ?? 'Project Meeting',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isLive
                ? 'Started at ${m.time} · Tap to join'
                : 'Meeting ended · Duration: 00:15:20 · 4 members',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final targetMeeting = globalMockMeetings.firstWhere(
                  (item) => item.id == m.fileId,
                  orElse: () => DemoMeeting(
                    id: m.fileId ?? 'm1',
                    title: m.fileName ?? 'Project Meeting',
                    projectName: _roomName,
                    dateTimeLabel: m.time,
                    scheduledAt: DateTime.now(),
                    hostName: m.senderName,
                    hostInitials: m.senderInitials,
                    participantCount: 4,
                    participantNames: [m.senderName, 'Sarah Miller'],
                    status: isLive ? 'Live' : 'Ended',
                  ),
                );
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (_) =>
                      PermissionsPreviewSheet(meeting: targetMeeting),
                );
              },
              icon: Icon(isLive ? Icons.video_call : Icons.replay, size: 16),
              label: Text(isLive ? 'Join Meeting' : 'Rejoin / View Notes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLive ? AppColors.success : AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openChatSummary() {
    final rid = _roomId;
    if (rid == null) return;
    Navigator.pushNamed(
      context,
      R.chatSummary,
      arguments: ChatRoom(
        id: rid,
        name: _roomName,
        lastMessage: '',
        time: '',
        initials: _roomName.isNotEmpty ? _roomName[0] : 'C',
        isGroup: widget is GroupChatScreen,
      ),
    );
  }

  void _showInputMenu() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final width = MediaQuery.sizeOf(sheetContext).width;

        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width > 600 ? 400 : width - 24,
              ),
              child: Builder(
                builder: (sheetCtx) {
                  final isDark =
                      Theme.of(sheetCtx).brightness == Brightness.dark;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.3 : 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF475569)
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Expanded(
                              child: _attachmentOption(
                                icon: Icons.insert_drive_file_rounded,
                                label: 'Documents',
                                color: const Color(0xFF7F56D9),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _pickDocument();
                                },
                              ),
                            ),
                            Expanded(
                              child: _attachmentOption(
                                icon: Icons.photo_library_rounded,
                                label: 'Photos & Videos',
                                color: const Color(0xFFE04F9F),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _pickMedia();
                                },
                              ),
                            ),
                            Expanded(
                              child: _attachmentOption(
                                icon: Icons.camera_alt_rounded,
                                label: 'Camera',
                                color: const Color(0xFFE53935),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openCamera();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Expanded(
                              child: _attachmentOption(
                                icon: Icons.mic_rounded,
                                label: 'Audio',
                                color: const Color(0xFFF59E0B),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openAudioRecorder();
                                },
                              ),
                            ),
                            Expanded(
                              child: _attachmentOption(
                                icon: Icons.poll_rounded,
                                label: 'Poll',
                                color: const Color(0xFF00A884),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openCreatePoll();
                                },
                              ),
                            ),
                            Expanded(
                              child: _attachmentOption(
                                icon: Icons.event_rounded,
                                label: 'Events',
                                color: const Color(0xFF0284C7),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openCreateEvent();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _attachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDocument() async {
    if (_sendingAttachment) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'zip'
        ],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;

      final sizeInMb = file.size / (1024 * 1024);
      if (sizeInMb > 50) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('File is too large. Maximum size is 50 MB.')),
        );
        return;
      }

      final sizeStr = file.size > 1024 * 1024
          ? '${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB'
          : '${(file.size / 1024).toStringAsFixed(0)} KB';

      if (!mounted) return;

      await _sendAttachmentMessage(
        fileId: file.name,
        messageType: 'file',
        caption: 'Shared document: ${file.name}',
        displayName: file.name,
        mimeType: sizeStr,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick document: $e')),
      );
    }
  }

  Future<void> _pickMedia() async {
    if (_sendingAttachment) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.media,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final ext = file.extension?.toLowerCase() ?? '';
      final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);

      final captionCtrl = TextEditingController();
      if (!mounted) return;
      final send = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isVideo ? 'Send Video' : 'Send Photo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    isVideo ? Icons.movie_outlined : Icons.image_outlined,
                    size: 48,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(file.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: captionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Caption (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Send'),
            ),
          ],
        ),
      );

      if (send != true || !mounted) return;

      final captionText = captionCtrl.text.trim();
      await _sendAttachmentMessage(
        fileId: file.name,
        messageType: isVideo ? 'video' : 'image',
        caption: captionText.isNotEmpty
            ? captionText
            : (isVideo ? 'Video' : 'Photo'),
        displayName: file.name,
        mimeType: isVideo ? 'video/mp4' : 'image/jpeg',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pick media: $e')),
      );
    }
  }

  Future<void> _openCamera() async {
    if (_sendingAttachment) return;
    try {
      final captionCtrl = TextEditingController();
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.camera_alt, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Camera Capture'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera, color: Colors.white, size: 48),
                    SizedBox(height: 8),
                    Text('Camera Active (Simulated)',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: captionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Caption (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx, false);
                await _pickMedia();
              },
              child: const Text('Choose Photo'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Take & Send'),
            ),
          ],
        ),
      );

      if (result != true || !mounted) return;

      final captionText = captionCtrl.text.trim();
      await _sendAttachmentMessage(
        fileId: 'camera_photo.jpg',
        messageType: 'image',
        caption: captionText.isNotEmpty ? captionText : 'Camera Photo',
        displayName: 'camera_photo.jpg',
        mimeType: 'image/jpeg',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e')),
      );
    }
  }

  Future<void> _openAudioRecorder() async {
    if (_sendingAttachment) return;
    final recordedDuration = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _AudioRecorderSheet(),
    );
    if (recordedDuration == null || !mounted) return;

    await _sendAttachmentMessage(
      fileId: 'voice_note.mp3',
      messageType: 'audio',
      caption: 'Voice message ($recordedDuration)',
      displayName: recordedDuration,
      mimeType: 'audio/mp3',
    );
  }

  Future<void> _openCreatePoll() async {
    if (_sendingAttachment) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CreatePollSheet(
        onCreated: (question, options, allowMultiple, isAnonymous) async {
          final pollData = {
            'question': question,
            'options': options.map((opt) => {'text': opt, 'votes': 0}).toList(),
            'allowMultiple': allowMultiple,
            'isAnonymous': isAnonymous,
            'totalVotes': 0,
            'userVoted': <int>[],
          };

          await _sendAttachmentMessage(
            fileId: jsonEncode(pollData),
            messageType: 'poll',
            caption: question,
            displayName: question,
          );
        },
      ),
    );
  }

  Future<void> _openCreateEvent() async {
    if (_sendingAttachment) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CreateEventSheet(
        onCreated: (title, description, dateStr, timeStr, location) async {
          final eventData = {
            'title': title,
            'description': description,
            'dateStr': dateStr,
            'timeStr': timeStr,
            'location': location,
            'goingCount': 1,
            'isGoing': true,
          };

          await _sendAttachmentMessage(
            fileId: jsonEncode(eventData),
            messageType: 'event',
            caption: title,
            displayName: title,
          );
        },
      ),
    );
  }

  Future<void> _sendAttachmentMessage({
    required String fileId,
    required String messageType,
    String? caption,
    String? displayName,
    String? mimeType,
  }) async {
    if (_sendingAttachment) return;
    final session = context.read<SessionController>();
    final me = session.currentUser;
    final myId = me?.id ?? 'me';
    final displayNameUser = me?.fullName ?? me?.displayName ?? 'You';
    final label = caption ?? displayName ?? 'Attachment';
    final now = DateTime.now();
    final pendingId = 'att_${now.millisecondsSinceEpoch}';

    setState(() {
      _sendingAttachment = true;
      _messages.add(ChatMessage(
        id: pendingId,
        senderId: myId,
        senderName: displayNameUser,
        senderInitials: _initialsFromName(displayNameUser),
        message: label,
        time: _formatMsgTimeFromDateTime(now),
        isMe: true,
        isPending: false,
        messageType: messageType,
        fileId: fileId,
        fileName: displayName ?? fileId,
        mimeType: mimeType,
        createdAt: now,
      ));
    });
    _scrollChatToEnd();

    try {
      final rid = _roomId;
      if (rid != null && rid.isNotEmpty && !AppConfig.isDemoMode) {
        final ws = _ws ?? context.read<WebSocketManager>();
        final payload = {
          'content': label,
          'message_type': messageType,
          'file_id': int.tryParse(fileId) ?? fileId,
        };

        if (!ws.isConnected) {
          await ws.connect();
        }
        if (mounted && ws.isConnected) {
          ws.sendChatPayload(rid, payload);
          unawaited(_confirmPendingViaRestIfNeeded(pendingId, rid, payload));
        } else if (mounted) {
          final result =
              await context.read<AppServices>().chat.sendMessage(rid, payload);
          _handleSendResult(pendingId, result);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _sendingAttachment = false);
      }
    }
  }

  Future<void> _toggleVoiceMessage() async {
    if (_transcribingVoice) return;
    final rid = _roomId;
    if (rid == null) return;

    if (!_recordingVoice) {
      if (kIsWeb) {
        final micOk = await _voiceRecorder.ensurePermission();
        if (!micOk) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Allow microphone access to use voice messages.'),
            ),
          );
          return;
        }
        final ok = await _voiceSpeech.initialize();
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Speech recognition is not available in this browser.',
              ),
            ),
          );
          return;
        }
        _voiceDraft = '';
        final started = await _voiceSpeech.startListening((text, isFinal) {
          if (!mounted || text.trim().isEmpty) return;
          setState(() => _voiceDraft = text.trim());
        });
        if (!started) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not start speech recognition.'),
            ),
          );
          return;
        }
        if (!mounted) return;
        setState(() => _recordingVoice = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Listening… Tap mic to send, or ✕ to cancel.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final ok = await _voiceRecorder.ensurePermission();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Allow microphone access to use voice messages.'),
          ),
        );
        return;
      }
      final started = await _voiceRecorder.startVoiceNote();
      if (!started) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start microphone.')),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _recordingVoice = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recording… Tap mic to send, or ✕ to cancel.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (kIsWeb) {
      setState(() {
        _recordingVoice = false;
        _transcribingVoice = true;
      });
      await _voiceSpeech.stop((text, isFinal) {
        if (text.trim().isNotEmpty) {
          _voiceDraft = text.trim();
        }
      });
      if (!mounted) return;
      setState(() => _transcribingVoice = false);

      final text = _voiceDraft.trim();
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No speech detected. Try again.')),
        );
        return;
      }

      _ctrl.text = text;
      _voiceDraft = '';
      await _send();
      return;
    }

    setState(() {
      _recordingVoice = false;
      _transcribingVoice = true;
    });

    final captured = await _voiceRecorder.stopVoiceNote();
    if (!mounted) return;

    if (captured == null) {
      setState(() => _transcribingVoice = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audio captured. Try again.')),
      );
      return;
    }

    final result = await context.read<AppServices>().ai.transcribe(
          captured.bytes,
          filename: captured.filename,
        );

    if (!mounted) return;
    setState(() => _transcribingVoice = false);

    if (!result.isSuccess || result.data!.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error?.contains('502') == true ||
                    result.error?.toLowerCase().contains('stt') == true
                ? 'Speech service is unavailable right now. Try again later.'
                : 'Transcription failed: ${result.error ?? 'empty'}',
          ),
        ),
      );
      return;
    }

    _ctrl.text = result.data!.text.trim();
    await _send();
  }

  Future<void> _cancelVoiceMessage() async {
    if (!_recordingVoice || _transcribingVoice) return;
    if (kIsWeb) {
      await _voiceSpeech.stop(null);
    } else {
      await _voiceRecorder.cancelVoiceNote();
    }
    if (!mounted) return;
    setState(() {
      _recordingVoice = false;
      _voiceDraft = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice recording cancelled.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    final rid = _roomId;
    if (text.isEmpty || rid == null || !mounted) return;

    final ws = _ws ?? context.read<WebSocketManager>();
    final session = context.read<SessionController>();
    final myId = session.currentUser?.id ?? '';
    final displayName = session.currentUser?.displayName ??
        session.currentUser?.fullName ??
        'You';

    if (!ws.isConnected) {
      await ws.connect();
    }
    if (!mounted) return;

    final pendingId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    final pending = ChatMessage(
      id: pendingId,
      senderId: myId,
      senderName: displayName,
      senderInitials: _initialsFromName(displayName),
      message: text,
      time: _formatMsgTimeFromDateTime(now),
      isMe: true,
      isPending: true,
      createdAt: now,
    );
    final payload = {'content': text, 'message_type': 'text'};
    setState(() {
      _messages.add(pending);
      _ctrl.clear();
    });
    _scrollChatToEnd();

    final isMention = text.contains('@');
    NotificationEventDispatcher.triggerEvent(
      context: context,
      type: isMention
          ? NotificationType.chatMention
          : NotificationType.directMessage,
      title: isMention ? 'Chat Mention' : 'New Message',
      body: text,
      entityType: 'chat',
      entityId: rid,
    );

    if (ws.isConnected) {
      ws.sendMessage(rid, text);
      unawaited(_confirmPendingViaRestIfNeeded(pendingId, rid, payload));
    } else {
      final result =
          await context.read<AppServices>().chat.sendMessage(rid, payload);
      _handleSendResult(pendingId, result);
    }
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _chatStatusLine() {
    if (_loadingHistory) return 'Loading messages…';

    if (AppConfig.isDemoMode) {
      final isGroup = widget is GroupChatScreen;
      if (isGroup || _memberCount > 0) {
        final totalMembers = _memberCount > 0 ? _memberCount : 4;
        final onlineMembers = (totalMembers * 0.75).round();
        if (onlineMembers > 0) {
          return '$onlineMembers of $totalMembers members online';
        }
        return '$totalMembers members';
      } else {
        final presence = _getMockPresence(_roomName);
        return _getPresenceLabel(presence);
      }
    }

    final connected = _ws?.isConnected ?? false;
    final status = connected ? 'Connected' : 'Offline';
    if (_memberCount > 0) {
      final n = _memberCount;
      return '$status · $n ${n == 1 ? 'member' : 'members'}';
    }
    return status;
  }

  Color _statusIndicatorColor(bool connected) {
    if (AppConfig.isDemoMode) {
      final isGroup = widget is GroupChatScreen;
      if (isGroup || _memberCount > 0) {
        return AppColors.success;
      }
      final presence = _getMockPresence(_roomName);
      return _getPresenceColor(presence);
    }
    return connected ? AppColors.success : AppColors.warning;
  }

  Future<void> _showMembersList() async {
    final pid = _projectId;
    List<ApiUser> membersList = [];
    if (pid != null && pid.isNotEmpty) {
      try {
        final res = await context.read<AppServices>().projects.listMembers(pid);
        res.when(success: (m) => membersList = m, failure: (_) {});
      } catch (_) {}
    }
    if (!mounted) return;
    if (membersList.isEmpty) {
      final session = context.read<SessionController>();
      final me = session.currentUser;
      membersList = [
        if (me != null) me,
        const ApiUser(
          id: 'mock_m1',
          displayName: 'sarah_m',
          fullName: 'Sarah Miller',
          email: 'sarah@example.com',
          role: 'admin',
          userType: 'freelancer',
          professionalField: 'UI/UX Design',
        ),
        const ApiUser(
          id: 'mock_m2',
          displayName: 'alex_dev',
          fullName: 'Alex Chen',
          email: 'alex@example.com',
          role: 'member',
          userType: 'student',
          major: 'Software Engineering',
        ),
      ];
    }
    final uniqueMembers = <String, ApiUser>{};
    for (final m in membersList) {
      if (m.id.isNotEmpty) uniqueMembers[m.id] = m;
    }
    final displayMembers = uniqueMembers.values.toList();

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Project Members (${displayMembers.length})',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: displayMembers.length,
                itemBuilder: (_, i) {
                  final u = displayMembers[i];
                  final isOwner = i == 0;
                  final projectRole = isOwner
                      ? 'Owner'
                      : (u.role == 'admin' ? 'Admin' : 'Member');
                  final status = i % 2 == 0 ? 'Online' : 'Offline';
                  final statusColor = status == 'Online'
                      ? AppColors.success
                      : AppColors.textHint;
                  final handle =
                      u.displayName.isNotEmpty ? '@${u.displayName}' : '';

                  return ListTile(
                    leading: Stack(
                      children: [
                        TAvatar(initials: u.initials, radius: 20),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(u.primaryName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('$handle • $projectRole • $status',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showTeammateProfileInChat(u);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTeammateProfileInChat(ApiUser u) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TAvatar(initials: u.initials, radius: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.primaryName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      if (u.displayName.isNotEmpty)
                        Text('@${u.displayName}',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      TChip(label: u.displayRole),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (u.email.isNotEmpty)
              Text('Email: ${u.email}',
                  style: const TextStyle(color: AppColors.textSecondary)),
            if (u.professionalField.isNotEmpty)
              Text('Field: ${u.professionalField}',
                  style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final myInitials =
        _initialsFromName(session.currentUser?.displayName ?? 'Me');
    final chatItems = _chatListItems(_messages);
    final connected = _ws?.isConnected ?? false;

    if (_roomId == null && !_loadingHistory) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Messages',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Choose a conversation from the list to start messaging.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                TAvatar(
                  initials: _roomName.isNotEmpty ? _roomName[0] : 'C',
                  radius: 20,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _statusIndicatorColor(connected),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _statusIndicatorColor(connected),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _chatStatusLine(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Members',
            onPressed: _showMembersList,
          ),
          IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: 'AI summary',
            onPressed: _openChatSummary,
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Meeting',
            onPressed: _openMeeting,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background,
                    AppColors.primaryLight.withValues(alpha: 0.12),
                  ],
                ),
              ),
              child: RefreshIndicator(
                onRefresh: _loadHistory,
                child: ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  itemCount: chatItems.length,
                  itemBuilder: (_, i) {
                    final item = chatItems[i];
                    if (item.dateLabel != null) {
                      return Center(
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: 8,
                            top: i > 0 ? 6 : 0,
                          ),
                          child: TChip(
                            label: item.dateLabel!,
                            bg: AppColors.border,
                          ),
                        ),
                      );
                    }
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(item.message!.id),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 6),
                          child: child,
                        ),
                      ),
                      child: _buildBubble(
                        item.message!,
                        myInitials,
                        isFirstInGroup: item.isFirstInGroup,
                        isLastInGroup: item.isLastInGroup,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildBubble(
    ChatMessage m,
    String myInitials, {
    required bool isFirstInGroup,
    required bool isLastInGroup,
  }) {
    if (m.messageType == 'meeting' || m.message.contains('started a meeting')) {
      return _meetingChatCard(m);
    }
    if (m.messageType == 'poll') {
      return _PollCardWidget(message: m);
    }
    if (m.messageType == 'event') {
      return _EventCardWidget(message: m);
    }
    if (m.messageType == 'audio') {
      return _AudioCardWidget(message: m);
    }
    if (m.messageType == 'video') {
      return _VideoCardWidget(message: m);
    }
    final isMe = m.isMe;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = isMe
        ? AppColors.primary
        : (isDark ? const Color(0xFF1E293B) : Colors.white);
    final textColor =
        isMe ? Colors.white : (isDark ? Colors.white : AppColors.textPrimary);
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.72;

    final topPad = isFirstInGroup ? 10.0 : 2.0;
    final bottomPad = isLastInGroup ? 8.0 : 2.0;

    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMe ? 20 : (isFirstInGroup ? 18 : 6)),
      topRight: Radius.circular(isMe ? (isFirstInGroup ? 18 : 6) : 20),
      bottomLeft: Radius.circular(isMe ? 20 : (isLastInGroup ? 6 : 18)),
      bottomRight: Radius.circular(isMe ? (isLastInGroup ? 6 : 18) : 20),
    );

    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            SizedBox(
              width: 34,
              child: isLastInGroup
                  ? TAvatar(
                      initials: m.senderInitials,
                      radius: 15,
                      bg: AppColors.primary,
                    )
                  : null,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe && isFirstInGroup)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 2),
                    child: Text(
                      m.senderName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onLongPress: isMe && !m.isPending
                        ? () => _confirmDeleteMessage(m)
                        : null,
                    borderRadius: radius,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                      padding: m.hasAttachment && m.isImage
                          ? const EdgeInsets.all(6)
                          : const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: radius,
                        border:
                            isMe ? null : Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (m.hasAttachment)
                            _ChatAttachmentBody(
                              message: m,
                              isMe: isMe,
                              onOpen: () => _openAttachment(m),
                            ),
                          if (m.message.isNotEmpty &&
                              (!m.hasAttachment || !m.isImage))
                            Builder(
                              builder: (_) {
                                final dir = getTextDirection(m.message);
                                return Text(
                                  m.message,
                                  textDirection: dir,
                                  textAlign: getTextAlign(dir),
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14.5,
                                    height: 1.35,
                                    letterSpacing: 0.1,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isLastInGroup)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                    child: Text(
                      '${m.time}${m.isPending ? ' · sending' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isMe) ...[
            SizedBox(
              width: 34,
              child: isLastInGroup
                  ? Opacity(
                      opacity: m.isPending ? 0.5 : 1,
                      child: TAvatar(initials: myInitials, radius: 15),
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openAttachment(ChatMessage m) async {
    final fid = m.fileId;
    if (fid == null || fid.isEmpty) return;

    if (m.isImage) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (ctx) => _ChatImageViewerDialog(
          fileId: fid,
          title: m.fileName ?? 'Photo',
        ),
      );
      return;
    }

    try {
      final bytes =
          await context.read<AppServices>().files.downloadFile(fid).unwrap();
      if (!mounted) return;
      final name = m.fileName ?? 'attachment';
      await saveDownloadedBytes(
        filename: name,
        bytes: Uint8List.fromList(bytes),
        mimeType: _mimeForFilename(name),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded $name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: $e')),
      );
    }
  }

  Widget _buildInput() => Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _ChatInputIconButton(
                icon: _sendingAttachment ? null : Icons.add_rounded,
                tooltip: 'Attach',
                onPressed: _sendingAttachment || _transcribingVoice
                    ? null
                    : _showInputMenu,
                child: _sendingAttachment
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              _ChatInputIconButton(
                icon: _transcribingVoice
                    ? Icons.hourglass_top_rounded
                    : _recordingVoice
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                tooltip: 'Voice',
                iconColor: _recordingVoice
                    ? const Color(0xFFDC2626)
                    : AppColors.primary,
                bgColor: _recordingVoice
                    ? const Color(0xFFFEE2E2)
                    : AppColors.primaryLight,
                onPressed: _transcribingVoice || _sendingAttachment
                    ? null
                    : _toggleVoiceMessage,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  decoration: BoxDecoration(
                    color: _recordingVoice
                        ? const Color(0xFFFEF2F2)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: _recordingVoice
                          ? const Color(0xFFFECACA)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (_recordingVoice) ...[
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 12, right: 4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFDC2626),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 5,
                          enabled: !_transcribingVoice &&
                              !_sendingAttachment &&
                              !_recordingVoice,
                          style: const TextStyle(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: _recordingVoice
                                ? (_voiceDraft.isNotEmpty
                                    ? _voiceDraft
                                    : 'Listening… tap mic to send')
                                : _transcribingVoice
                                    ? 'Transcribing…'
                                    : _sendingAttachment
                                        ? 'Uploading…'
                                        : 'Message',
                            hintStyle: const TextStyle(
                              color: AppColors.textHint,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      if (_recordingVoice)
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),
                          tooltip: 'Cancel',
                          onPressed: _cancelVoiceMessage,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ChatInputIconButton(
                icon: Icons.send_rounded,
                tooltip: 'Send',
                filled: true,
                onPressed:
                    _transcribingVoice || _sendingAttachment || _recordingVoice
                        ? null
                        : _send,
              ),
            ],
          ),
        ),
      );
}

class _ChatInputIconButton extends StatelessWidget {
  static const double _size = 44;
  static const double _iconSize = 22;

  const _ChatInputIconButton({
    this.icon,
    this.child,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
    this.bgColor,
    this.filled = false,
  });

  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final Color? bgColor;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final background =
        bgColor ?? (filled ? AppColors.primary : AppColors.primaryLight);
    final foreground = iconColor ?? (filled ? Colors.white : AppColors.primary);

    return Material(
      color: disabled ? background.withValues(alpha: 0.55) : background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: _size,
            height: _size,
            child: Center(
              child: child ??
                  Icon(
                    icon,
                    size: _iconSize,
                    color: disabled
                        ? foreground.withValues(alpha: 0.45)
                        : foreground,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline image or file chip inside a chat bubble.
class _ChatAttachmentBody extends StatefulWidget {
  final ChatMessage message;
  final bool isMe;
  final VoidCallback onOpen;

  const _ChatAttachmentBody({
    required this.message,
    required this.isMe,
    required this.onOpen,
  });

  @override
  State<_ChatAttachmentBody> createState() => _ChatAttachmentBodyState();
}

class _ChatAttachmentBodyState extends State<_ChatAttachmentBody> {
  Uint8List? _thumbBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.message.isImage && widget.message.fileId != null) {
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    setState(() => _loading = true);
    try {
      final bytes = await context
          .read<AppServices>()
          .files
          .downloadFile(widget.message.fileId!)
          .unwrap();
      if (mounted) setState(() => _thumbBytes = Uint8List.fromList(bytes));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    if (m.isImage) {
      return GestureDetector(
        onTap: widget.onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _loading
              ? const SizedBox(
                  width: 200,
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _thumbBytes != null
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.memory(
                          _thumbBytes!,
                          width: 220,
                          fit: BoxFit.cover,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.open_in_full,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('Tap to open',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Container(
                      width: 200,
                      height: 100,
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.image_outlined,
                        color: widget.isMe ? Colors.white70 : AppColors.primary,
                      ),
                    ),
        ),
      );
    }

    return InkWell(
      onTap: widget.onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.15)
              : AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.attach_file,
              size: 20,
              color: widget.isMe ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                m.fileName ?? m.message,
                style: TextStyle(
                  color: widget.isMe ? Colors.white : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen image viewer when tapping a chat photo.
class _ChatImageViewerDialog extends StatefulWidget {
  final String fileId;
  final String title;

  const _ChatImageViewerDialog({
    required this.fileId,
    required this.title,
  });

  @override
  State<_ChatImageViewerDialog> createState() => _ChatImageViewerDialogState();
}

class _ChatImageViewerDialogState extends State<_ChatImageViewerDialog> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context
          .read<AppServices>()
          .files
          .downloadFile(widget.fileId)
          .unwrap();
      if (!mounted) return;
      setState(() {
        _bytes = Uint8List.fromList(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    if (_bytes == null) return;
    final name =
        widget.title.contains('.') ? widget.title : '${widget.title}.jpg';
    try {
      await saveDownloadedBytes(
        filename: name,
        bytes: _bytes!,
        mimeType: _mimeForFilename(name),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_bytes != null)
                IconButton(
                  icon:
                      const Icon(Icons.download_outlined, color: Colors.white),
                  tooltip: 'Download',
                  onPressed: _download,
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Material(
                color: Colors.black,
                child: _loading
                    ? const SizedBox(
                        width: 320,
                        height: 280,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        ),
                      )
                    : _error != null
                        ? SizedBox(
                            width: 320,
                            height: 200,
                            child: Center(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4,
                            child: Image.memory(
                              _bytes!,
                              fit: BoxFit.contain,
                            ),
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Summary ──────────────────────────────────────────────────────────────
class ChatSummaryScreen extends StatefulWidget {
  const ChatSummaryScreen({super.key});

  @override
  State<ChatSummaryScreen> createState() => _ChatSummaryScreenState();
}

class _ChatSummaryScreenState extends State<ChatSummaryScreen> {
  bool _loading = true;
  String? _error;
  String _summaryText = '';
  List<String> _speechLines = const [];
  List<String> _keyPoints = const [];
  List<String> _actions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final room = ModalRoute.of(context)?.settings.arguments as ChatRoom?;
    if (room == null) {
      setState(() {
        _loading = false;
        _error = 'Open Chat Summary from a conversation.';
      });
      return;
    }
    try {
      final services = context.read<AppServices>();
      final msgs = await services.chat.getMessages(room.id).unwrap();
      final transcript = msgs
          .map((m) => '${m['sender_name'] ?? 'User'}: ${m['content'] ?? ''}')
          .join('\n');
      if (transcript.trim().isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No messages to summarise yet.';
        });
        return;
      }
      Map<String, dynamic> summary;
      try {
        summary = await services.ai.summarizeChat(transcript, topN: 6).unwrap();
      } catch (_) {
        summary = {
          'summary': transcript.split('\n').take(3).join(' '),
          'key_points': transcript
              .split('\n')
              .map((l) => l.contains(':') ? l.split(':').last.trim() : l)
              .where((s) => s.length >= 4)
              .take(6)
              .toList(),
        };
      }
      final kp = summary['key_points'];
      final ai = summary['action_items'];
      final speech = summary['speech_transcript'];
      setState(() {
        _summaryText = summary['summary']?.toString().trim() ?? '';
        if (_summaryText.isEmpty && kp is List && kp.isNotEmpty) {
          _summaryText = kp.map((e) => e.toString()).join('. ');
        }
        _speechLines = speech is List
            ? speech.map((e) => e.toString()).toList()
            : const [];
        _keyPoints =
            kp is List ? kp.map((e) => e.toString()).toList() : const [];
        _actions = ai is List ? ai.map((e) => e.toString()).toList() : const [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Chat Summary',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _error = null;
                            });
                            _load();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  const AIBanner(
                      title: 'AI Summary',
                      subtitle: 'Whisper speech + chat via Teamify AI'),
                  const SizedBox(height: 16),
                  if (_summaryText.isNotEmpty)
                    TCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Summary',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Text(_summaryText,
                              style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  if (_speechLines.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    TCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Speech transcript',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Text(_speechLines.join('\n'),
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Key Points',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                fontSize: 16)),
                        const SizedBox(height: 12),
                        if (_keyPoints.isEmpty)
                          const Text('No key points returned.',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textSecondary))
                        else
                          ..._keyPoints.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.only(
                                            top: 6, right: 8),
                                        decoration: const BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle)),
                                    Expanded(
                                        child: Text(p,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color:
                                                    AppColors.textSecondary))),
                                  ]))),
                      ])),
                  const SizedBox(height: 12),
                  TCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Action Items',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                fontSize: 16)),
                        const SizedBox(height: 12),
                        if (_actions.isEmpty)
                          const Text('No action items returned.',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textSecondary))
                        else
                          ..._actions.map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                const Icon(Icons.check_box_outline_blank,
                                    size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(a,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textPrimary))),
                              ]))),
                      ])),
                ]),
    );
  }
}

// ── Pinned Messages ───────────────────────────────────────────────────────────
class PinnedMessagesScreen extends StatelessWidget {
  const PinnedMessagesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Pinned Messages',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.push_pin_outlined,
                  size: 48, color: AppColors.textHint),
              SizedBox(height: 16),
              Text(
                'Coming Soon',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Pinned messages will appear here once backend support is available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Smart Q&A ─────────────────────────────────────────────────────────────────
class SmartQAScreen extends StatefulWidget {
  const SmartQAScreen({super.key});
  @override
  State<SmartQAScreen> createState() => _SmartQAScreenState();
}

class _SmartQAScreenState extends State<SmartQAScreen> {
  final _ctrl = TextEditingController();
  final _answers = <Map<String, String>>[];
  bool _asking = false;
  String? _roomId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is ChatRoom) {
        setState(() => _roomId = args.id);
      } else if (args is Map && args['room_id'] != null) {
        setState(() => _roomId = args['room_id'].toString());
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty || !mounted) return;
    final rid = _roomId;
    if (rid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open Smart Q&A from a chat (with a room) first.'),
        ),
      );
      return;
    }
    setState(() => _asking = true);
    try {
      final services = context.read<AppServices>();
      final msgs = await services.chat.getMessages(rid).unwrap();
      final transcript = msgs
          .map((m) => '${m['sender_name'] ?? 'User'}: ${m['content'] ?? ''}')
          .join('\n');
      final prompt =
          '$transcript\n\nUser question: $q\nAnswer concisely using only the conversation.';
      final summary = await services.ai.summarizeChat(prompt, topN: 8).unwrap();
      final kp = summary['key_points'];
      final answer = kp is List && kp.isNotEmpty
          ? kp.map((e) => e.toString()).join('\n')
          : summary.toString();
      if (!mounted) return;
      setState(() {
        _answers.add({'q': q, 'a': answer});
        _ctrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Smart Q&A',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          const AIBanner(
              title: 'Ask AI about this chat',
              subtitle:
                  'Answers are derived server-side from the latest messages in this room'),
          const SizedBox(height: 16),
          ..._answers.map((a) => Column(children: [
                Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(16)),
                        child: Text(a['q']!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)))),
                TCard(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.auto_awesome,
                                  color: Colors.white, size: 14)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(a['a']!,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary))),
                        ])),
              ])),
        ])),
        Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: SafeArea(
                child: Row(children: [
              Expanded(
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(24)),
                      child: TextField(
                          controller: _ctrl,
                          enabled: !_asking,
                          decoration: const InputDecoration(
                              hintText: 'Ask about this conversation…',
                              border: InputBorder.none)))),
              const SizedBox(width: 8),
              _asking
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : GestureDetector(
                      onTap: _ask,
                      child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                              color: AppColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.send,
                              color: Colors.white, size: 18))),
            ]))),
      ]),
    );
  }
}

// ── File Sharing ──────────────────────────────────────────────────────────────
class FileSharingScreen extends StatefulWidget {
  const FileSharingScreen({super.key});
  @override
  State<FileSharingScreen> createState() => _FileSharingScreenState();
}

class _FileSharingScreenState extends State<FileSharingScreen> {
  late Future<List<ApiFile>> _filesFuture;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _filesFuture = context.read<AppServices>().files.listFiles().unwrap();
  }

  void _reload() {
    setState(() {
      _filesFuture = context.read<AppServices>().files.listFiles().unwrap();
    });
  }

  Future<void> _uploadFile() async {
    if (_uploading) return;
    final fileSvc = context.read<AppServices>().files;
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    final path = picked.path;
    if (bytes == null && (path == null || path.isEmpty)) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read file from device.')),
      );
      return;
    }

    setState(() => _uploading = true);
    final upload = await fileSvc.uploadFile(
      filePath: path ?? '',
      filename: picked.name,
      fileBytes: bytes,
    );
    if (!mounted) return;
    setState(() => _uploading = false);

    if (!upload.isSuccess) {
      messenger.showSnackBar(
        SnackBar(content: Text(upload.error ?? 'Upload failed')),
      );
      return;
    }
    _reload();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Uploaded ${picked.name}'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _downloadFile(ApiFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await context
          .read<AppServices>()
          .files
          .downloadFile(file.id)
          .unwrap();
      if (!mounted) return;
      if (bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Download returned empty file')),
        );
        return;
      }
      if (kIsWeb) {
        await saveDownloadedBytes(
          filename: file.name,
          bytes: Uint8List.fromList(bytes),
          mimeType: _mimeForFilename(file.name),
        );
      } else {
        final actions = FileActions();
        final savedPath = await actions.saveBytes(file.name, bytes);
        await actions.openPath(savedPath);
      }
      if (!mounted) return;
      messenger
          .showSnackBar(SnackBar(content: Text('Downloaded ${file.name}')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Shared Files',
              style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            _uploading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.upload_file_outlined),
                    onPressed: _uploadFile,
                  ),
          ]),
      body: FutureBuilder<List<ApiFile>>(
        future: _filesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  snapshot.error?.toString() ?? 'Failed to load files',
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ]),
            );
          }
          final files = snapshot.data ?? [];
          if (files.isEmpty) {
            return const Center(
              child: Text('No shared files yet.',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _filesFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: files
                  .map((f) => TCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(
                                  Icons.insert_drive_file_outlined,
                                  color: AppColors.primary,
                                  size: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(f.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                        fontSize: 13)),
                                Text('${f.size} • ${f.uploadedBy}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                              ])),
                          IconButton(
                              icon: const Icon(Icons.download_outlined,
                                  color: AppColors.primary),
                              onPressed: () => _downloadFile(f)),
                        ]),
                      ))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}

// ── File Integrity ────────────────────────────────────────────────────────────
class FileIntegrityScreen extends StatefulWidget {
  const FileIntegrityScreen({super.key});
  @override
  State<FileIntegrityScreen> createState() => _FileIntegrityScreenState();
}

class _FileIntegrityScreenState extends State<FileIntegrityScreen> {
  late Future<List<ApiFile>> _filesFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = context.read<AppServices>().files.listFiles().unwrap();
  }

  void _reload() {
    setState(() {
      _filesFuture = context.read<AppServices>().files.listFiles().unwrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context)),
          title: const Text('File Integrity',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: FutureBuilder<List<ApiFile>>(
        future: _filesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  snapshot.error?.toString() ?? 'Failed to load files',
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ]),
            );
          }
          final files = snapshot.data ?? [];
          final verified = files.where((f) => f.sha256.isNotEmpty).length;
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _filesFuture;
            },
            child: ListView(padding: const EdgeInsets.all(16), children: [
              TCard(
                  child: Column(children: [
                Icon(
                  verified == files.length && files.isNotEmpty
                      ? Icons.verified_user
                      : Icons.info_outline,
                  color: verified > 0 ? AppColors.success : AppColors.warning,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  files.isEmpty
                      ? 'No files uploaded'
                      : '$verified / ${files.length} files report a SHA-256 hash',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Hashes come from the backend file metadata.',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                )
              ])),
              const SizedBox(height: 12),
              if (files.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No files to verify.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              else
                ...files.map((f) => TCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      Icon(
                          f.sha256.isNotEmpty
                              ? Icons.check_circle
                              : Icons.help_outline,
                          color: f.sha256.isNotEmpty
                              ? AppColors.success
                              : AppColors.warning,
                          size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(f.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary))),
                      TChip(
                          label: f.sha256.isNotEmpty ? 'SHA-256 ✓' : 'No hash',
                          bg: (f.sha256.isNotEmpty
                                  ? AppColors.success
                                  : AppColors.warning)
                              .withValues(alpha: 0.1),
                          textColor: f.sha256.isNotEmpty
                              ? AppColors.success
                              : AppColors.warning),
                    ]))),
            ]),
          );
        },
      ),
    );
  }
}

// ── Attachment Sheets & Widgets ────────────────────────────────────────────────
class _AudioRecorderSheet extends StatefulWidget {
  const _AudioRecorderSheet();

  @override
  State<_AudioRecorderSheet> createState() => _AudioRecorderSheetState();
}

class _AudioRecorderSheetState extends State<_AudioRecorderSheet> {
  bool _isRecording = false;
  bool _isPaused = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _isRecording = true;
    _isPaused = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording && !_isPaused) {
        setState(() => _seconds++);
      }
    });
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
  }

  String get _durationLabel {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Record Audio Note',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _isPaused ? Colors.orange : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isPaused
                    ? 'Paused ($_durationLabel)'
                    : 'Recording… $_durationLabel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _isPaused ? Colors.orange : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context, null),
                icon: const Icon(Icons.close),
                color: Colors.red,
                iconSize: 28,
                tooltip: 'Cancel',
              ),
              IconButton(
                onPressed: _togglePause,
                icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                color: Colors.orange,
                iconSize: 32,
                tooltip: _isPaused ? 'Resume' : 'Pause',
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, _durationLabel),
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Send'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreatePollSheet extends StatefulWidget {
  final void Function(String question, List<String> options, bool allowMultiple,
      bool isAnonymous) onCreated;
  const _CreatePollSheet({required this.onCreated});

  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;
  bool _isAnonymous = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionCtrls.length < 6) {
      setState(() => _optionCtrls.add(TextEditingController()));
    }
  }

  void _removeOption(int index) {
    if (_optionCtrls.length > 2) {
      setState(() {
        _optionCtrls[index].dispose();
        _optionCtrls.removeAt(index);
      });
    }
  }

  void _submit() {
    final q = _questionCtrl.text.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Poll question is required')));
      return;
    }
    final options = _optionCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('At least 2 options are required')));
      return;
    }
    widget.onCreated(q, options, _allowMultiple, _isAnonymous);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Create Poll',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: _questionCtrl,
              decoration: const InputDecoration(
                labelText: 'Question *',
                hintText: 'e.g. Which design direction do you prefer?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Options',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...List.generate(_optionCtrls.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionCtrls[i],
                        decoration: InputDecoration(
                          labelText: 'Option ${i + 1}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (_optionCtrls.length > 2)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: () => _removeOption(i),
                      ),
                  ],
                ),
              );
            }),
            if (_optionCtrls.length < 6)
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('Add Option'),
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Allow multiple answers'),
              value: _allowMultiple,
              onChanged: (v) => setState(() => _allowMultiple = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Anonymous voting'),
              value: _isAnonymous,
              onChanged: (v) => setState(() => _isAnonymous = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Create Poll',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateEventSheet extends StatefulWidget {
  final void Function(String title, String description, String dateStr,
      String timeStr, String location) onCreated;
  const _CreateEventSheet({required this.onCreated});

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(hours: 3));
  TimeOfDay _time =
      TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 3)));

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event title is required')));
      return;
    }

    final scheduled =
        DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    if (scheduled
        .isBefore(DateTime.now().subtract(const Duration(minutes: 5)))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Event cannot be scheduled in the past')));
      return;
    }

    final dateStr = '${_date.year}-${_date.month}-${_date.day}';
    final timeStr = _time.format(context);
    final location = _locationCtrl.text.trim().isNotEmpty
        ? _locationCtrl.text.trim()
        : 'Teamify Room';

    widget.onCreated(title, _descCtrl.text.trim(), dateStr, timeStr, location);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Schedule Event',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Event Title *',
                hintText: 'e.g. Design Sync & Q&A',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date', style: TextStyle(fontSize: 12)),
                    subtitle: Text('${_date.year}-${_date.month}-${_date.day}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (p != null) setState(() => _date = p);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Time', style: TextStyle(fontSize: 12)),
                    subtitle: Text(_time.format(context),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final p = await showTimePicker(
                          context: context, initialTime: _time);
                      if (p != null) setState(() => _time = p);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location / Link',
                hintText: 'e.g. Main Conference Room',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Schedule Event',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollCardWidget extends StatefulWidget {
  final ChatMessage message;
  const _PollCardWidget({required this.message});

  @override
  State<_PollCardWidget> createState() => _PollCardWidgetState();
}

class _PollCardWidgetState extends State<_PollCardWidget> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _parseData();
  }

  void _parseData() {
    try {
      if (widget.message.fileId != null) {
        _data = jsonDecode(widget.message.fileId!);
      }
    } catch (_) {}
  }

  void _vote(int index) {
    if (_data == null) return;
    setState(() {
      final opts = List<Map<String, dynamic>>.from(_data!['options'] as List);
      final userVoted = List<int>.from(_data!['userVoted'] as List? ?? []);
      final allowMultiple = _data!['allowMultiple'] == true;

      if (userVoted.contains(index)) {
        opts[index]['votes'] =
            ((opts[index]['votes'] as int) - 1).clamp(0, 9999);
        userVoted.remove(index);
        _data!['totalVotes'] =
            ((_data!['totalVotes'] as int) - 1).clamp(0, 9999);
      } else {
        if (!allowMultiple && userVoted.isNotEmpty) {
          for (final prev in userVoted) {
            opts[prev]['votes'] =
                ((opts[prev]['votes'] as int) - 1).clamp(0, 9999);
          }
          userVoted.clear();
          _data!['totalVotes'] =
              ((_data!['totalVotes'] as int) - 1).clamp(0, 9999);
        }
        opts[index]['votes'] = (opts[index]['votes'] as int) + 1;
        userVoted.add(index);
        _data!['totalVotes'] = (_data!['totalVotes'] as int) + 1;
      }
      _data!['options'] = opts;
      _data!['userVoted'] = userVoted;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Text(widget.message.message,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      );
    }

    final question = _data!['question']?.toString() ?? widget.message.message;
    final options =
        List<Map<String, dynamic>>.from(_data!['options'] as List? ?? []);
    final totalVotes = _data!['totalVotes'] as int? ?? 0;
    final userVoted = List<int>.from(_data!['userVoted'] as List? ?? []);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Builder(
                  builder: (_) {
                    final qDir = getTextDirection(question);
                    return Text(
                      question,
                      textDirection: qDir,
                      textAlign: getTextAlign(qDir),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.textPrimary),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(options.length, (i) {
            final opt = options[i];
            final text = opt['text']?.toString() ?? '';
            final votes = opt['votes'] as int? ?? 0;
            final pct = totalVotes > 0 ? (votes / totalVotes) : 0.0;
            final selected = userVoted.contains(i);

            return InkWell(
              onTap: () => _vote(i),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(
                            builder: (_) {
                              final optDir = getTextDirection(text);
                              return Text(
                                text,
                                textDirection: optDir,
                                textAlign: getTextAlign(optDir),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              );
                            },
                          ),
                        ),
                        Text('$votes votes',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppColors.border,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      minHeight: 4,
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            '$totalVotes total votes',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EventCardWidget extends StatefulWidget {
  final ChatMessage message;
  const _EventCardWidget({required this.message});

  @override
  State<_EventCardWidget> createState() => _EventCardWidgetState();
}

class _EventCardWidgetState extends State<_EventCardWidget> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    try {
      if (widget.message.fileId != null) {
        _data = jsonDecode(widget.message.fileId!);
      }
    } catch (_) {}
  }

  void _toggleGoing() {
    if (_data == null) return;
    setState(() {
      final isGoing = _data!['isGoing'] == true;
      _data!['isGoing'] = !isGoing;
      final count = _data!['goingCount'] as int? ?? 1;
      _data!['goingCount'] = isGoing ? (count - 1).clamp(0, 9999) : count + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _data?['title']?.toString() ?? widget.message.message;
    final dateStr = _data?['dateStr']?.toString() ?? 'Today';
    final timeStr = _data?['timeStr']?.toString() ?? widget.message.time;
    final location = _data?['location']?.toString() ?? 'Teamify Sync';
    final goingCount = _data?['goingCount'] as int? ?? 1;
    final isGoing = _data?['isGoing'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.event, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (_) {
                        final tDir = getTextDirection(title);
                        return Text(
                          title,
                          textDirection: tDir,
                          textAlign: getTextAlign(tDir),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        );
                      },
                    ),
                    Text('$dateStr at $timeStr',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Builder(
                  builder: (_) {
                    final lDir = getTextDirection(location);
                    return Text(
                      location,
                      textDirection: lDir,
                      textAlign: getTextAlign(lDir),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$goingCount going',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              ElevatedButton.icon(
                onPressed: _toggleGoing,
                icon: Icon(isGoing ? Icons.check : Icons.add, size: 16),
                label: Text(isGoing ? 'Going' : 'Join Event'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isGoing ? AppColors.success : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AudioCardWidget extends StatefulWidget {
  final ChatMessage message;
  const _AudioCardWidget({required this.message});

  @override
  State<_AudioCardWidget> createState() => _AudioCardWidgetState();
}

class _AudioCardWidgetState extends State<_AudioCardWidget> {
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    final isMe = widget.message.isMe;
    final durationStr = widget.message.fileName ?? '00:15';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isMe ? null : Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => setState(() => _isPlaying = !_isPlaying),
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: isMe ? Colors.white : AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: List.generate(
                  15,
                  (i) => Container(
                    width: 3,
                    height: (i % 3 == 0 ? 18.0 : (i % 2 == 0 ? 12.0 : 8.0)),
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isMe
                          ? (_isPlaying ? Colors.white : Colors.white60)
                          : (_isPlaying
                              ? AppColors.primary
                              : AppColors.textSecondary),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isPlaying
                    ? 'Playing… $durationStr'
                    : 'Voice note ($durationStr)',
                style: TextStyle(
                  fontSize: 11,
                  color: isMe ? Colors.white70 : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VideoCardWidget extends StatelessWidget {
  final ChatMessage message;
  const _VideoCardWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isMe ? null : Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.play_circle_fill,
                    color: Colors.white, size: 48),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      message.fileName ?? 'Video',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (message.message.isNotEmpty && message.message != 'Video') ...[
            const SizedBox(height: 8),
            Text(
              message.message,
              style: TextStyle(
                color: isMe ? Colors.white : AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
