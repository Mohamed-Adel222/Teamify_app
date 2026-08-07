import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/widgets.dart';

/// Shared visual language for Meeting + Meeting Summary screens.
abstract final class MeetingUi {
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;

  static BoxDecoration cardDecoration({Color? fill}) => BoxDecoration(
        color: fill ?? Colors.white,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );
}

enum MeetingTranscriptPhase { idle, recording, processing, saving }

enum ParticipantPresence { inMeeting, notJoined, offline }

/// Parsed chat / speech line for live notes bubbles.
class MeetingNoteLine {
  final String speaker;
  final String text;
  final bool isSpeech;

  const MeetingNoteLine({
    required this.speaker,
    required this.text,
    this.isSpeech = false,
  });

  static MeetingNoteLine? parse(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return null;
    if (line.startsWith('[Speech] ')) {
      final rest = line.substring(9);
      final i = rest.indexOf(': ');
      if (i > 0) {
        return MeetingNoteLine(
          speaker: rest.substring(0, i),
          text: rest.substring(i + 2),
          isSpeech: true,
        );
      }
    }
    final i = line.indexOf(': ');
    if (i > 0) {
      return MeetingNoteLine(
        speaker: line.substring(0, i),
        text: line.substring(i + 2),
      );
    }
    return MeetingNoteLine(speaker: 'Note', text: line);
  }
}

class MeetingRoomPicker extends StatelessWidget {
  const MeetingRoomPicker({
    super.key,
    required this.roomId,
    required this.rooms,
    required this.enabled,
    required this.onChanged,
  });

  final String? roomId;
  final List<Map<String, dynamic>> rooms;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: MeetingUi.cardDecoration(fill: Colors.white),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: DropdownButtonFormField<String>(
        key: ValueKey(roomId),
        initialValue: roomId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Chat room',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        items: rooms
            .map(
              (r) => DropdownMenuItem(
                value: r['id']?.toString(),
                child: Text(
                  r['name']?.toString() ?? 'Room ${r['id']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class MeetingInfoHeader extends StatelessWidget {
  const MeetingInfoHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isLive,
  });

  final String title;
  final String subtitle;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MeetingUi.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.75),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(MeetingUi.radiusSm),
            ),
            child: Icon(
              isLive ? Icons.videocam_rounded : Icons.groups_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (isLive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Color(0xFF16A34A)),
                  SizedBox(width: 6),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class MeetingTranscriptStatusCard extends StatelessWidget {
  const MeetingTranscriptStatusCard({
    super.key,
    required this.phase,
    required this.detail,
    required this.durationLabel,
    this.diagnosticLabel,
  });

  final MeetingTranscriptPhase phase;
  final String detail;
  final String durationLabel;

  /// Temporary debug line (Listening, Speech detected, Restarting, …).
  final String? diagnosticLabel;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color, bg) = switch (phase) {
      MeetingTranscriptPhase.recording => (
          Icons.mic_rounded,
          'Live transcription active',
          const Color(0xFF2563EB),
          const Color(0xFFEFF6FF),
        ),
      MeetingTranscriptPhase.processing => (
          Icons.bolt_rounded,
          'Processing insights',
          const Color(0xFF7C3AED),
          const Color(0xFFF5F3FF),
        ),
      MeetingTranscriptPhase.saving => (
          Icons.save_rounded,
          'Saving',
          const Color(0xFF0891B2),
          const Color(0xFFECFEFF),
        ),
      MeetingTranscriptPhase.idle => (
          Icons.graphic_eq_rounded,
          'Ready',
          AppColors.textSecondary,
          const Color(0xFFF8FAFC),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.25,
                  ),
                ),
                if (diagnosticLabel != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      diagnosticLabel!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  durationLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MeetingParticipantsPanel extends StatelessWidget {
  const MeetingParticipantsPanel({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.participantCount,
    required this.activeCount,
    required this.isLive,
    required this.children,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final int participantCount;
  final int activeCount;
  final bool isLive;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: MeetingUi.cardDecoration(),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MeetingUi.radiusMd),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 20, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Participants ($participantCount)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (isLive)
                    Text(
                      '$activeCount in meeting',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(children: children),
            ),
          ],
        ],
      ),
    );
  }
}

class MeetingParticipantTile extends StatelessWidget {
  const MeetingParticipantTile({
    super.key,
    required this.name,
    required this.email,
    required this.initials,
    required this.presence,
  });

  final String name;
  final String email;
  final String initials;
  final ParticipantPresence presence;

