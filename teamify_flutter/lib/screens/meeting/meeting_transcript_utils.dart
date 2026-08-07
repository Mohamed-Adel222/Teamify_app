/// Helpers to clean meeting transcripts before summary UI / API calls.
library;

/// Join streaming speech segments into one continuous utterance block.
String mergeSpeechSegment(String existing, String segment) {
  final s = segment.trim();
  if (s.isEmpty) return existing.trim();
  final e = existing.trim();
  if (e.isEmpty) return s;
  if (e == s || e.endsWith(s)) return e;
  if (s.startsWith(e)) return s;
  if (e.contains(s)) return e;
  return '$e $s';
}

/// Normalizes, sorts, and deduplicates meeting transcript entries.
List<Map<String, dynamic>> normalizeMeetingTranscript(
  List<Map<String, dynamic>> raw,
) {
  final items = raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((e) => (e['content']?.toString().trim() ?? '').isNotEmpty)
      .toList();

  items.sort((a, b) {
    final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return da.compareTo(db);
  });

  return _dedupeTranscript(items);
}

List<Map<String, dynamic>> _dedupeTranscript(
  List<Map<String, dynamic>> items,
) {
  final out = <Map<String, dynamic>>[];
  for (final item in items) {
    final content = item['content']?.toString().trim() ?? '';
    if (content.isEmpty) continue;

    final isSpeech = item['source']?.toString() == 'speech';
    if (isSpeech && out.isNotEmpty) {
      final prev = out.last;
      if (prev['source']?.toString() == 'speech') {
        final prevText = prev['content']?.toString().trim() ?? '';
        if (content == prevText) continue;
        if (content.startsWith(prevText) && content.length > prevText.length) {
          out.removeLast();
        } else if (prevText.startsWith(content)) {
          continue;
        }
      }
    }

    final dup = out.any((e) {
      final sameSource = e['source']?.toString() == item['source']?.toString();
      final sameContent = e['content']?.toString().trim() == content;
      final sameSender =
          e['sender_id']?.toString() == item['sender_id']?.toString();
      return sameSource && sameContent && sameSender;
    });
    if (!dup) out.add(item);
  }
  return out;
}

/// Human-readable duration; caps absurd values from bad timestamps.
String? formatMeetingDuration({
  int? durationSeconds,
  DateTime? startedAt,
  DateTime? endedAt,
}) {
  int? secs = durationSeconds;
  if ((secs == null || secs <= 0) && startedAt != null && endedAt != null) {
    secs = endedAt.difference(startedAt).inSeconds;
  }
  if (secs == null || secs <= 0) return null;
  // Ignore corrupt durations (e.g. whole chat history used as span).
  if (secs > 8 * 3600) return null;

  final d = Duration(seconds: secs);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '${h}h $m:$s';
  return '$m:$s';
}

int countUniqueParticipants(List<Map<String, dynamic>> msgs) {
  final ids = <String>{};
  for (final m in msgs) {
    final id = m['sender_id']?.toString() ?? '';
    final name = m['sender_name']?.toString().trim() ?? '';
    if (id.isNotEmpty) {
      ids.add(id);
    } else if (name.isNotEmpty) {
      ids.add(name.toLowerCase());
    }
  }
  return ids.length;
}

List<String> speechLinesFromTranscript(List<Map<String, dynamic>> msgs) {
  return formatTranscriptDisplayLines(
    msgs.where((m) => m['source']?.toString() == 'speech').toList(),
  );
}

List<String> chatLinesFromTranscript(List<Map<String, dynamic>> msgs) {
  return formatTranscriptDisplayLines(
    msgs.where((m) => m['source']?.toString() != 'speech').toList(),
  );
}

String clampSummaryText(String text, {int maxLen = 480}) {
  final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.length <= maxLen) return cleaned;
  final cut = cleaned.substring(0, maxLen);
  final lastPeriod = cut.lastIndexOf('.');
  if (lastPeriod > maxLen ~/ 2) {
    return cut.substring(0, lastPeriod + 1);
  }
  return '$cut…';
}

