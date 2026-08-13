import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/observability/app_logger.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

// ── Complete Profile ──────────────────────────────────────────────────────────
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final List<String> _selectedRoles = ['Freelance Designer'];
  final List<String> _selectedAvailability = ['Full-time'];

  final List<String> _roles = [
    'UI/UX Designer',
    'Product Designer',
    'Freelance Designer',
    'Mobile App Designer',
    'Flutter Developer',
    'Frontend Developer',
    'Graphic Designer',
    'Team Lead',
    'Mentor',
    'Remote Designer'
  ];

  final List<String> _availability = [
    'Full-time',
    'Part-time',
    'Freelance',
    'Remote',
    'Hybrid',
    'Available Now',
    'Open to Opportunities'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Complete Profile'),
        leading:
            const Padding(padding: EdgeInsets.all(12), child: TBackButton()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TBar(value: 0.6, height: 8),
            const SizedBox(height: 8),
            const Text('60% Complete',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            const SizedBox(height: 32),
            Center(
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 2),
                        shape: BoxShape.circle),
                    child: const TAvatar(initials: 'MK', radius: 48),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 4)
                          ]),
                      child:
                          const Icon(Icons.edit, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const TSectionHeader(title: 'Professional Bio'),
            const SizedBox(height: 12),
            _inputField('Full Name', 'Mariam Kamel'),
            _inputField('Bio',
                'Passionate UI/UX Designer looking for innovative projects.'),
            const SizedBox(height: 24),
            const TSectionHeader(title: 'Skills & Expertise'),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TChip(label: 'Product Design'),
                TChip(label: 'Flutter'),
                TChip(label: 'Figma'),
                TChip(label: '+ Add Skill', bg: Colors.transparent),
              ],
            ),
            const SizedBox(height: 32),
            const TSectionHeader(title: 'Preferences'),
            const SizedBox(height: 20),
            const Text('Preferred Role',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: _roles.map((role) {
                final isSelected = _selectedRoles.contains(role);
                return FilterChip(
                  label: Text(role),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedRoles.add(role);
                      } else {
                        _selectedRoles.remove(role);
                      }
                    });
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color:
                            isSelected ? AppColors.primary : AppColors.border),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Text('Availability',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: _availability.map((a) {
                final isSelected = _selectedAvailability.contains(a);
                return FilterChip(
                  label: Text(a),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedAvailability.add(a);
                      } else {
                        _selectedAvailability.remove(a);
                      }
                    });
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color:
                            isSelected ? AppColors.primary : AppColors.border),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 48),
            TButton(
                label: 'Save & Continue', onTap: () => Navigator.pop(context)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _inputField(String label, String val) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: SizedBox(width: double.infinity, child: Text(val))),
          ],
        ),
      );
}

class _ComingSoonFeatureBody extends StatelessWidget {
  final String message;
  const _ComingSoonFeatureBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text(
              'Coming Soon',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── AI Teammate Matching ──────────────────────────────────────────────────────
class AITeammateMatchingScreen extends StatelessWidget {
  const AITeammateMatchingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Talent Matching')),
      body: const _ComingSoonFeatureBody(
        message:
            'AI talent matching is not available yet. Use Team Recommendation from the AI Hub.',
      ),
    );
  }
}

// ── Project Risk Predictor ────────────────────────────────────────────────────
class ProjectRiskPredictorScreen extends StatelessWidget {
  const ProjectRiskPredictorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Risk Analysis')),
      body: const _ComingSoonFeatureBody(
        message:
            'Project risk prediction is not available yet. Use AI Insights for delay risk analysis.',
      ),
    );
  }
}

// ── Chat Emotion Detection ────────────────────────────────────────────────────
class ChatEmotionScreen extends StatelessWidget {
  const ChatEmotionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Project Chat')),
      body: const _ComingSoonFeatureBody(
        message:
            'Chat emotion detection is not available yet. Backend support is required before this feature can launch.',
      ),
    );
  }
}

// ── Meeting Transcription ─────────────────────────────────────────────────────
class MeetingTranscriptionScreen extends StatefulWidget {
  const MeetingTranscriptionScreen({super.key});

  @override
  State<MeetingTranscriptionScreen> createState() =>
      _MeetingTranscriptionScreenState();
}