  @override
  Widget build(BuildContext context) {
    final (dot, label, labelColor) = switch (presence) {
      ParticipantPresence.inMeeting => (
          const Color(0xFF22C55E),
          'In meeting',
          const Color(0xFF15803D),
        ),
      ParticipantPresence.notJoined => (
          const Color(0xFF94A3B8),
          'Not joined',
          const Color(0xFF64748B),
        ),
      ParticipantPresence.offline => (
          const Color(0xFFEF4444),
          'Offline',
          const Color(0xFFB91C1C),
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              TAvatar(initials: initials, radius: 18),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: dot.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MeetingLiveNotesCard extends StatelessWidget {
  const MeetingLiveNotesCard({
    super.key,
    required this.lines,
    required this.emptyHint,
    this.partialSpeech,
    this.micBanner,
  });

  final List<String> lines;
  final String? partialSpeech;
  final String emptyHint;
  final Widget? micBanner;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.notes_rounded, size: 18, color: AppColors.primary),
            SizedBox(width: 6),
            Text(
              'Live Notes',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: MeetingUi.cardDecoration(),
            child: Column(
              children: [
                if (micBanner != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: micBanner,
                  ),
                ],
                Expanded(
                  child: lines.isEmpty &&
                          (partialSpeech == null || partialSpeech!.isEmpty)
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              emptyHint,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final raw in lines)
                              MeetingSpeechBubble(
                                line: MeetingNoteLine.parse(raw) ??
                                    MeetingNoteLine(
                                      speaker: 'Chat',
                                      text: raw,
                                    ),
                              ),
                            if (partialSpeech != null &&
                                partialSpeech!.trim().isNotEmpty)
                              MeetingSpeechBubble(
                                line: MeetingNoteLine(
                                  speaker: 'Listening…',
                                  text: partialSpeech!.trim(),
                                ),
                                isPartial: true,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MeetingSpeechBubble extends StatelessWidget {
  const MeetingSpeechBubble({
    super.key,
    required this.line,
    this.isPartial = false,
  });

  final MeetingNoteLine line;
  final bool isPartial;

  @override
  Widget build(BuildContext context) {
    final bg =
        line.isSpeech ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC);
    final border = line.isSpeech ? const Color(0xFFBFDBFE) : AppColors.border;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                AppColors.primary.withValues(alpha: isPartial ? 0.12 : 0.18),
            child: Text(
              line.speaker.isNotEmpty ? line.speaker[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isPartial ? AppColors.textSecondary : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.speaker,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isPartial
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '"${line.text}"',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontStyle:
                          isPartial ? FontStyle.italic : FontStyle.normal,
                      color: isPartial
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MeetingLiveControls extends StatelessWidget {
  const MeetingLiveControls({
    super.key,
    required this.muted,
    required this.isRecording,
    required this.speechUnavailable,
    required this.saving,
    required this.onMute,
    required this.onRecord,
    required this.onSave,
    required this.onEndMeeting,
    this.isSharing = false,
    this.onShare,
  });

  final bool muted;
  final bool isRecording;
  final bool speechUnavailable;
  final bool saving;
  final bool isSharing;
  final VoidCallback onMute;
  final VoidCallback? onRecord;
  final VoidCallback? onSave;
  final VoidCallback? onShare;
  final VoidCallback onEndMeeting;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final int count = onShare != null ? 4 : 3;
            final double spacing = (count - 1) * 8.0;
            final double btnWidth = (constraints.maxWidth - spacing) / count;
            final double actualWidth = btnWidth < 75 ? 75 : btnWidth;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: actualWidth,
                    child: _ControlBtn(
                      label: muted ? 'Unmute' : 'Mute',
                      icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      style: _ControlStyle.secondary,
                      onPressed: onMute,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: actualWidth,
                    child: _ControlBtn(
                      label: speechUnavailable
                          ? 'Enable mic'
                          : (isRecording ? 'Live' : 'Record'),
                      icon: isRecording
                          ? Icons.fiber_manual_record_rounded
                          : Icons.mic_none_rounded,
                      style: isRecording && !speechUnavailable
                          ? _ControlStyle.recording
                          : _ControlStyle.primary,
                      onPressed: onRecord,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: actualWidth,
                    child: _ControlBtn(
                      label: saving
                          ? 'Saving…'
                          : (isRecording ? 'Stop & Save' : 'Save'),
                      icon: Icons.save_rounded,
                      style: _ControlStyle.secondary,
                      onPressed: saving ? null : onSave,
                    ),
                  ),
                  if (onShare != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: actualWidth,
                      child: _ControlBtn(
                        label: isSharing ? 'Stop Sharing' : 'Share Screen',
                        icon: isSharing
                            ? Icons.stop_screen_share
                            : Icons.screen_share,
                        style: isSharing
                            ? _ControlStyle.recording
                            : _ControlStyle.primary,
                        onPressed: onShare,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton(
            onPressed: onEndMeeting,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFECACA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
              ),
              elevation: 0,
            ),
            child: const Text(
              'End Meeting',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

enum _ControlStyle { primary, secondary, recording }

class _ControlBtn extends StatelessWidget {
  const _ControlBtn({
    required this.label,
    required this.icon,
    required this.style,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final _ControlStyle style;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool recording = style == _ControlStyle.recording;
    final Color fg = recording ? Colors.white : AppColors.primary;
    final Color bg = recording
        ? const Color(0xFFDC2626)
        : (style == _ControlStyle.primary
            ? AppColors.primaryLight
            : Colors.white);
    final BorderSide side =
        recording ? BorderSide.none : const BorderSide(color: AppColors.border);

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
        side: side,
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
        child: SizedBox(
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20, color: onPressed == null ? AppColors.textHint : fg),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: onPressed == null ? AppColors.textHint : fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary widgets ───────────────────────────────────────────────────────────

class SummaryOverviewCard extends StatelessWidget {
  const SummaryOverviewCard({
    super.key,
    required this.title,
    required this.participantsLabel,
    required this.durationLabel,
  });

  final String title;
  final String participantsLabel;
  final String? durationLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: MeetingUi.cardDecoration(
        fill: AppColors.primaryLight.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _MetaChip(icon: Icons.people_outline, label: participantsLabel),
              if (durationLabel != null && durationLabel!.isNotEmpty)
                _MetaChip(icon: Icons.schedule, label: durationLabel!),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }
}

class SummarySectionHeader extends StatelessWidget {
  const SummarySectionHeader(
      {super.key, required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryEmptyCard extends StatelessWidget {
  const SummaryEmptyCard({
    super.key,
    required this.icon,
    required this.message,
    this.emoji,
  });

  final IconData icon;
  final String message;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (emoji != null)
            Text(emoji!, style: const TextStyle(fontSize: 28))
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single card with structured AI summary bullets.
class SummaryAiInsightsCard extends StatelessWidget {
  const SummaryAiInsightsCard({super.key, required this.bullets});

  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < bullets.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    bullets[i],
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      letterSpacing: 0.1,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SummaryCollapsibleTranscript extends StatelessWidget {
  const SummaryCollapsibleTranscript({
    super.key,
    required this.lines,
    required this.entryCount,
    required this.expanded,
    required this.onToggle,
  });

  final List<String> lines;
  final int entryCount;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.article_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Full Transcript',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: AppColors.border),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                itemCount: lines.length,
                separatorBuilder: (_, i) {
                  if (lines[i].isEmpty) return const SizedBox(height: 12);
                  return const SizedBox(height: 8);
                },
                itemBuilder: (_, i) {
                  final line = lines[i];
                  if (line.isEmpty) return const SizedBox.shrink();
                  final isSpeaker = RegExp(r'^[^:]+:\s*$').hasMatch(line);
                  if (isSpeaker) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    );
                  }
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SummaryBulletCard extends StatelessWidget {
  const SummaryBulletCard({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: MeetingUi.cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
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
}

class SummaryActionChecklistCard extends StatelessWidget {
  const SummaryActionChecklistCard({
    super.key,
    required this.text,
    required this.owner,
    required this.due,
  });

  final String text;
  final String owner;
  final String due;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_box_outline_blank_rounded,
            size: 24,
            color: AppColors.primary.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Tag(label: owner, icon: Icons.person_outline),
                    _Tag(label: due, icon: Icons.event_outlined),
                    const _Tag(
                      label: 'Open',
                      icon: Icons.radio_button_unchecked,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class SummaryActionsRow extends StatelessWidget {
  const SummaryActionsRow({
    super.key,
    required this.exportBusy,
    required this.canCreateTasks,
    required this.onExport,
    required this.onShare,
    required this.onCreateTasks,
  });

  final bool exportBusy;
  final bool canCreateTasks;
  final VoidCallback? onExport;
  final VoidCallback? onShare;
  final VoidCallback? onCreateTasks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: exportBusy ? null : onExport,
          icon: exportBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_as_pdf_outlined, size: 20),
          label: const Text('Export as PDF'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: exportBusy ? null : onShare,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
                  ),
                ),
              ),
            ),
            if (canCreateTasks) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCreateTasks,
                  icon: const Icon(Icons.add_task_rounded, size: 18),
                  label: const Text('Create Tasks'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(MeetingUi.radiusMd),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