/// Split AI summary prose into readable bullet lines.
List<String> summaryTextToBullets(String text, {int maxItems = 8}) {
  final raw = text.trim();
  if (raw.isEmpty) return [];

  final lines = <String>[];
  for (final chunk in raw.split(RegExp(r'[\n\r]+'))) {
    final line = chunk.trim();
    if (line.isEmpty) continue;
    if (RegExp(r'^[-•*]\s+').hasMatch(line)) {
      lines.add(line.replaceFirst(RegExp(r'^[-•*]\s+'), '').trim());
    } else if (RegExp(r'^\d+[.)]\s+').hasMatch(line)) {
      lines.add(line.replaceFirst(RegExp(r'^\d+[.)]\s+'), '').trim());
    } else {
      lines.add(line);
    }
  }

  if (lines.length > 1) {
    return _dedupeBulletLines(lines, maxItems: maxItems, maxLen: 220);
  }

  final sentences = raw
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim().replaceAll(RegExp(r'^[-•*]\s+'), ''))
      .where((s) => s.length >= 12)
      .toList();

  if (sentences.isNotEmpty) {
    return _dedupeBulletLines(sentences, maxItems: maxItems, maxLen: 220);
  }

  // Raw speech often has no punctuation — chunk by words instead of dropping.
  return _dedupeBulletLines(
    chunkTextByWords(raw, maxChunk: 140),
    maxItems: maxItems,
    maxLen: 220,
  );
}

/// Split long plain text into readable chunks (word boundaries).
List<String> chunkTextByWords(String text, {int maxChunk = 140}) {
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.isEmpty) return [];

  final chunks = <String>[];
  final buf = StringBuffer();
  for (final w in words) {
    final next = buf.isEmpty ? w : '${buf.toString()} $w';
    if (next.length > maxChunk && buf.isNotEmpty) {
      chunks.add(buf.toString().trim());
      buf.clear();
      buf.write(w);
    } else {
      buf.clear();
      buf.write(next);
    }
  }
  if (buf.isNotEmpty) chunks.add(buf.toString().trim());
  return chunks;
}

