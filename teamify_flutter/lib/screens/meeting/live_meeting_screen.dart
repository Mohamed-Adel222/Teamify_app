import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../core/audio/meeting_speech_pipeline.dart';
import '../../core/network/api_result.dart';
import '../../core/observability/app_logger.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme.dart';
import '../../data/models/api_meeting.dart';
import '../../services/app_services.dart';
import 'meeting_screens.dart';

class LiveMeetingScreen extends StatefulWidget {
  final String publicId;
  final ApiMeeting meeting;
  final MeetingJoinToken joinToken;
  final bool cameraEnabled;
  final bool microphoneEnabled;

  const LiveMeetingScreen({
    super.key,
    required this.publicId,
    required this.meeting,
    required this.joinToken,
    this.cameraEnabled = true,
    this.microphoneEnabled = true,
  });

  @override
  State<LiveMeetingScreen> createState() => _LiveMeetingScreenState();
}

class _LiveMeetingScreenState extends State<LiveMeetingScreen> {
  final Room _room = Room(
    roomOptions: const RoomOptions(
      adaptiveStream: true,
      dynacast: true,
    ),
  );
  final MeetingSpeechPipeline _speech = MeetingSpeechPipeline();
  EventsListener<RoomEvent>? _listener;

  bool _connecting = true;
  String? _connectError;
  bool _micOn = true;
  bool _camOn = true;
  bool _showParticipants = false;
  bool _ending = false;
  bool _speechUnavailable = false;
  bool _didConnect = false;
  String _connectionLabel = 'Connecting';
  String? _sessionId;
  DateTime? _startedAt;
  final List<Map<String, dynamic>> _transcript = [];
  bool _disposed = false;

  String get _myId =>
      context.read<SessionController>().currentUser?.id ??
      widget.joinToken.identity;

  bool get _isHost => widget.meeting.hostUserId == _myId;

