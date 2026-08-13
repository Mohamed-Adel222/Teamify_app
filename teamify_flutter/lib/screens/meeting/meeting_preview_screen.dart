import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../core/observability/app_logger.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme.dart';
import '../../data/models/api_meeting.dart';
import '../../services/app_services.dart';
import 'live_meeting_screen.dart';

/// Camera/microphone preview before connecting to LiveKit.
class MeetingPreviewScreen extends StatefulWidget {
  final String publicId;

  const MeetingPreviewScreen({super.key, required this.publicId});

  @override
  State<MeetingPreviewScreen> createState() => _MeetingPreviewScreenState();
}

class _MeetingPreviewScreenState extends State<MeetingPreviewScreen> {
  ApiMeeting? _meeting;
  String? _error;
  bool _loading = true;
  bool _joining = false;
  bool _micOn = true;
  bool _cameraOn = true;
  String? _cameraError;
  LocalVideoTrack? _previewTrack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  Future<void> _stopPreview() async {
    final track = _previewTrack;
    _previewTrack = null;
    if (track == null) return;
    try {
      await track.stop();
    } catch (_) {}
    try {
      await track.dispose();
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result =
        await context.read<AppServices>().meetings.getMeeting(widget.publicId);
    if (!mounted) return;
    if (!result.isSuccess || result.data == null) {
      setState(() {
        _loading = false;
        _error = result.error ?? 'Meeting not found';
      });
      return;
    }
    setState(() {
      _meeting = result.data;
      _loading = false;
    });
    await _startCameraPreview();
  }

  Future<void> _startCameraPreview() async {
    if (!_cameraOn) return;
    await _stopPreview();
    try {
      final track = await LocalVideoTrack.createCameraTrack(
        const CameraCaptureOptions(
          cameraPosition: CameraPosition.front,
        ),
      );
      if (!mounted) {
        await track.stop();
        await track.dispose();
        return;
      }
      setState(() {
        _previewTrack = track;
        _cameraError = null;
      });
    } catch (e, st) {
      AppLogger.error('Camera preview failed', e, st);
      if (!mounted) return;
      setState(() {
        _cameraError =
            'Camera is blocked or unavailable. Allow camera access, then try again.';
        _previewTrack = null;
      });
    }
  }

  Future<void> _toggleCamera() async {
    final next = !_cameraOn;
    setState(() => _cameraOn = next);
    if (next) {
      await _startCameraPreview();
    } else {
      await _stopPreview();
      if (mounted) setState(() {});
    }
  }

  Future<void> _join() async {
    final meeting = _meeting;
    if (meeting == null || _joining) return;
    if (meeting.isEnded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This meeting has ended.')),
      );
      return;
    }
    setState(() => _joining = true);
    await _stopPreview();
    final tokenResult =
        await context.read<AppServices>().meetings.issueToken(widget.publicId);
    if (!mounted) return;
    if (!tokenResult.isSuccess || tokenResult.data == null) {
      setState(() => _joining = false);
      final msg = tokenResult.statusCode == 503
          ? 'LiveKit is not configured on the server. Video meetings are unavailable.'
          : (tokenResult.error ?? 'Could not join meeting');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (_cameraOn) await _startCameraPreview();
      return;
    }
    final token = tokenResult.data!;
    if (token.url.isEmpty || token.token.isEmpty) {
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'LiveKit is not configured on the server. Video meetings are unavailable.',
          ),
        ),
      );
      if (_cameraOn) await _startCameraPreview();
      return;
    }

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMeetingScreen(
          publicId: widget.publicId,
          meeting: token.meeting ?? meeting,
          joinToken: token,
          cameraEnabled: _cameraOn,
          microphoneEnabled: _micOn,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final me = session.currentUser;
    final name = me?.fullName ?? me?.displayName ?? 'You';
    final initials = _initials(name);
    final meeting = _meeting;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text(meeting?.title ?? 'Join meeting'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(message: _error!, onRetry: _load)
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              color: const Color(0xFF111827),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_cameraOn && _previewTrack != null)
                                    VideoTrackRenderer(_previewTrack!)
                                  else
                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 40,
                                            backgroundColor: AppColors.primary,
                                            child: Text(
                                              initials,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            _cameraOn
                                                ? (_cameraError ??
                                                    'Starting camera…')
                                                : 'Camera is off',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Positioned(
                                    left: 12,
                                    bottom: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (meeting != null)
                          Text(
                            [
                              if (meeting.hostName.isNotEmpty)
                                'Host: ${meeting.hostName}',
                              if ((meeting.projectName ?? '').isNotEmpty)
                                meeting.projectName!,
                            ].join(' · '),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _RoundToggle(
                              enabled: _micOn,
                              iconOn: Icons.mic,
                              iconOff: Icons.mic_off,
                              onTap: () => setState(() => _micOn = !_micOn),
                            ),
                            const SizedBox(width: 20),
                            _RoundToggle(
                              enabled: _cameraOn,
                              iconOn: Icons.videocam,
                              iconOff: Icons.videocam_off,
                              onTap: _toggleCamera,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _joining ? null : _join,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              _joining ? 'Joining…' : 'Join',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  String _initials(String name) {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Y';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _RoundToggle extends StatelessWidget {
  final bool enabled;
  final IconData iconOn;
  final IconData iconOff;
  final VoidCallback onTap;

  const _RoundToggle({
    required this.enabled,
    required this.iconOn,
    required this.iconOff,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: 28,
        backgroundColor: enabled ? Colors.white12 : const Color(0xFFB91C1C),
        child: Icon(
          enabled ? iconOn : iconOff,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
