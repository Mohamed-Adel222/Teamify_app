import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/audio/meeting_mic_keepalive.dart';
import '../../core/audio/meeting_speech_merge.dart';
import '../../core/audio/meeting_speech_pipeline.dart';
import '../../core/network/api_result.dart';
import '../../core/network/websocket_manager.dart';
import '../../core/files/file_downloader.dart';
import '../../core/routes.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme.dart';
import '../../services/app_services.dart';
import '../project/project_screens.dart' show AddTaskRouteArgs;
import '../../config/app_config.dart';
import '../../widgets/widgets.dart';
import 'meeting_summary_export.dart';
import 'meeting_transcript_utils.dart';
import 'meeting_ui.dart';

class _MeetingParticipant {
  final String userId;
  final String name;
  final String email;
  final String initials;
  bool isActive;

  _MeetingParticipant({
    required this.userId,
    required this.name,
    this.email = '',
    required this.initials,
    this.isActive = false,
  });
}

// ── Meeting Screen (Live/Start) ──────────────────────────────────────────────
class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  String? _roomId;
  String? _projectId;
  String _roomName = 'Meeting';
  List<_MeetingParticipant> _participants = [];
  Set<String> _presenceActiveIds = {};
  List<String> _liveNoteLines = [];
  List<Map<String, dynamic>> _chatRooms = [];

  bool _loading = true;
  String? _loadError;
  bool _isLive = false;
  bool _muted = false;
  String? _sessionId;
  bool _sessionSaved = false;
  bool _startingMeeting = false;
  bool _stoppingSession = false;
  bool _disposed = false;
  List<Map<String, dynamic>> _sessionTranscript = [];
  final MeetingSpeechPipeline _speechPipeline = MeetingSpeechPipeline();
  bool _speechActive = false;
  bool _speechUnavailable = false;
  int _backgroundInsightJobs = 0;
  final LiveSpeechBuffer _liveSpeech = LiveSpeechBuffer();
  String? _speechDiagnosticStatus;
  DateTime? _speechDiagnosticAt;
  bool _finalizingSpeech = false;
  bool _participantsExpanded = true;
  bool _finalizingMeeting = false;
  bool _endingMeeting = false;
  bool _isSharingScreen = false;
  Timer? _speechWatchdog;

  DateTime? _startedAt;
  Timer? _elapsedTimer;
  Timer? _pollTimer;
  StreamSubscription<SocketPayload>? _wsSub;
  WebSocketManager? _wsManager;
  String _elapsedLabel = '00:00';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _disposed = true;
    _elapsedTimer?.cancel();
    _pollTimer?.cancel();
    _speechWatchdog?.cancel();
    _wsSub?.cancel();
    _speechPipeline.dispose();
    if (kIsWeb) {
      MeetingMicKeepAlive.release();
    }
    if (_isLive && _roomId != null) {
      _wsManager?.leaveMeeting(_roomId!);
    }
    super.dispose();
  }

  void _emitLeaveMeeting(String roomId) {
    _wsManager?.leaveMeeting(roomId);
  }

  WebSocketManager? _ws() {
    try {
      return context.read<WebSocketManager>();
    } catch (_) {
      return null;
    }
  }

  void _startElapsedTimer() {
    _startedAt ??= DateTime.now();
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _startedAt;
      if (start == null || !mounted || _disposed || !_isLive) return;
      final elapsed = DateTime.now().difference(start);
      setState(() {
        _elapsedLabel = _formatDuration(elapsed);
      });
    });
  }

  Future<void> _bootstrap() async {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final argRoomId = args?['roomId']?.toString();
    final argRoomName = args?['roomName']?.toString();
    final argProjectId = args?['projectId']?.toString();

    if (AppConfig.isDemoMode) {
      final session = context.read<SessionController>();
      final me = session.currentUser;
      final myId = me?.id ?? 'demo_me';
      final myName = me?.fullName ?? me?.displayName ?? 'Alex Chen';
      setState(() {
        _roomId = argRoomId ?? 'demo_room_1';
        _roomName = argRoomName ?? 'Sprint Planning & Sync';
        _projectId = argProjectId ?? 'demo_project_1';
        _participants = [
          _MeetingParticipant(
            userId: myId,
            name: '$myName (Host)',
            email: me?.email ?? '',
            initials: _initials(myName),
            isActive: true,
          ),
          _MeetingParticipant(
            userId: 'demo_u2',
            name: 'Sarah Miller',
            email: 'sarah.m@example.com',
            initials: 'SM',
            isActive: true,
          ),
          _MeetingParticipant(
            userId: 'demo_u3',
            name: 'David Ross',
            email: 'david.r@example.com',
            initials: 'DR',
            isActive: true,
          ),
          _MeetingParticipant(
            userId: 'demo_u4',
            name: 'Emily Watson',
            email: 'emily.w@example.com',
            initials: 'EW',
            isActive: true,
          ),
        ];
        _isLive = true;
        _loading = false;
        _loadError = null;
      });
      _startElapsedTimer();
      return;
    }

    try {
      final chat = context.read<AppServices>().chat;
      final rooms = await chat.listRooms().unwrap();
      if (!mounted) return;

      _chatRooms = rooms;
      String? selectedId = argRoomId;
      if (selectedId == null ||
          selectedId.isEmpty ||
          selectedId == 'general' ||
          int.tryParse(selectedId) == null) {
        final projectRooms =
            rooms.where((r) => r['project_id'] != null).toList();
        if (projectRooms.isNotEmpty) {
          selectedId = projectRooms.first['id']?.toString();
        } else if (rooms.isNotEmpty) {
          selectedId = rooms.first['id']?.toString();
        }
      }

      if (selectedId == null) {
        setState(() {
          _loading = false;
          _loadError =
              'No chat rooms yet. Start a conversation first, then join a meeting from that chat.';
        });
        return;
      }

      await _loadRoom(
        selectedId,
        fallbackName: argRoomName,
        projectId: argProjectId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<List<_MeetingParticipant>> _loadParticipants(
    List<Map<String, dynamic>> chatMembers,
    String? projectId,
  ) async {
    final byId = <String, _MeetingParticipant>{};

    void addUser(String id, String name, String email) {
      if (id.isEmpty) return;
      byId[id] = _MeetingParticipant(
        userId: id,
        name: name,
        email: email,
        initials: _initials(name),
      );
    }

    for (final m in chatMembers) {
      addUser(
        m['user_id']?.toString() ?? '',
        m['display_name']?.toString() ?? 'User',
        m['email']?.toString() ?? '',
      );
    }

    if (projectId != null && projectId.isNotEmpty) {
      final result =
          await context.read<AppServices>().projects.listMembers(projectId);
      result.when(
        success: (users) {
          for (final u in users) {
            addUser(u.id, u.primaryName, u.email);
          }
        },
        failure: (_) {},
      );
    }

    final list = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  void _applyMeetingPresence(Map<String, dynamic> data) {
    if (data['room_id']?.toString() != _roomId) return;
    final ids =
        (data['active_user_ids'] as List?)?.map((e) => e.toString()).toSet() ??
            {};

    if (!mounted || _disposed) return;
    setState(() {
      _presenceActiveIds = ids;
      final known = {for (final p in _participants) p.userId: p};
      final users = (data['users'] as List?)?.whereType<Map>();
      if (users != null) {
        for (final raw in users) {
          final u = Map<String, dynamic>.from(raw);
          final id = u['user_id']?.toString() ?? '';
          if (id.isEmpty || known.containsKey(id)) continue;
          final name = u['display_name']?.toString() ?? 'User';
          _participants.add(_MeetingParticipant(
            userId: id,
            name: name,
            email: u['email']?.toString() ?? '',
            initials: _initials(name),
            isActive: ids.contains(id),
          ));
        }
      }
      for (final p in _participants) {
        p.isActive = _isLive && ids.contains(p.userId);
      }
    });
  }

  Future<void> _loadRoom(
    String roomId, {
    String? fallbackName,
    String? projectId,
  }) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final data =
          await context.read<AppServices>().chat.getRoom(roomId).unwrap();
      if (!mounted) return;

      final room = data['room'] as Map<String, dynamic>? ?? {};
      final members = (data['members'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];

      final name = room['name']?.toString().trim();
      _roomId = roomId;
      _projectId = room['project_id']?.toString() ?? projectId;
      _roomName = (name != null && name.isNotEmpty)
          ? name
          : (fallbackName ?? 'Chat $roomId');

      final session = context.read<SessionController>();
      final myId = session.currentUser?.id ?? '';

      _participants = await _loadParticipants(members, _projectId);

      if (_participants.isEmpty && myId.isNotEmpty) {
        final me = session.currentUser;
        final meName = me?.displayName ?? me?.fullName ?? 'You';
        _participants = [
          _MeetingParticipant(
            userId: myId,
            name: meName,
            email: me?.email ?? '',
            initials: _initials(meName),
          ),
        ];
      }

      await _refreshLiveNotes();

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  /// Keeps speech lines and merges in chat messages (by id), sorted by time.
  List<Map<String, dynamic>> _mergeChatIntoTranscript(
    List<Map<String, dynamic>> chatEntries,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final e in _sessionTranscript) {
      if (e['source']?.toString() == 'speech') {
        final id = e['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          byId[id] = Map<String, dynamic>.from(e);
        }
      }
    }
    for (final e in chatEntries) {
      final id = e['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      byId[id] = Map<String, dynamic>.from(e);
    }
    final merged = byId.values.toList();
    merged.sort((a, b) {
      final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return da.compareTo(db);
    });
    return merged;
  }

  List<Map<String, dynamic>> _transcriptSnapshot() {
    return _sessionTranscript.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _refreshLiveNotes() async {
    final rid = _roomId;
    if (rid == null) return;

    List<Map<String, dynamic>> msgs;
    try {
      msgs = await context
          .read<AppServices>()
          .chat
          .getMessages(rid, perPage: 50)
          .unwrap();
    } catch (_) {
      return;
    }

    if (!mounted) return;

    final lines = msgs
        .map((m) => '${m['sender_name'] ?? 'User'}: ${m['content'] ?? ''}')
        .where((line) => line.trim().length > 2)
        .toList();

    List<String> noteLines;
    if (_isLive && _startedAt != null) {
      noteLines = [];
      final chatEntries = <Map<String, dynamic>>[];
      for (final m in msgs) {
        final created = m['created_at']?.toString() ?? '';
        final dt = DateTime.tryParse(created);
        if (dt != null && !dt.isBefore(_startedAt!)) {
          noteLines.add(
            '${m['sender_name'] ?? 'User'}: ${m['content'] ?? ''}',
          );
          chatEntries.add({
            'id': m['id'],
            'sender_id': m['sender_id'],
            'sender_name': m['sender_name'] ?? 'User',
            'content': m['content'] ?? '',
            'created_at': created,
          });
        }
      }
      // Merge chat with speech — do not replace (speech would be lost on save).
      _sessionTranscript = _mergeChatIntoTranscript(chatEntries);
      noteLines = _sessionTranscript
          .map((e) {
            final name = e['sender_name'] ?? 'User';
            final text = e['content'] ?? '';
            if (e['source']?.toString() == 'speech') {
              return '[Speech] $name: $text';
            }
            return '$name: $text';
          })
          .where((line) => line.trim().length > 2)
          .toList();
    } else {
      noteLines = lines.length > 5 ? lines.sublist(lines.length - 5) : lines;
      noteLines = noteLines
          .map((l) => l.length > 220 ? '${l.substring(0, 217)}…' : l)
          .toList();
    }

    if (!mounted || _disposed) return;
    final cap = _isLive ? 8 : 5;
    setState(() {
      for (final p in _participants) {
        p.isActive = _isLive && _presenceActiveIds.contains(p.userId);
      }
      _liveNoteLines = noteLines.length > cap
          ? noteLines.sublist(noteLines.length - cap)
          : noteLines;
    });
  }

  Future<void> _startMeeting() async {
    final rid = _roomId;
    if (rid == null || _startingMeeting) return;

    setState(() => _startingMeeting = true);

    final chat = context.read<AppServices>().chat;
    try {
      final session = await chat.startMeetingSession(rid).unwrap();
      if (!mounted) return;

      final startedAt = DateTime.now();
      final myId = context.read<SessionController>().currentUser?.id ?? '';

      setState(() {
        _startingMeeting = false;
        _isLive = true;
        _participantsExpanded = false;
        _liveSpeech.committed = '';
        _liveSpeech.clearPartial();
        _speechDiagnosticStatus = null;
        _muted = false;
        _speechUnavailable = false;
        _sessionId = session['id']?.toString();
        _sessionSaved = false;
        _sessionTranscript = [];
        _startedAt = startedAt;
        _presenceActiveIds = {if (myId.isNotEmpty) myId};
        for (final p in _participants) {
          p.isActive = p.userId == myId;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _startingMeeting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start meeting: $e')),
      );
      return;
    }

    _startElapsedTimer();

    _wsSub?.cancel();
    _pollTimer?.cancel();

    _startSpeechWatchdog();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _disposed || !_isLive) return;
      await _startSpeechCapture();
      if (mounted && !_disposed && _isLive && !_speechPipeline.isLiveActive) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted && _isLive) await _startSpeechCapture();
      }
    });

    _wsManager = _ws();
    final wsManager = _wsManager;
    if (wsManager != null && !wsManager.isConnected) {
      await wsManager.connect();
    }
    if (wsManager != null && wsManager.isConnected) {
      wsManager.joinRoom(rid);
      wsManager.joinMeeting(rid);
      _wsSub = wsManager.stream.listen((payload) {
        if (payload.event == SocketEvent.meetingPresence) {
          _applyMeetingPresence(payload.data);
        } else if (payload.event == SocketEvent.chatMessage) {
          if (payload.data['room_id']?.toString() == _roomId) {
            _refreshLiveNotes();
          }
        }
      });
    }
    _refreshLiveNotes();
  }

  List<String> _participantIdsForSession() {
    final ids = <String>{..._presenceActiveIds};
    final myId = context.read<SessionController>().currentUser?.id;
    if (myId != null && myId.isNotEmpty) ids.add(myId);
    return ids.toList();
  }

  Future<Map<String, dynamic>?> _persistSession({
    bool silent = false,
    bool force = false,
  }) async {
    final rid = _roomId;
    final sid = _sessionId;
    if (rid == null || sid == null) return null;
    if (!force && (_sessionSaved || _stoppingSession)) {
      return null;
    }

    if (!silent && mounted) {
      setState(() => _stoppingSession = true);
    }

    final participantIds = _participantIdsForSession();
    final transcript = _transcriptSnapshot();
    final chat = context.read<AppServices>().chat;
    try {
      final session = await chat
          .stopMeetingSession(
            rid,
            sid,
            transcript: transcript,
            participantIds: participantIds,
          )
          .unwrap();
      _sessionSaved = true;
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meeting transcript saved'),
          ),
        );
      }
      return session;
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save transcript: $e')),
        );
      }
      return null;
    } finally {
      if (!silent && mounted) {
        setState(() => _stoppingSession = false);
      }
    }
  }

  void _startSpeechWatchdog() {
    _speechWatchdog?.cancel();
    _speechWatchdog = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isLive || _muted || _disposed || _speechUnavailable) return;
      if (!_speechPipeline.isLiveActive) {
        _startSpeechCapture();
      }
    });
  }

  void _stopSpeechWatchdog() {
    _speechWatchdog?.cancel();
    _speechWatchdog = null;
  }

  Future<String?> _transcribeBytes(Uint8List bytes, String filename) async {
    final result = await context.read<AppServices>().ai.transcribe(
          bytes,
          filename: filename,
        );
    if (!result.isSuccess) return null;
    return result.data?.text.trim();
  }

  Future<void> _startSpeechCapture() async {
    final started = await _speechPipeline.start(
      onLiveText: _handleLiveSpeech,
      transcribeFallback: _transcribeBytes,
      onError: _onSpeechEngineError,
      onStatus: _onSpeechEngineStatus,
      onWhisperRefine: _handleWhisperRefinement,
      onBackgroundJobsChanged: (count) {
        if (mounted && !_disposed) {
          setState(() => _backgroundInsightJobs = count);
        }
      },
      shouldRun: () => (_isLive || _finalizingSpeech) && !_muted && !_disposed,
    );

    if (!mounted || _disposed) return;

    if (started) {
      setState(() {
        _speechActive = true;
        _speechUnavailable = false;
      });
      return;
    }

    setState(() {
      _speechUnavailable = true;
      _speechActive = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Microphone or speech recognition unavailable. Allow mic in the browser, then tap Enable microphone.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  void _onSpeechEngineError(String message) {
    debugPrint('Meeting speech error: $message');
    final denied = message.contains('not-allowed') ||
        message.contains('not_allowed') ||
        message.contains('audio-capture') ||
        message.contains('service-not-allowed');
    if (denied && mounted && !_disposed) {
      setState(() {
        _speechUnavailable = true;
        _speechActive = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition blocked. Allow microphone.'),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    if (_isLive && !_muted && !_disposed) {
      Future.delayed(
          const Duration(milliseconds: 400), _ensureSpeechCaptureRunning);
    }
  }

  void _onSpeechEngineStatus(String status) {
    if (!mounted || _disposed) return;
    setState(() {
      _speechDiagnosticStatus = status;
      _speechDiagnosticAt = DateTime.now();
      if (status == 'listening' || status == 'speech_detected') {
        _speechUnavailable = false;
        _speechActive = true;
      }
    });
  }

  String? _speechDiagnosticLabel() {
    final s = _speechDiagnosticStatus;
    if (s == null) return null;
    if (_speechDiagnosticAt != null &&
        DateTime.now().difference(_speechDiagnosticAt!) >
            const Duration(seconds: 12)) {
      return null;
    }
    return switch (s) {
      'listening' => 'Listening',
      'speech_detected' => 'Speech detected',
      'restarting' => 'Restarting recognition',
      'finalizing_phrase' => 'Finalizing phrase',
      'whisper_refining' => 'Whisper refining',
      'ended' => 'Recognition paused — restarting',
      'error' => 'Recognition error',
      _ => null,
    };
  }

  Future<void> _retryMicrophone() async {
    if (!_isLive || _disposed) return;
    await _stopSpeechCapture();
    await _startSpeechCapture();
  }

  Future<void> _stopSpeechCapture() async {
    await _speechPipeline.shutdown();
    if (kIsWeb) {
      MeetingMicKeepAlive.release();
    }
    if (mounted && !_disposed) {
      setState(() {
        _speechActive = false;
        _liveSpeech.clearPartial();
        _speechDiagnosticStatus = null;
        _backgroundInsightJobs = 0;
      });
    }
  }

  void _finalizeLocalTranscript() {
    final text = _streamingSpeechText().trim();
    if (text.isEmpty) return;
    _liveSpeech.committed = text;
    _liveSpeech.clearPartial();
    _upsertSpeechTranscript(text);
    _syncStreamingLiveNote();
  }

  Future<void> _flushSpeechCapture() async {
    if ((!_isLive && !_finalizingSpeech) || _muted) return;
    await _speechPipeline.commitPartial(_handleLiveSpeech);
  }

  String _streamingSpeechText() => _liveSpeech.displayText;

  void _handleWhisperRefinement(String text) {
    if ((!_isLive && !_finalizingSpeech) ||
        _muted ||
        !mounted ||
        _disposed ||
        text.trim().isEmpty) {
      return;
    }
    setState(() {
      _liveSpeech.applyWhisperRefinement(text);
      _syncStreamingLiveNote();
    });
    _upsertSpeechTranscript(_liveSpeech.committed);
  }

  void _handleLiveSpeech(String text, bool isFinal) {
    if ((!_isLive && !_finalizingSpeech) ||
        _muted ||
        !mounted ||
        _disposed ||
        text.trim().isEmpty) {
      return;
    }

    setState(() {
      if (isFinal) {
        _liveSpeech.applyFinal(text);
      } else {
        _liveSpeech.applyPartial(text);
      }
      _syncStreamingLiveNote();
    });

    if (isFinal) {
      _upsertSpeechTranscript(_liveSpeech.committed);
    }
  }

  void _syncStreamingLiveNote() {
    if (!mounted || _disposed) return;
    final user = context.read<SessionController>().currentUser;
    final name = (user?.fullName.isNotEmpty == true)
        ? user!.fullName
        : (user?.displayName ?? 'You');
    final committed = _liveSpeech.committed.trim();
    if (committed.isEmpty)
      return; // in-progress text → partialSpeech bubble below

    final speechPrefix = '[Speech] $name: ';
    final notes = [..._liveNoteLines];
    var speechIdx = -1;
    for (var i = notes.length - 1; i >= 0; i--) {
      if (notes[i].startsWith(speechPrefix)) {
        speechIdx = i;
        break;
      }
    }
    final line = '$speechPrefix$committed';
    if (speechIdx >= 0) {
      notes[speechIdx] = line;
    } else {
      notes.add(line);
    }
    _liveNoteLines =
        notes.length > 24 ? notes.sublist(notes.length - 24) : notes;
  }

  void _upsertSpeechTranscript(String fullText) {
    if (fullText.trim().isEmpty) return;
    final user = context.read<SessionController>().currentUser;
    final name = (user?.fullName.isNotEmpty == true)
        ? user!.fullName
        : (user?.displayName ?? 'You');
    final myId = user?.id ?? '';

    final idx = _sessionTranscript.indexWhere(
      (e) =>
          e['source']?.toString() == 'speech' &&
          e['sender_id']?.toString() == myId,
    );

    final entry = {
      'id': idx >= 0
          ? _sessionTranscript[idx]['id']
          : 'speech-live-${_sessionId ?? '0'}',
      'source': 'speech',
      'sender_id': myId,
      'sender_name': name,
      'content': fullText,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (idx >= 0) {
      _sessionTranscript = [
        ..._sessionTranscript.sublist(0, idx),
        entry,
        ..._sessionTranscript.sublist(idx + 1),
      ];
    } else {
      _sessionTranscript = [..._sessionTranscript, entry];
    }
  }

  /// Save transcript to the server but keep the meeting live and recording.
  Future<void> _saveTranscriptCheckpoint() async {
    if (_stoppingSession || !_isLive) return;

    final chat = context.read<AppServices>().chat;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _stoppingSession = true);
    await _flushSpeechCapture();
    await _refreshLiveNotes();

    final rid = _roomId;
    final sid = _sessionId;
    if (rid == null || sid == null) {
      if (mounted) setState(() => _stoppingSession = false);
      return;
    }

    try {
      await chat
          .saveMeetingCheckpoint(
            rid,
            sid,
            transcript: _transcriptSnapshot(),
            participantIds: _participantIdsForSession(),
          )
          .unwrap();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Transcript saved — meeting still live. Recording continues.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to save transcript: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _stoppingSession = false);
    }

    await _ensureSpeechCaptureRunning();
  }

  Future<void> _ensureSpeechCaptureRunning() async {
    if (!_isLive || _muted || _disposed) return;
    if (_speechPipeline.isLiveActive) return;
    await _startSpeechCapture();
  }

  Future<void> _toggleMute() async {
    if (!_isLive || _disposed) return;
    final next = !_muted;
    setState(() => _muted = next);
    if (next) {
      await _speechPipeline.commitPartial(_handleLiveSpeech);
      await _speechPipeline.shutdown();
      if (mounted) setState(() => _speechActive = false);
    } else {
      await _ensureSpeechCaptureRunning();
    }
  }

  Future<void> _toggleRecord() async {
    if (!_isLive || _disposed) return;
    if (_speechUnavailable) {
      await _retryMicrophone();
      return;
    }
    if (_speechActive && !_muted) return;
    setState(() => _muted = false);
    await _startSpeechCapture();
  }

  Future<void> _endMeeting() async {
    if (_endingMeeting) return;
    _endingMeeting = true;

    if (mounted) {
      setState(() => _finalizingMeeting = true);
    }

    final wasLive = _isLive;
    final rid = _roomId;
    final sessionId = _sessionId;
    Map<String, dynamic>? endedSession;

    try {
      _stopSpeechWatchdog();
      _finalizingSpeech = true;

      await _speechPipeline.commitPartial(_handleLiveSpeech);
      _finalizeLocalTranscript();
      await _speechPipeline.drainBackground();

      _isLive = false;
      _finalizingSpeech = false;

      await _speechPipeline.shutdown();
      if (kIsWeb) {
        MeetingMicKeepAlive.release();
      }

      if (mounted && !_disposed) {
        setState(() {
          _speechActive = false;
          _liveSpeech.clearPartial();
          _backgroundInsightJobs = 0;
        });
      }

      _elapsedTimer?.cancel();
      _pollTimer?.cancel();
      _wsSub?.cancel();

      if (wasLive && rid != null) {
        _emitLeaveMeeting(rid);
      }

      if (sessionId != null && sessionId.isNotEmpty) {
        endedSession = await _persistSession(silent: true, force: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to finalize meeting: $e')),
        );
      }
    } finally {
      _endingMeeting = false;
      if (mounted) {
        setState(() => _finalizingMeeting = false);
      }
    }

    if (!mounted || _disposed) return;

    if (rid == null) {
      Navigator.pop(context);
      return;
    }

    final transcript = _transcriptSnapshot();
    final elapsedSecs = _startedAt != null
        ? DateTime.now().difference(_startedAt!).inSeconds
        : null;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingSummaryScreen(
          roomName: _roomName,
          roomId: rid,
          sessionId: sessionId,
          projectId: _projectId,
          inlineTranscript: transcript,
          sessionStartedAt: _startedAt,
          sessionDurationSeconds: elapsedSecs,
          initialSession: endedSession,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '${h.toString().padLeft(2, '0')}:$m:$s';
    return '$m:$s';
  }

  String _initials(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  int get _activeCount => _participants.where((p) => p.isActive).length;

  bool get _isRecordingUi => _speechActive && !_muted && !_speechUnavailable;

  String _meetingInfoSubtitle() {
    final count = _isLive ? _activeCount : _participants.length;
    final label = count == 1 ? 'participant' : 'participants';
    if (_isLive) {
      return '$count $label • $_elapsedLabel';
    }
    return '$count $label';
  }

  MeetingTranscriptPhase _transcriptPhase() {
    if (_finalizingMeeting) return MeetingTranscriptPhase.processing;
    if (_stoppingSession) return MeetingTranscriptPhase.saving;
    if (_isRecordingUi) return MeetingTranscriptPhase.recording;
    if (_backgroundInsightJobs > 0) return MeetingTranscriptPhase.processing;
    return MeetingTranscriptPhase.idle;
  }

  String _transcriptDetail() {
    if (_finalizingMeeting) {
      return 'Finalizing meeting…';
    }
    if (_sessionId == null) return 'Starting session…';
    final sid = 'Session #$_sessionId';
    if (_stoppingSession) return '$sid · saving transcript';
    if (_isRecordingUi) {
      final diag = _speechDiagnosticLabel();
      if (diag != null) {
        return '$sid · $diag';
      }
      if (_backgroundInsightJobs > 0) {
        return '$sid · live transcription · Whisper refine in background';
      }
      return '$sid · live transcription active';
    }
    if (_backgroundInsightJobs > 0) {
      return '$sid · processing meeting insights…';
    }
    if (_speechUnavailable) return '$sid · chat only — enable microphone';
    return '$sid · ready to capture';
  }

  ParticipantPresence _presenceFor(_MeetingParticipant p) {
    if (p.isActive) return ParticipantPresence.inMeeting;
    return ParticipantPresence.notJoined;
  }

  List<Widget> _participantTiles() {
    return _participants
        .map(
          (p) => MeetingParticipantTile(
            name: p.name,
            email: p.email,
            initials: p.initials,
            presence: _presenceFor(p),
          ),
        )
        .toList();
  }

  Widget _finalizingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              _finalizingMeeting ? '⚡ Finalizing meeting…' : 'Processing…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saving transcript and generating summary',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final me = context.read<SessionController>().currentUser;
    final canShareScreen = me?.isStudent == true || me?.isFreelancer == true;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, size: 18, color: onSurface),
            onPressed: (_isLive || _finalizingMeeting)
                ? null
                : () => Navigator.pop(context)),
        title: Text('Meeting',
            style: TextStyle(
                color: onSurface, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? _errorBody()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_chatRooms.isNotEmpty) ...[
                            MeetingRoomPicker(
                              roomId: _roomId,
                              rooms: _chatRooms,
                              enabled: !_isLive,
                              onChanged: (id) {
                                if (id != null) _loadRoom(id);
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          MeetingInfoHeader(
                            title: _roomName,
                            subtitle: _meetingInfoSubtitle(),
                            isLive: _isLive,
                          ),
                          const SizedBox(height: 8),
                          if (_isLive) ...[
                            MeetingTranscriptStatusCard(
                              phase: _transcriptPhase(),
                              detail: _transcriptDetail(),
                              durationLabel: _elapsedLabel,
                              diagnosticLabel: _speechDiagnosticLabel(),
                            ),
                            const SizedBox(height: 8),
                          ],
                          MeetingParticipantsPanel(
                            expanded: _participantsExpanded,
                            onToggle: () => setState(
                              () => _participantsExpanded =
                                  !_participantsExpanded,
                            ),
                            participantCount: _participants.length,
                            activeCount: _activeCount,
                            isLive: _isLive,
                            children: _participants.isEmpty
                                ? [
                                    const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text(
                                        'No members in this room yet.',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ]
                                : _participantTiles(),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _isLive
                                ? _liveMeetingBody()
                                : _idleMeetingScrollBody(),
                          ),
                          if (_isLive)
                            SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: MeetingLiveControls(
                                  muted: _muted,
                                  isRecording: _isRecordingUi,
                                  speechUnavailable: _speechUnavailable,
                                  saving: _stoppingSession,
                                  isSharing: _isSharingScreen,
                                  onMute: _toggleMute,
                                  onRecord:
                                      _stoppingSession ? null : _toggleRecord,
                                  onSave: _stoppingSession
                                      ? null
                                      : _saveTranscriptCheckpoint,
                                  onShare: canShareScreen
                                      ? () => setState(() => _isSharingScreen = !_isSharingScreen)
                                      : null,
                                  onEndMeeting:
                                      _finalizingMeeting ? () {} : _endMeeting,
                                ),
                              ),
                            )
                          else
                            SafeArea(
                              top: false,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: FilledButton(
                                    onPressed:
                                        _roomId == null || _startingMeeting
                                            ? null
                                            : _startMeeting,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          MeetingUi.radiusMd,
                                        ),
                                      ),
                                    ),
                                    child: _startingMeeting
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Start Meeting',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
          if (_finalizingMeeting) _finalizingOverlay(),
        ],
      ),
    );
  }

  /// Before meeting starts: recent chat preview.
  Widget _idleMeetingScrollBody() {
    final hasRecentChat = _liveNoteLines.isNotEmpty;
    if (!hasRecentChat) {
      return Center(
        child: Text(
          _projectId != null
              ? 'Start the meeting to capture speech and chat.'
              : 'Start the meeting when your team is ready.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent chat',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: MeetingUi.cardDecoration(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: _liveNoteLines
                  .map(
                    (line) => MeetingSpeechBubble(
                      line: MeetingNoteLine.parse(line) ??
                          MeetingNoteLine(speaker: 'Chat', text: line),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _liveMeetingBody() {
    if (_isSharingScreen) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary, width: 2),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.screen_share, color: Colors.white, size: 36),
              SizedBox(height: 8),
              Text(
                'You are sharing your screen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return MeetingLiveNotesCard(
            lines: _liveNoteLines,
            partialSpeech: _liveSpeech.utterancePartial.isEmpty
                ? null
                : _liveSpeech.utterancePartial,
            emptyHint: _isRecordingUi
                ? 'Live transcription active — speak naturally. Words appear here as you talk.'
                : _speechUnavailable
                    ? 'Allow microphone access to capture speech.'
                    : 'Waiting for microphone…',
            micBanner: _speechUnavailable
                ? Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDBA74)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.mic_off_rounded,
                                size: 18, color: Color(0xFFEA580C)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Microphone access needed',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _retryMicrophone,
                            icon: const Icon(Icons.mic_rounded, size: 18),
                            label: const Text('Enable microphone'),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
    );
  }

  Widget _errorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _loadError = null;
                });
                _bootstrap();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Meeting Summary Screen ───────────────────────────────────────────────────
class MeetingSummaryScreen extends StatefulWidget {
  final String roomName;
  final String roomId;
  final String? sessionId;
  final String? projectId;
  final List<Map<String, dynamic>> inlineTranscript;
  final DateTime? sessionStartedAt;
  final int? sessionDurationSeconds;
  final Map<String, dynamic>? initialSession;

  const MeetingSummaryScreen({
    super.key,
    required this.roomName,
    required this.roomId,
    this.sessionId,
    this.projectId,
    this.inlineTranscript = const [],
    this.sessionStartedAt,
    this.sessionDurationSeconds,
    this.initialSession,
  });

  @override
  State<MeetingSummaryScreen> createState() => _MeetingSummaryScreenState();
}

class _MeetingSummaryScreenState extends State<MeetingSummaryScreen> {
  bool _loading = true;
  String? _error;
  String _summaryText = '';
  List<String> _summaryBullets = [];
  List<String> _keyPoints = [];
  List<String> _decisions = [];
  List<Map<String, String>> _actions = [];
  int _participantsCount = 0;
  String? _durationLabel;
  bool _exportBusy = false;
  bool _canCreateTasks = false;
  String? _linkedProjectId;
  List<String> _transcriptLines = [];
  int _transcriptEntryCount = 0;
  bool _transcriptExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
  }

  Future<void> _loadSummary() async {
    try {
      final svc = context.read<AppServices>();
      Map<String, dynamic>? storedSummary;
      DateTime? sessionStarted;
      DateTime? sessionEnded;
      int? sessionSecs = widget.sessionDurationSeconds;

      List<Map<String, dynamic>> msgs =
          normalizeMeetingTranscript(widget.inlineTranscript);

      final initial = widget.initialSession;
      if (initial != null) {
        final rawTranscript = initial['transcript'];
        if (msgs.isEmpty && rawTranscript is List) {
          msgs = normalizeMeetingTranscript(
            rawTranscript
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(),
          );
        }
        final aiSummary = initial['ai_summary'];
        if (aiSummary is Map && aiSummary.isNotEmpty) {
          storedSummary = Map<String, dynamic>.from(aiSummary);
        } else {
          final summaryText = initial['summary']?.toString().trim();
          if (summaryText != null && summaryText.isNotEmpty) {
            storedSummary = {
              'summary': summaryText,
              'key_points': initial['key_points'],
              'action_items': initial['action_items'],
              'speech_transcript': initial['speech_transcript'],
            };
          }
        }
        final secs = initial['duration_seconds'];
        if (secs is int && secs > 0) {
          sessionSecs = secs;
        }
        sessionEnded = DateTime.tryParse(initial['ended_at']?.toString() ?? '');
      }

      Map<String, dynamic>? roomPayload;
      try {
        roomPayload = await svc.chat.getRoom(widget.roomId).unwrap();
        final members = (roomPayload['members'] as List?)
            ?.whereType<Map<String, dynamic>>();
        _participantsCount = members?.length ?? 0;
      } catch (_) {}

      await _resolveCreateTasksPermission(svc, roomPayload);

      final sid = widget.sessionId;
      if (sid != null && sid.isNotEmpty) {
        try {
          final session =
              await svc.chat.getMeetingSession(widget.roomId, sid).unwrap();

          sessionStarted = DateTime.tryParse(
                session['started_at']?.toString() ?? '',
              ) ??
              widget.sessionStartedAt;
          sessionEnded =
              DateTime.tryParse(session['ended_at']?.toString() ?? '');

          final secs = session['duration_seconds'];
          if (secs is int && secs > 0 && secs <= 8 * 3600) {
            sessionSecs = secs;
          }

          final transcriptRaw = session['transcript'];
          final dbMsgs = transcriptRaw is List
              ? normalizeMeetingTranscript(
                  transcriptRaw
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList(),
                )
              : <Map<String, dynamic>>[];

          if (msgs.isEmpty) {
            msgs = dbMsgs;
          }

          final summaryText = session['summary']?.toString().trim();
          final aiSummary = session['ai_summary'];
          if (summaryText != null && summaryText.isNotEmpty) {
            storedSummary = {
              'summary': summaryText,
              'key_points': session['key_points'],
              'action_items': session['action_items'],
              'speech_transcript': session['speech_transcript'],
            };
          } else if (aiSummary is Map) {
            storedSummary = Map<String, dynamic>.from(aiSummary);
          }
        } catch (_) {}
      }

      sessionStarted ??= widget.sessionStartedAt;
      _durationLabel = formatMeetingDuration(
        durationSeconds: sessionSecs,
        startedAt: sessionStarted,
        endedAt: sessionEnded,
      );

      if (msgs.isEmpty && sid == null) {
        try {
          final raw =
              await svc.chat.getMessages(widget.roomId, perPage: 30).unwrap();
          msgs = normalizeMeetingTranscript(raw);
        } catch (_) {}
      }

      if (msgs.isNotEmpty) {
        final fromTranscript = countUniqueParticipants(msgs);
        if (fromTranscript > 0) {
          _participantsCount = fromTranscript;
        }
      }

      if (storedSummary != null && msgs.isNotEmpty) {
        storedSummary = await _refreshSummaryIfSparse(
          svc,
          msgs,
          storedSummary,
        );
      }

      if (storedSummary != null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _applySummaryPayload(storedSummary!, msgs);
        });
        return;
      }

      if (msgs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _summaryText = 'No messages were captured in this meeting.';
        });
        return;
      }

      final transcript = msgs
          .map((m) => '${m['sender_name'] ?? 'User'}: ${m['content'] ?? ''}')
          .where((l) => l.trim().length > 3)
          .join('\n');

      Map<String, dynamic> summary;
      try {
        summary = await svc.ai.summarizeChat(transcript, topN: 5).unwrap();
      } catch (_) {
        summary = _buildLocalSummaryPayload(msgs);
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _applySummaryPayload(summary, msgs);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _resolveCreateTasksPermission(
    AppServices svc,
    Map<String, dynamic>? roomPayload,
  ) async {
    final userId =
        context.read<SessionController>().currentUser?.id.toString() ?? '';
    if (userId.isEmpty) {
      _canCreateTasks = false;
      _linkedProjectId = null;
      return;
    }

    var projectId = widget.projectId?.trim();
    if (projectId == null || projectId.isEmpty) {
      final room = roomPayload?['room'];
      if (room is Map) {
        final raw = room['project_id'];
        if (raw != null) projectId = raw.toString();
      }
    }

    if (projectId == null || projectId.isEmpty) {
      _canCreateTasks = false;
      _linkedProjectId = null;
      return;
    }

    try {
      final project = await svc.projects.getProject(projectId).unwrap();
      _linkedProjectId = projectId;
      _canCreateTasks = project.ownerId.isNotEmpty && project.ownerId == userId;
    } catch (_) {
      _canCreateTasks = false;
      _linkedProjectId = null;
    }
  }

  String _transcriptPlainText(List<Map<String, dynamic>> msgs) {
    return msgs
        .map((m) => '${m['sender_name'] ?? 'User'}: ${m['content'] ?? ''}')
        .where((l) => l.trim().length > 3)
        .join('\n');
  }

  Future<Map<String, dynamic>> _refreshSummaryIfSparse(
    AppServices svc,
    List<Map<String, dynamic>> msgs,
    Map<String, dynamic> existing,
  ) async {
    final summaryText = existing['summary']?.toString().trim() ?? '';
    final kp = filterSummaryBullets(cleanKeyPoints(existing['key_points']));
    final needsAi = kp.isEmpty &&
        (summaryText.isEmpty ||
            summaryText.length < 24 ||
            isRawSpeechChunk(summaryText));

    if (!needsAi) return existing;

    try {
      final fresh = await svc.ai
          .summarizeChat(_transcriptPlainText(msgs), topN: 6)
          .unwrap();
      return {
        ...existing,
        ...fresh,
        if (summaryText.isNotEmpty) 'summary': summaryText,
      };
    } catch (_) {
      return existing;
    }
  }

  void _applySummaryPayload(
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> msgs,
  ) {
    final normalized = normalizeMeetingTranscript(msgs);

    var summaryRaw = summary['summary']?.toString().trim() ?? '';
    if (summaryRaw.isEmpty) {
      summaryRaw = _buildLocalSummaryText(normalized);
    }
    _summaryText = clampSummaryText(summaryRaw);

    _keyPoints = cleanKeyPoints(summary['key_points']);
    if (_keyPoints.isEmpty) {
      _keyPoints = cleanKeyPoints(_extractLocalKeyPoints(normalized));
    }

    _summaryBullets = filterSummaryBullets(
      _keyPoints.isNotEmpty
          ? List<String>.from(_keyPoints)
          : summaryTextToBullets(_summaryText),
    );

    if (_summaryBullets.isEmpty) {
      _summaryBullets = narrativeBulletsFromMeeting(normalized);
    }

    _transcriptLines = _buildTranscriptLines(normalized);
    _transcriptEntryCount = normalized
        .where((m) => (m['content']?.toString().trim() ?? '').isNotEmpty)
        .length;

    _decisions = cleanKeyPoints(summary['decisions'], maxItems: 6);
    if (_decisions.isEmpty) {
      _decisions = localMeetingDecisions(
        msgs: normalized,
        summaryText: _summaryText,
      );
    }

    _actions = cleanActionItems(summary['action_items']);
    if (_actions.isEmpty) {
      _actions = relaxedActionItems(summary['action_items']);
    }
    if (_actions.isEmpty) {
      _actions = localMeetingActions(normalized);
    }
    if (_actions.isEmpty) {
      _actions = learningActionsFromTranscript(normalized);
    }
    _actions = _actions
        .where((a) => !looksLikeTranscriptDump(a['text'] ?? ''))
        .toList();
  }

  List<String> _buildTranscriptLines(List<Map<String, dynamic>> msgs) {
    final speechMsgs =
        msgs.where((m) => m['source']?.toString() == 'speech').toList();
    if (speechMsgs.isNotEmpty) {
      return formatTranscriptDisplayLines(speechMsgs);
    }
    return formatTranscriptDisplayLines(msgs);
  }

  Map<String, dynamic> _buildLocalSummaryPayload(
    List<Map<String, dynamic>> msgs,
  ) {
    return {
      'summary': _buildLocalSummaryText(msgs),
      'speech_transcript': msgs
          .where((m) => m['source']?.toString() == 'speech')
          .map((m) => '${m['sender_name'] ?? 'User'}: ${m['content'] ?? ''}')
          .toList(),
      'key_points': _extractLocalKeyPoints(msgs),
      'action_items': const [],
    };
  }

  String _buildLocalSummaryText(List<Map<String, dynamic>> msgs) {
    if (msgs.isEmpty) {
      return 'No speech or chat content was captured in this meeting.';
    }
    final speech = msgs
        .where((m) => m['source']?.toString() == 'speech')
        .map((m) => (m['content'] ?? '').toString().trim())
        .where((s) => s.length >= 8)
        .toList();
    final chat = msgs
        .where((m) => m['source']?.toString() != 'speech')
        .map((m) => (m['content'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final who = msgs.first['sender_name']?.toString() ?? 'Participants';

    if (speech.isNotEmpty) {
      final bullets = narrativeBulletsFromMeeting(msgs, maxItems: 3);
      if (bullets.isNotEmpty) {
        return '$who discussed: ${bullets.join(' ')}';
      }
      final chunks = chunkTextByWords(speech.first, maxChunk: 120);
      final snippet = chunks.isNotEmpty
          ? chunks.first
          : speech.first.substring(0, speech.first.length.clamp(0, 120));
      return '$who led this session. Topics covered: ${polishBulletLine(snippet)}';
    }
    if (chat.isNotEmpty) {
      return '$who discussed: ${chat.take(5).join('. ')}.';
    }
    return 'Meeting content was captured but could not be summarized.';
  }

  List<String> _extractLocalKeyPoints(List<Map<String, dynamic>> msgs) {
    return narrativeBulletsFromMeeting(msgs, maxItems: 5);
  }

  Future<Uint8List> _buildPdfBytes() {
    return buildMeetingSummaryPdf(
      roomName: widget.roomName,
      summaryText: _summaryText,
      decisions: _decisions,
      actions: _actions,
      durationLabel: _durationLabel,
      participantsCount: _participantsCount,
    );
  }

  Future<void> _exportPdf() async {
    if (_exportBusy) return;
    setState(() => _exportBusy = true);
    try {
      final bytes = await _buildPdfBytes();
      final filename = meetingSummaryPdfFilename(widget.roomName);
      await saveDownloadedBytes(
        filename: filename,
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded $filename')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  Future<void> _shareSummary() async {
    if (_exportBusy) return;
    setState(() => _exportBusy = true);
    try {
      final filename = meetingSummaryPdfFilename(widget.roomName);
      final bytes = await _buildPdfBytes();
      final shared = await shareDownloadedBytes(
        filename: filename,
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      if (shared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Summary shared')),
        );
      } else {
        await saveDownloadedBytes(
          filename: filename,
          bytes: bytes,
          mimeType: 'application/pdf',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Share unavailable on this device — PDF downloaded instead'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  void _createTasks() {
    final projectId = _linkedProjectId;
    if (!_canCreateTasks || projectId == null || projectId.isEmpty) return;
    Navigator.pushNamed(
      context,
      R.addTask,
      arguments: AddTaskRouteArgs(projectId: projectId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final participantsLabel = _participantsCount > 0
        ? '$_participantsCount ${_participantsCount == 1 ? 'participant' : 'participants'}'
        : 'Participants';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Meeting Summary',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _error = null;
                            });
                            _loadSummary();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    SummaryOverviewCard(
                      title: widget.roomName.isNotEmpty
                          ? widget.roomName
                          : 'Meeting',
                      participantsLabel: participantsLabel,
                      durationLabel: _durationLabel,
                    ),
                    const SummarySectionHeader(
                      icon: Icons.auto_awesome_rounded,
                      title: 'AI Summary',
                    ),
                    if (_summaryBullets.isEmpty)
                      const SummaryEmptyCard(
                        icon: Icons.summarize_outlined,
                        emoji: '✨',
                        message:
                            'No summary points were generated for this meeting.',
                      )
                    else
                      SummaryAiInsightsCard(bullets: _summaryBullets),
                    const SummarySectionHeader(
                      icon: Icons.gavel_rounded,
                      title: 'Decisions',
                    ),
                    if (_decisions.isEmpty)
                      const SummaryEmptyCard(
                        icon: Icons.rule_folder_outlined,
                        emoji: '📝',
                        message: 'No decisions identified',
                      )
                    else
                      ..._decisions.map(_decisionCard),
                    const SummarySectionHeader(
                      icon: Icons.checklist_rounded,
                      title: 'Action Items',
                    ),
                    if (_actions.isEmpty)
                      const SummaryEmptyCard(
                        icon: Icons.task_alt_outlined,
                        emoji: '☑️',
                        message: 'No action items identified',
                      )
                    else
                      ..._actions.map(
                        (a) => SummaryActionChecklistCard(
                          text: a['text']!,
                          owner: a['owner']!,
                          due: a['due']!,
                        ),
                      ),
                    if (_transcriptLines.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SummaryCollapsibleTranscript(
                        lines: _transcriptLines,
                        entryCount: _transcriptEntryCount,
                        expanded: _transcriptExpanded,
                        onToggle: () => setState(
                          () => _transcriptExpanded = !_transcriptExpanded,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SummaryActionsRow(
                      exportBusy: _exportBusy,
                      canCreateTasks: _canCreateTasks,
                      onExport: _exportPdf,
                      onShare: _shareSummary,
                      onCreateTasks: _createTasks,
                    ),
                  ],
                ),
    );
  }

  Widget _decisionCard(String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: MeetingUi.cardDecoration(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1, right: 10),
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 14, color: Colors.white),
            ),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

// ── Demo Mode Meeting Model & Screens ──────────────────────────────────────────
class DemoMeeting {
  final String id;
  final String title;
  final String projectName;
  final String dateTimeLabel;
  final DateTime scheduledAt;
  final String hostName;
  final String hostInitials;
  final int participantCount;
  final List<String> participantNames;
  final String status;
  final String description;

  DemoMeeting({
    required this.id,
    required this.title,
    required this.projectName,
    required this.dateTimeLabel,
    required this.scheduledAt,
    required this.hostName,
    required this.hostInitials,
    required this.participantCount,
    required this.participantNames,
    required this.status,
    this.description = '',
  });
}

final List<DemoMeeting> globalMockMeetings = [
  DemoMeeting(
    id: 'm1',
    title: 'Sprint Planning & Sync',
    projectName: 'Teamify Mobile App',
    dateTimeLabel: 'Today, 2:00 PM',
    scheduledAt: DateTime.now().add(const Duration(minutes: 10)),
    hostName: 'Alex Chen',
    hostInitials: 'AC',
    participantCount: 4,
    participantNames: [
      'Alex Chen',
      'Sarah Miller',
      'David Ross',
      'Emily Watson'
    ],
    status: 'Live',
    description:
        'Weekly team sprint alignment, backlog prioritization, and workload allocation.',
  ),
  DemoMeeting(
    id: 'm2',
    title: 'Frontend Architecture Review',
    projectName: 'AI Smart Engine',
    dateTimeLabel: 'Tomorrow, 10:30 AM',
    scheduledAt: DateTime.now().add(const Duration(days: 1, hours: 2)),
    hostName: 'Sarah Miller',
    hostInitials: 'SM',
    participantCount: 5,
    participantNames: [
      'Sarah Miller',
      'Alex Chen',
      'Michael Chang',
      'Jessica Wu'
    ],
    status: 'Upcoming',
    description:
        'Deep dive into state management, web worker optimization, and widget modularity.',
  ),
  DemoMeeting(
    id: 'm3',
    title: 'AI Feature Demo & Q&A',
    projectName: 'Teamify Mobile App',
    dateTimeLabel: 'Jul 31, 2026, 4:00 PM',
    scheduledAt: DateTime.now().add(const Duration(days: 2)),
    hostName: 'David Ross',
    hostInitials: 'DR',
    participantCount: 3,
    participantNames: ['David Ross', 'Emily Watson', 'Alex Chen'],
    status: 'Upcoming',
    description:
        'Live demonstration of automated transcription and summary extraction pipeline.',
  ),
  DemoMeeting(
    id: 'm4',
    title: 'Weekly Team Retrospective',
    projectName: 'Security Portal',
    dateTimeLabel: 'Jul 28, 2026, 11:00 AM',
    scheduledAt: DateTime.now().subtract(const Duration(days: 2)),
    hostName: 'Emily Watson',
    hostInitials: 'EW',
    participantCount: 6,
    participantNames: [
      'Emily Watson',
      'Sarah Miller',
      'David Ross',
      'Alex Chen'
    ],
    status: 'Ended',
    description:
        'Review of past sprint deliverables, friction points, and process improvements.',
  ),
];

class MeetingsListScreen extends StatefulWidget {
  const MeetingsListScreen({super.key});

  @override
  State<MeetingsListScreen> createState() => _MeetingsListScreenState();
}

class _MeetingsListScreenState extends State<MeetingsListScreen> {
  String _activeTab = 'All';

  List<DemoMeeting> get _filteredMeetings {
    if (_activeTab == 'Upcoming') {
      return globalMockMeetings
          .where((m) => m.status == 'Upcoming' || m.status == 'Live')
          .toList();
    } else if (_activeTab == 'Ended') {
      return globalMockMeetings.where((m) => m.status == 'Ended').toList();
    }
    return globalMockMeetings;
  }

  void _openCreateMeeting() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateMeetingScreen(
          onCreated: (newMeeting) {
            setState(() {
              globalMockMeetings.insert(0, newMeeting);
            });
          },
        ),
      ),
    );
  }

  void _joinMeeting(DemoMeeting meeting) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PermissionsPreviewSheet(meeting: meeting),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Smart Meetings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_call),
            onPressed: _openCreateMeeting,
            tooltip: 'Schedule Meeting',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _tabChip('All'),
                  const SizedBox(width: 8),
                  _tabChip('Upcoming'),
                  const SizedBox(width: 8),
                  _tabChip('Ended'),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _filteredMeetings.length,
                itemBuilder: (context, index) {
                  final m = _filteredMeetings[index];
                  return _meetingCard(m);
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateMeeting,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.video_call, color: Colors.white),
        label: const Text(
          'Create Meeting',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      bottomNavigationBar: TBottomNav(
        current: 0,
        onTap: (i) => handleRoleNav(context, i),
      ),
    );
  }

  Widget _tabChip(String label) {
    final sel = _activeTab == label;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.white : AppColors.textPrimary,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _meetingCard(DemoMeeting m) {
    final isLive = m.status == 'Live';
    final isUpcoming = m.status == 'Upcoming';

    Color statusBg;
    Color statusFg;
    if (isLive) {
      statusBg = AppColors.success.withValues(alpha: 0.15);
      statusFg = AppColors.success;
    } else if (isUpcoming) {
      statusBg = AppColors.primary.withValues(alpha: 0.15);
      statusFg = AppColors.primary;
    } else {
      statusBg = AppColors.border;
      statusFg = AppColors.textSecondary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  m.projectName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
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
                      const SizedBox(width: 6),
                    ],
                    Text(
                      m.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusFg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            m.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.schedule,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                m.dateTimeLabel,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const Spacer(),
              const Icon(Icons.person_outline,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Host: ${m.hostName}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          if (m.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              m.description,
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Row(
                children: m.participantNames.take(3).map((name) {
                  final init = name.split(' ').map((e) => e[0]).take(2).join();
                  return Container(
                    margin: const EdgeInsets.only(right: 4),
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      child: Text(
                        init,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(width: 6),
              Text(
                '${m.participantCount} members',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const Spacer(),
              if (isLive || isUpcoming)
                ElevatedButton.icon(
                  onPressed: () => _joinMeeting(m),
                  icon: const Icon(Icons.video_call, size: 16),
                  label: Text(isLive ? 'Join Live Now' : 'Join Call'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isLive ? AppColors.success : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MeetingSummaryScreen(
                          roomId: m.id,
                          roomName: m.title,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('View Summary'),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CreateMeetingScreen extends StatefulWidget {
  final ValueChanged<DemoMeeting> onCreated;
  const CreateMeetingScreen({super.key, required this.onCreated});

  @override
  State<CreateMeetingScreen> createState() => _CreateMeetingScreenState();
}

class _CreateMeetingScreenState extends State<CreateMeetingScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedProject = 'Teamify Mobile App';
  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _selectedTime =
      TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 2)));
  String _duration = '30 minutes';
  final List<String> _selectedParticipants = ['Alex Chen', 'Sarah Miller'];

  final List<String> _availableProjects = [
    'Teamify Mobile App',
    'AI Smart Engine',
    'Security Portal',
    'General Sync',
  ];

  final List<String> _availableUsers = [
    'Alex Chen',
    'Sarah Miller',
    'David Ross',
    'Emily Watson',
    'Michael Chang',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meeting title is required')),
      );
      return;
    }

    final scheduled = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    if (scheduled
        .isBefore(DateTime.now().subtract(const Duration(minutes: 5)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Meeting cannot be scheduled in the past')),
      );
      return;
    }

    if (_selectedParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one participant is required')),
      );
      return;
    }

    final newMeeting = DemoMeeting(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      projectName: _selectedProject,
      dateTimeLabel:
          '${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year} at ${_selectedTime.format(context)}',
      scheduledAt: scheduled,
      hostName: 'Alex Chen',
      hostInitials: 'AC',
      participantCount: _selectedParticipants.length,
      participantNames: _selectedParticipants,
      status: 'Upcoming',
      description: _descriptionController.text.trim(),
    );

    widget.onCreated(newMeeting);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Meeting created successfully!'),
        backgroundColor: AppColors.success,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Schedule Meeting',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Meeting Title *',
                hintText: 'e.g. Sprint Architecture Sync',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedProject,
              decoration: const InputDecoration(
                labelText: 'Related Project',
                border: OutlineInputBorder(),
              ),
              items: _availableProjects
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedProject = v!),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date', style: TextStyle(fontSize: 12)),
                    subtitle: Text(
                      '${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null)
                        setState(() => _selectedDate = picked);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Time', style: TextStyle(fontSize: 12)),
                    subtitle: Text(
                      _selectedTime.format(context),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null) {
                        setState(() => _selectedTime = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _duration,
              decoration: const InputDecoration(
                labelText: 'Duration',
                border: OutlineInputBorder(),
              ),
              items: ['15 minutes', '30 minutes', '45 minutes', '60 minutes']
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => setState(() => _duration = v!),
            ),
            const SizedBox(height: 16),
            const Text(
              'Participants *',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableUsers.map((user) {
                final sel = _selectedParticipants.contains(user);
                return FilterChip(
                  label: Text(user),
                  selected: sel,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedParticipants.add(user);
                      } else {
                        _selectedParticipants.remove(user);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Meeting Description (Optional)',
                hintText: 'Agenda topics, links, or notes...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Schedule Meeting',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionsPreviewSheet extends StatefulWidget {
  final DemoMeeting meeting;
  const PermissionsPreviewSheet({super.key, required this.meeting});

  @override
  State<PermissionsPreviewSheet> createState() =>
      _PermissionsPreviewSheetState();
}

class _PermissionsPreviewSheetState extends State<PermissionsPreviewSheet> {
  bool _micOn = true;
  bool _cameraOn = true;

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
          Text(
            widget.meeting.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Host: ${widget.meeting.hostName} · ${widget.meeting.projectName}',
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Center(
                  child: _cameraOn
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: AppColors.primary,
                              child: Text(
                                widget.meeting.hostInitials,
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Camera Preview Active',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_off,
                                color: Colors.white54, size: 48),
                            SizedBox(height: 8),
                            Text('Camera is turned off',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _micOn ? Icons.mic : Icons.mic_off,
                          color: _micOn ? AppColors.success : Colors.red,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _micOn ? 'Microphone Ready' : 'Muted',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setState(() => _micOn = !_micOn),
                icon: Icon(_micOn ? Icons.mic : Icons.mic_off),
                color: _micOn ? AppColors.primary : Colors.red,
                iconSize: 28,
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed: () => setState(() => _cameraOn = !_cameraOn),
                icon: Icon(_cameraOn ? Icons.videocam : Icons.videocam_off),
                color: _cameraOn ? AppColors.primary : Colors.red,
                iconSize: 28,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MeetingScreen(),
                    settings: RouteSettings(
                      arguments: {
                        'roomId': widget.meeting.id,
                        'roomName': widget.meeting.title,
                        'projectId': 'demo_project_1',
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.video_call, size: 20),
              label: const Text('Join Call Now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