  @override
  void initState() {
    super.initState();
    _micOn = widget.microphoneEnabled;
    _camOn = widget.cameraEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_speech.shutdown());
    unawaited(_teardownRoom());
    super.dispose();
  }

  Future<void> _teardownRoom() async {
    try {
      await _listener?.dispose();
    } catch (_) {}
    _listener = null;
    try {
      await _room.disconnect();
    } catch (_) {}
    try {
      await _room.dispose();
    } catch (_) {}
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _connectError = null;
      _connectionLabel = 'Connecting';
    });
    try {
      _listener = _room.createListener();
      _listener!
        ..on<RoomConnectedEvent>((_) {
          if (!mounted || _disposed) return;
          _didConnect = true;
          setState(() {
            _connecting = false;
            _connectionLabel = 'Connected';
          });
        })
        ..on<RoomReconnectingEvent>((_) {
          if (!mounted || _disposed) return;
          setState(() => _connectionLabel = 'Reconnecting');
        })
        ..on<RoomReconnectedEvent>((_) {
          if (!mounted || _disposed) return;
          setState(() => _connectionLabel = 'Connected');
        })
        ..on<RoomDisconnectedEvent>((event) {
          if (!mounted || _disposed) return;
          setState(() => _connectionLabel = 'Disconnected');
          if (_didConnect && !_ending) {
            unawaited(_handleRemoteDisconnect());
          }
        })
        ..on<ParticipantConnectedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackSubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackUnsubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackMutedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackUnmutedEvent>((_) {
          if (mounted) setState(() {});
        });

      _room.addListener(_onRoomChanged);
      await _room.connect(
        widget.joinToken.url,
        widget.joinToken.token,
      );
      _didConnect = true;
      await _publishLocalTracks();
      _startedAt = DateTime.now();
      await _startSessionAndSpeech();
      if (mounted && !_disposed) {
        setState(() {
          _connecting = false;
          _connectionLabel = 'Connected';
        });
      }
    } catch (e, st) {
      AppLogger.error('LiveKit connect failed', e, st);
      if (!mounted || _disposed) return;
      setState(() {
        _connecting = false;
        _connectError =
            'Could not connect to the meeting. Check camera/microphone permissions and try again.';
        _connectionLabel = 'Disconnected';
      });
    }
  }

  Future<void> _publishLocalTracks() async {
    if (_camOn) {
      try {
        await _room.localParticipant?.setCameraEnabled(true);
      } catch (e, st) {
        AppLogger.error('Camera publish failed', e, st);
        _camOn = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Camera is blocked or unavailable. You are in the meeting without video.',
              ),
            ),
          );
        }
      }
    }
    if (_micOn) {
      try {
        await _room.localParticipant?.setMicrophoneEnabled(true);
      } catch (e, st) {
        AppLogger.error('Microphone publish failed', e, st);
        _micOn = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Microphone is blocked or unavailable. You are in the meeting without audio.',
              ),
            ),
          );
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _handleRemoteDisconnect() async {
    if (_ending || !_didConnect || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The meeting has ended or you were disconnected.')),
    );
    await _leave(endForAll: false);
  }

  void _onRoomChanged() {
    if (mounted && !_disposed) setState(() {});
  }

  Future<void> _startSessionAndSpeech() async {
    final roomId = widget.meeting.chatRoomId;
    if (roomId.isEmpty) return;
    final services = context.read<AppServices>();
    try {
      final session =
          await services.chat.startMeetingSession(roomId).unwrap();
      _sessionId = session['id']?.toString();
    } catch (e, st) {
      AppLogger.error('Meeting session start failed', e, st);
    }

    final started = await _speech.start(
      onLiveText: (text, isFinal) {
        if (!isFinal || text.trim().isEmpty || !mounted) return;
        final me = context.read<SessionController>().currentUser;
        setState(() {
          _transcript.add({
            'sender_name': me?.fullName ?? me?.displayName ?? 'You',
            'content': text.trim(),
            'created_at': DateTime.now().toIso8601String(),
          });
        });
      },
      transcribeFallback: (bytes, filename) async {
        final result = await services.ai.transcribe(
          bytes,
          filename: filename,
        );
        if (!result.isSuccess) {
          if (mounted) {
            setState(() => _speechUnavailable = true);
          }
          return null;
        }
        return result.data?.text;
      },
      onError: (message) {
        AppLogger.error('Meeting speech: $message');
        if (message.toLowerCase().contains('not-allowed') ||
            message.toLowerCase().contains('unavailable')) {
          if (mounted) setState(() => _speechUnavailable = true);
        }
      },
      shouldRun: () => !_disposed && _micOn,
    );
    if (mounted && !started) {
      setState(() => _speechUnavailable = true);
    }
  }

  Future<void> _toggleMic() async {
    final next = !_micOn;
    try {
      await _room.localParticipant?.setMicrophoneEnabled(next);
      if (mounted) setState(() => _micOn = next);
    } catch (e, st) {
      AppLogger.error('Microphone toggle failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not change microphone. Check browser permissions.'),
        ),
      );
    }
  }

  Future<void> _toggleCam() async {
    final next = !_camOn;
    try {
      await _room.localParticipant?.setCameraEnabled(next);
      if (mounted) setState(() => _camOn = next);
    } catch (e, st) {
      AppLogger.error('Camera toggle failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not change camera. Check browser permissions.'),
        ),
      );
    }
  }

  Future<void> _leave({required bool endForAll}) async {
    if (_ending) return;
    final meetings = context.read<AppServices>().meetings;
    final chat = context.read<AppServices>().chat;
    setState(() => _ending = true);
    await _speech.shutdown();
    try {
      if (endForAll) {
        await meetings.end(widget.publicId);
      } else {
        await meetings.leave(widget.publicId);
      }
    } catch (e, st) {
      AppLogger.error('Meeting leave/end failed', e, st);
    }

    final sessionId = _sessionId;
    Map<String, dynamic>? endedSession;
    if (endForAll && sessionId != null && sessionId.isNotEmpty) {
      try {
        endedSession = await chat
            .stopMeetingSession(
              widget.meeting.chatRoomId,
              sessionId,
              transcript: _transcript,
              participantIds: _participantIds(),
            )
            .unwrap();
      } catch (e, st) {
        AppLogger.error('Stop meeting session failed', e, st);
      }
    }

    await _teardownRoom();
    if (!mounted) return;

    if (endForAll) {
      final elapsed = _startedAt == null
          ? null
          : DateTime.now().difference(_startedAt!).inSeconds;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingSummaryScreen(
            roomName: widget.meeting.title,
            roomId: widget.meeting.chatRoomId,
            sessionId: sessionId,
            projectId: widget.meeting.projectId,
            inlineTranscript: _transcript,
            sessionStartedAt: _startedAt,
            sessionDurationSeconds: elapsed,
            initialSession: endedSession,
          ),
        ),
      );
      return;
    }
    Navigator.pop(context);
  }

  List<String> _participantIds() {
    final ids = <String>{};
    final local = _room.localParticipant?.identity;
    if (local != null && local.isNotEmpty) ids.add(local);
    for (final p in _room.remoteParticipants.values) {
      if (p.identity.isNotEmpty) ids.add(p.identity);
    }
    return ids.toList();
  }

  List<Participant> _participants() {
    final list = <Participant>[];
    final local = _room.localParticipant;
    if (local != null) list.add(local);
    list.addAll(_room.remoteParticipants.values);
    return list;
  }

  int _crossAxisCount(int n) {
    if (n <= 1) return 1;
    if (n <= 4) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final participants = _participants();
    final count = participants.length;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: widget.meeting.title,
              status: _connectionLabel,
              count: count,
              speechUnavailable: _speechUnavailable,
            ),
            Expanded(
              child: _connecting
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _connectError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _connectError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      : _ParticipantGrid(
                          participants: participants,
                          crossAxisCount: _crossAxisCount(count),
                          localIdentity: _room.localParticipant?.identity,
                        ),
            ),
            if (_showParticipants) _ParticipantSheet(participants: participants),
            _Controls(
              micOn: _micOn,
              camOn: _camOn,
              isHost: _isHost,
              ending: _ending,
              onMic: _toggleMic,
              onCam: _toggleCam,
              onParticipants: () =>
                  setState(() => _showParticipants = !_showParticipants),
              onLeave: () => _leave(endForAll: false),
              onEnd: _isHost ? () => _leave(endForAll: true) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String status;
  final int count;
  final bool speechUnavailable;

  const _Header({
    required this.title,
    required this.status,
    required this.count,
    required this.speechUnavailable,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.people_alt_outlined,
                  color: Colors.white70, size: 18),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: status == 'Connected'
                      ? AppColors.success
                      : status == 'Reconnecting'
                          ? Colors.orange
                          : Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(status,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (speechUnavailable) ...[
                const SizedBox(width: 12),
                const Text(
                  'Whisper unavailable — using browser captions when possible',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ParticipantGrid extends StatelessWidget {
  final List<Participant> participants;
  final int crossAxisCount;
  final String? localIdentity;

  const _ParticipantGrid({
    required this.participants,
    required this.crossAxisCount,
    required this.localIdentity,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const Center(
        child: Text('Waiting for participants…',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 4 / 3,
      ),
      itemCount: participants.length,
      itemBuilder: (_, i) => _ParticipantTile(
        participant: participants[i],
        isLocal: participants[i].identity == localIdentity,
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final bool isLocal;

  const _ParticipantTile({
    required this.participant,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    VideoTrack? video;
    for (final pub in participant.videoTrackPublications) {
      final track = pub.track;
      if (track is VideoTrack && !pub.muted) {
        video = track;
        break;
      }
    }
    final micMuted = !participant.isMicrophoneEnabled();
    final name = participant.name.isNotEmpty
        ? participant.name
        : (isLocal ? 'You' : participant.identity);
    final connecting = participant.connectionQuality == ConnectionQuality.lost;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: const Color(0xFF111827),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video != null)
              VideoTrackRenderer(video)
            else
              Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    _initials(name),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (connecting)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const Text('Reconnecting…',
                    style: TextStyle(color: Colors.white70)),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              right: 8,
              child: Row(
                children: [
                  if (micMuted)
                    const Icon(Icons.mic_off, color: Colors.redAccent, size: 14),
                  if (micMuted) const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isLocal ? '$name (You)' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _ParticipantSheet extends StatelessWidget {
  final List<Participant> participants;

  const _ParticipantSheet({required this.participants});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      color: const Color(0xFF0F172A),
      child: ListView.builder(
        itemCount: participants.length,
        itemBuilder: (_, i) {
          final p = participants[i];
          final name = p.name.isNotEmpty ? p.name : p.identity;
          return ListTile(
            dense: true,
            leading: Icon(
              p.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
              color: Colors.white70,
            ),
            title: Text(name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              p.isCameraEnabled() ? 'Camera on' : 'Camera off',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool micOn;
  final bool camOn;
  final bool isHost;
  final bool ending;
  final VoidCallback onMic;
  final VoidCallback onCam;
  final VoidCallback onParticipants;
  final VoidCallback onLeave;
  final VoidCallback? onEnd;

  const _Controls({
    required this.micOn,
    required this.camOn,
    required this.isHost,
    required this.ending,
    required this.onMic,
    required this.onCam,
    required this.onParticipants,
    required this.onLeave,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ctl(micOn ? Icons.mic : Icons.mic_off, onMic,
              bg: micOn ? Colors.white12 : const Color(0xFFB91C1C)),
          _ctl(camOn ? Icons.videocam : Icons.videocam_off, onCam,
              bg: camOn ? Colors.white12 : const Color(0xFFB91C1C)),
          _ctl(Icons.people_alt_outlined, onParticipants),
          _ctl(Icons.call_end, ending ? null : onLeave,
              bg: const Color(0xFFB91C1C)),
          if (isHost)
            _ctl(Icons.stop_circle_outlined, ending ? null : onEnd,
                bg: const Color(0xFF7F1D1D)),
        ],
      ),
    );
  }

  Widget _ctl(IconData icon, VoidCallback? onTap, {Color bg = Colors.white12}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: 26,
        backgroundColor: bg,
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