class _MeetingTranscriptionScreenState
    extends State<MeetingTranscriptionScreen> {
  bool _loading = true;
  String? _error;
  String _title = 'Meeting Intelligence';
  String _meta = '';
  String _summary = '';
  List<String> _actions = [];
  String _transcript = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    String? publicId;
    String? roomId;
    String? sessionId;
    if (args is String) publicId = args;
    if (args is Map) {
      publicId = args['publicId']?.toString() ?? args['public_id']?.toString();
      roomId = args['roomId']?.toString();
      sessionId = args['sessionId']?.toString();
    }
    if ((publicId == null || publicId.isEmpty) &&
        (roomId == null || roomId.isEmpty)) {
      setState(() {
        _loading = false;
        _error =
            'Open a meeting from history or a chat to see its transcript and AI summary.';
      });
      return;
    }
    try {
      if (publicId != null && publicId.isNotEmpty) {
        final meeting = await context
            .read<AppServices>()
            .meetings
            .getMeeting(publicId)
            .unwrap();
        if (!mounted) return;
        _applyMeeting(meeting.title, meeting.session);
      } else if (roomId != null && sessionId != null && sessionId.isNotEmpty) {
        final session = await context
            .read<AppServices>()
            .chat
            .getMeetingSession(roomId, sessionId)
            .unwrap();
        if (!mounted) return;
        _applyMeeting('Meeting notes', session);
      } else {
        setState(() {
          _loading = false;
          _error = 'This meeting does not have a saved transcript yet.';
        });
        return;
      }
    } catch (e, st) {
      AppLogger.error('Failed to load meeting intelligence', e, st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load meeting notes.';
      });
    }
  }

  void _applyMeeting(String title, Map<String, dynamic>? session) {
    final summary = session?['summary']?.toString() ??
        (session?['ai_summary'] is Map
            ? (session!['ai_summary']['summary']?.toString() ?? '')
            : '');
    final actionsRaw = session?['action_items'];
    final actions = <String>[];
    if (actionsRaw is List) {
      for (final item in actionsRaw) {
        if (item is String && item.trim().isNotEmpty) {
          actions.add(item.trim());
        } else if (item is Map) {
          final t = item['title']?.toString() ?? item['text']?.toString() ?? '';
          if (t.isNotEmpty) actions.add(t);
        }
      }
    }
    final lines = <String>[];
    final transcript = session?['transcript'] ?? session?['speech_transcript'];
    if (transcript is List) {
      for (final row in transcript) {
        if (row is Map) {
          final name = row['sender_name']?.toString() ?? 'Speaker';
          final content = row['content']?.toString() ?? '';
          if (content.isNotEmpty) lines.add('$name: $content');
        }
      }
    }
    setState(() {
      _loading = false;
      _error = null;
      _title = title;
      _meta = session?['started_at']?.toString() ?? '';
      _summary = summary;
      _actions = actions;
      _transcript = lines.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Meeting Intelligence')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TCard(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            const Icon(Icons.mic, color: AppColors.error),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  if (_meta.isNotEmpty)
                                    Text(_meta,
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const TSectionHeader(title: 'Meeting Summary'),
                      const SizedBox(height: 16),
                      TCard(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _summary.isEmpty
                              ? 'No AI summary is available for this meeting yet.'
                              : _summary,
                          style: const TextStyle(height: 1.5, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const TSectionHeader(title: 'Action Items'),
                      const SizedBox(height: 16),
                      if (_actions.isEmpty)
                        const TCard(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No action items were extracted.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ..._actions.map(_taskItem),
                      const SizedBox(height: 32),
                      const TSectionHeader(title: 'Transcript'),
                      const SizedBox(height: 16),
                      TCard(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _transcript.isEmpty
                              ? 'No transcript was saved for this meeting.'
                              : _transcript,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.8),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _taskItem(String t) => TCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          const Icon(Icons.circle_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(t, style: const TextStyle(fontSize: 14)),
          ),
        ]),
      );
}

// ── File Version History ──────────────────────────────────────────────────────
class FileVersionHistoryScreen extends StatelessWidget {
  const FileVersionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Security & History')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: AppColors.primaryDark,
            child: const Row(
              children: [
                Icon(Icons.cloud_done_outlined,
                    color: AppColors.success, size: 32),
                SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Cloud Backup Active',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      Text('Automatic versioning is enabled.',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ])),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: 4,
              itemBuilder: (context, i) {
                return _versionTile(4 - i, i == 0);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: TButton(
                label: 'Verify Integrity', icon: Icons.security, onTap: () {}),
          ),
        ],
      ),
    );
  }

  Widget _versionTile(int v, bool current) => TCard(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.insert_drive_file_outlined,
                    color: AppColors.primary)),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Text('Version $v.0',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    if (current) ...[
                      const SizedBox(width: 8),
                      const TChip(
                          label: 'LATEST',
                          bg: AppColors.success,
                          textColor: Colors.white,
                          fontSize: 9)
                    ],
                  ]),
                  const Text('May 07 • 02:45 PM',
                      style:
                          TextStyle(color: AppColors.textHint, fontSize: 12)),
                ])),
            TextButton(
                onPressed: () {},
                child: const Text('Restore',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      );
}