/// Transcript lines for UI — never one giant wall of text.
List<String> formatTranscriptDisplayLines(
  List<Map<String, dynamic>> msgs, {
  int maxChunk = 200,
}) {
  final out = <String>[];
  for (final m in msgs) {
    final name = m['sender_name']?.toString().trim() ?? 'Speaker';
    final text = (m['content'] ?? '').toString().trim();
    if (text.isEmpty) continue;

    final chunks = chunkTextByWords(text, maxChunk: maxChunk);
    if (chunks.isEmpty) continue;

    out.add('$name:');
    for (final c in chunks) {
      out.add(c);
    }
    out.add(''); // spacer between speakers
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out;
}

/// True when text looks like raw STT, not a summary bullet.
bool isRawSpeechChunk(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (t.length > 150) return true;
  final caps = RegExp(r'[A-Z]').allMatches(t).length;
  if (t.length > 35 && caps < 2) return true;
  if (RegExp(r'^(you|uh|um|okay|ok|so|and)\b', caseSensitive: false)
      .hasMatch(t)) {
    return true;
  }
  return false;
}

String polishBulletLine(String text) {
  var t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return t;
  t = t[0].toUpperCase() + t.substring(1);
  if (!RegExp(r'[.!?]$').hasMatch(t)) t = '$t.';
  return t;
}

/// Readable summary bullets from speech (not raw transcript dumps).
List<String> narrativeBulletsFromMeeting(
  List<Map<String, dynamic>> msgs, {
  int maxItems = 5,
}) {
  final combined = msgs
      .map((m) => (m['content'] ?? '').toString().trim())
      .where((s) => s.length >= 12)
      .join(' ');
  if (combined.isEmpty) return [];

  final segments = combined
      .split(RegExp(
        r'\b(?:so|and|but|because|when|if|then|also|however|today|first)\b',
        caseSensitive: false,
      ))
      .map((s) => s.trim())
      .where((s) => s.length >= 28 && s.length <= 200)
      .map(polishBulletLine)
      .where((s) => !isRawSpeechChunk(s))
      .toList();

  if (segments.length >= 2) {
    return _dedupeBulletLines(segments, maxItems: maxItems, maxLen: 200);
  }

  return chunkTextByWords(combined, maxChunk: 110)
      .where((s) => s.length >= 20 && !isRawSpeechChunk(s))
      .map(polishBulletLine)
      .take(maxItems)
      .toList();
}

List<String> filterSummaryBullets(List<String> bullets) {
  return bullets
      .map((b) => b.trim())
      .where((b) => b.length >= 12 && !isRawSpeechChunk(b))
      .map(polishBulletLine)
      .toList();
}

/// Short follow-ups from speech (practice, learn, improve, etc.).
List<Map<String, String>> learningActionsFromTranscript(
  List<Map<String, dynamic>> msgs, {
  int maxItems = 4,
}) {
  final text =
      msgs.map((m) => (m['content'] ?? '').toString()).join(' ').toLowerCase();
  if (text.isEmpty) return [];

  final owner = msgs.first['sender_name']?.toString().trim().isNotEmpty == true
      ? msgs.first['sender_name'].toString().trim()
      : 'Team';

  final templates = <String, String>{
    'practice': 'Practice speaking regularly',
    'communication': 'Focus on communication skills',
    'grammar': 'Review grammar fundamentals',
    'pronunciation': 'Work on pronunciation',
    'read': 'Read English books or articles',
    'listen': 'Listen to more English content',
    'write': 'Practice writing in English',
    'mistake': 'Learn from common mistakes',
    'fluent': 'Build fluency through daily use',
  };

  final out = <Map<String, String>>[];
  for (final entry in templates.entries) {
    if (text.contains(entry.key)) {
      out.add({
        'text': entry.value,
        'owner': owner,
        'due': 'TBD',
      });
      if (out.length >= maxItems) break;
    }
  }
  return out;
}

List<String> _dedupeBulletLines(
  List<String> lines, {
  required int maxItems,
  int maxLen = 220,
}) {
  final seen = <String>{};
  final out = <String>[];
  for (final line in lines) {
    var s = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.length < 8) continue;
    if (s.length > maxLen) {
      for (final part in chunkTextByWords(s, maxChunk: maxLen - 10)) {
        if (part.length < 8) continue;
        final pk = part.toLowerCase();
        if (seen.contains(pk)) continue;
        seen.add(pk);
        out.add(part);
        if (out.length >= maxItems) return out;
      }
      continue;
    }
    final key = s.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(s);
    if (out.length >= maxItems) break;
  }
  return out;
}

/// True when text looks like pasted transcript, not a task.
bool looksLikeTranscriptDump(String text) {
  final t = text.trim();
  if (t.length < 100) return false;
  if (RegExp(r'\[Speech\]', caseSensitive: false).hasMatch(t)) return true;
  final sentences =
      t.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.length > 20);
  if (sentences.length >= 3) return true;
  final actionCue = RegExp(
    r'\b(will|should|must|need to|todo|task|assign|follow up|deadline|create|schedule|review)\b',
    caseSensitive: false,
  );
  return !actionCue.hasMatch(t);
}

List<String> cleanKeyPoints(
  List<dynamic>? raw, {
  int maxItems = 5,
  int minLength = 8,
}) {
  if (raw == null) return [];
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    var s = item.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.length < minLength) continue;
    if (s.length > 220) {
      for (final part in chunkTextByWords(s, maxChunk: 200)) {
        if (part.length < minLength) continue;
        final pk = part.toLowerCase();
        if (seen.contains(pk)) continue;
        seen.add(pk);
        out.add(part);
        if (out.length >= maxItems) break;
      }
      continue;
    }
    final key = s.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(s);
    if (out.length >= maxItems) break;
  }
  return out;
}

List<Map<String, String>> cleanActionItems(List<dynamic>? raw) {
  if (raw == null) return [];
  final out = <Map<String, String>>[];
  final keywords = RegExp(
    r'\b(will|should|must|need to|have to|todo|task|assign|follow up|deadline)\b',
    caseSensitive: false,
  );
  for (final item in raw) {
    String text;
    String owner;
    var structured = false;
    if (item is Map) {
      text = (item['action'] ?? item['text'] ?? item['task'] ?? '')
          .toString()
          .trim();
      owner = (item['person'] ?? item['owner'] ?? item['assignee'] ?? 'Team')
          .toString()
          .trim();
      structured =
          (item['action'] ?? item['task'] ?? '').toString().trim().isNotEmpty;
    } else {
      text = item.toString().trim();
      owner = 'Team';
    }
    if (text.length < 6 || text.length > 140) continue;
    if (looksLikeTranscriptDump(text)) continue;
    if (!structured && !keywords.hasMatch(text)) continue;
    out.add({
      'text': text,
      'owner': owner.isEmpty ? 'Team' : owner,
      'due': _actionDueLabel(item),
    });
    if (out.length >= 6) break;
  }
  return out;
}

String _actionDueLabel(dynamic item) {
  if (item is Map) {
    for (final key in ['due', 'due_date', 'deadline', 'when']) {
      final v = item[key]?.toString().trim();
      if (v != null && v.isNotEmpty && v.toLowerCase() != 'tbd') return v;
    }
  }
  return 'TBD';
}

/// Fallback when keyword filter yields no rows — still show AI action items.
List<Map<String, String>> relaxedActionItems(List<dynamic>? raw) {
  if (raw == null) return [];
  final out = <Map<String, String>>[];
  for (final item in raw) {
    String text;
    String owner;
    if (item is Map) {
      text = (item['action'] ?? item['text'] ?? item['task'] ?? '')
          .toString()
          .trim();
      owner = (item['person'] ?? item['owner'] ?? item['assignee'] ?? 'Team')
          .toString()
          .trim();
    } else {
      text = item.toString().trim();
      owner = 'Team';
    }
    if (text.length < 6 || text.length > 140) continue;
    if (looksLikeTranscriptDump(text)) continue;
    out.add({
      'text': text,
      'owner': owner.isEmpty ? 'Team' : owner,
      'due': _actionDueLabel(item),
    });
    if (out.length >= 8) break;
  }
  return out;
}

/// Derive decision bullets from summary text and transcript when AI fields are empty.
List<String> localMeetingDecisions({
  required List<Map<String, dynamic>> msgs,
  required String summaryText,
  int maxItems = 6,
}) {
  final seen = <String>{};
  final out = <String>[];

  void add(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll(RegExp(r'^[-•*]\s*'), '');
    if (s.length < 8 || s.length > 220) return;
    final key = s.toLowerCase();
    if (seen.contains(key)) return;
    seen.add(key);
    out.add(s);
  }

  final decisionCue = RegExp(
    r'\b(decided|agreed|approved|chosen|will use|concluded|resolved)\b',
    caseSensitive: false,
  );

  for (final part in summaryText.split(RegExp(r'(?<=[.!?])\s+'))) {
    if (decisionCue.hasMatch(part)) add(part);
    if (out.length >= maxItems) return out;
  }

  for (final m in msgs) {
    final text = (m['content'] ?? '').toString();
    if (decisionCue.hasMatch(text)) add(text);
    if (out.length >= maxItems) return out;
  }

  return out;
}

/// Infer follow-up tasks from transcript lines when action_items are missing.
List<Map<String, String>> localMeetingActions(
  List<Map<String, dynamic>> msgs, {
  int maxItems = 6,
}) {
  final keywords = RegExp(
    r'\b(will|should|must|need to|have to|todo|task|assign|follow up|deadline|create|update|review|schedule|implement)\b',
    caseSensitive: false,
  );
  final out = <Map<String, String>>[];
  final seen = <String>{};

  for (final m in msgs) {
    final text = (m['content'] ?? '').toString().trim();
    final owner = (m['sender_name'] ?? m['sender'] ?? 'Team').toString().trim();
    if (text.length < 8 || text.length > 140) continue;
    if (looksLikeTranscriptDump(text)) continue;
    if (!keywords.hasMatch(text)) continue;

    final key = text.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);

    out.add({
      'text': text,
      'owner': owner.isEmpty ? 'Team' : owner,
      'due': 'TBD',
    });
    if (out.length >= maxItems) break;
  }

  return out;
}
