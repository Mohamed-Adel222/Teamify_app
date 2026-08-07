import 'dart:typed_data';

import '../../core/network/api_result.dart';
import '../../core/network/service_error_handler.dart';
import '../../data/repositories/ai_repository.dart';
import '../../data/repositories/cv_repository.dart';
import '../../core/cache/cache_manager.dart';
import '../../core/network/request_deduplicator.dart';

/// Service layer for all AI-powered features.
///
/// Converts raw AI API responses into meaningful, UI-ready results:
/// - Transcription (voice note → text)
/// - Anomaly detection (admin alert enrichment)
/// - Mentor analysis (performance insights dashboard data)
/// - CV building
class AIService with ServiceErrorHandler {
  final AIRepository _ai;
  final CVRepository _cv;
  final CacheManager _cache;
  static const _box = 'ai';
  final RequestDeduplicator _dedup = RequestDeduplicator();

  AIService({
    required AIRepository ai,
    required CVRepository cv,
    required CacheManager cache,
  })  : _ai = ai,
        _cv = cv,
        _cache = cache;

  // ── Transcription ─────────────────────────────────────────────────────

  /// Transcribes audio bytes into text.
  /// Returns a [TranscriptionResult] ready for UI display.
  Future<ApiResult<TranscriptionResult>> transcribe(
    Uint8List audioBytes, {
    String filename = 'audio.wav',
    String language = 'en',
  }) =>
      guard(() async {
        final data = await _ai.transcribe(
          audioBytes,
          filename: filename,
          language: language,
        );
        final procSec = data['processing_time_seconds'];
        return TranscriptionResult(
          text: data['text']?.toString() ?? data['raw_text']?.toString() ?? '',
          confidence: data['success'] == true ? 1.0 : 0.0,
          language: data['language']?.toString() ?? language,
          durationMs: procSec is num ? (procSec * 1000).round() : 0,
        );
      });

  // ── Anomaly Detection ─────────────────────────────────────────────────

  /// Runs anomaly detection and returns structured alert data.
  Future<ApiResult<AnomalyReport>> detectAnomaly(
    Map<String, dynamic> payload,
  ) =>
      _dedup.deduplicate(
          'detect_anomaly',
          () => guard(() async {
                final data = await _ai.detectAnomaly(payload);
                final anomalies = (data['anomalies'] as List?)
                        ?.map((e) => AnomalyItem.fromJson(
                            e is Map<String, dynamic> ? e : const {}))
                        .toList() ??
                    const [];
                return AnomalyReport(
                  isAnomalous: data['is_anomalous'] == true,
                  riskScore: (data['risk_score'] as num?)?.toDouble() ?? 0.0,
                  anomalies: anomalies,
                  summary: data['summary']?.toString() ?? '',
                );
              }));

  // ── Mentor Analysis ───────────────────────────────────────────────────

  /// Fetches the full mentor analysis for a user,
  /// combining recommendations + performance + courses.
  Future<ApiResult<MentorInsights>> getMentorInsights(
    String userId, {
    bool forceRefresh = false,
  }) =>
      _dedup.deduplicate(
          'mentor_insights_$userId',
          () => guard(() async {
                if (forceRefresh) {
                  await _cache.invalidate(_box, 'mentor_insights_$userId');
                }
                final cached = forceRefresh
                    ? null
                    : await _cache.getMap(_box, 'mentor_insights_$userId');
                if (cached != null) {
                  final insights = _parseMentorInsights(cached);
                  _fetchAndCacheMentorInsights(userId);
                  return insights;
                }
                return _fetchAndCacheMentorInsights(userId);
              }));

  Future<void> invalidateMentorInsights(String userId) =>
      _cache.invalidate(_box, 'mentor_insights_$userId');

  Future<ApiResult<List<Map<String, dynamic>>>> mentorChatHistory({
    int limit = 50,
    String threadKey = 'general',
  }) =>
      guard(() => _ai.mentorChatHistory(limit: limit, threadKey: threadKey));

  Future<MentorInsights> _fetchAndCacheMentorInsights(String userId) async {
    final payload = await _ai.mentorInsights(userId);
    final analysis = payload['analysis'] is Map
        ? Map<String, dynamic>.from(payload['analysis'] as Map)
        : payload;
    final performance = payload['performance'] is Map
        ? Map<String, dynamic>.from(payload['performance'] as Map)
        : <String, dynamic>{};
    final courses = payload['courses'] is Map
        ? Map<String, dynamic>.from(payload['courses'] as Map)
        : <String, dynamic>{};

    final insights = _mentorInsightsFromParts(analysis, performance, courses);

    await _cache.putMap(_box, 'mentor_insights_$userId', {
      'analysis': analysis,
      'performance': performance,
      'courses': courses,
    });

    return insights;
  }

  static MentorInsights _parseMentorInsights(Map<String, dynamic> cached) {
    final analysis = cached['analysis'] as Map<String, dynamic>? ?? {};
    final performance = cached['performance'] as Map<String, dynamic>? ?? {};
    final courses = cached['courses'] as Map<String, dynamic>? ?? {};
    return _mentorInsightsFromParts(analysis, performance, courses);
  }

  static MentorInsights _mentorInsightsFromParts(
    Map<String, dynamic> analysis,
    Map<String, dynamic> performance,
    Map<String, dynamic> courses,
  ) {
    final progress = analysis['career_progress'] as Map<String, dynamic>? ?? {};
    final careerScore = (analysis['overall_score'] as num?)?.toDouble() ??
        (progress['score'] as num?)?.toDouble() ??
        0.0;
    final perfOverall = (performance['overall'] as num?)?.toDouble();

    final courseList = (courses['courses'] as List?) ??
        (courses['recommended_courses'] as List?) ??
        const [];

    final gapsMap = analysis['skill_gaps'];
    final skillGaps = <MentorSkillInsight>[];
    var targetRole = '';
    var ownedSkills = <String>[];
    if (gapsMap is Map) {
      final gm = Map<String, dynamic>.from(gapsMap);
      targetRole = gm['target_role']?.toString() ?? '';
      final owned = gm['owned_skills'];
      if (owned is List) {
        ownedSkills =
            owned.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
      final details = gm['skill_details'];
      if (details is List && details.isNotEmpty) {
        for (final item in details) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final name = m['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          final isOwned = m['owned'] == true;
          skillGaps.add(MentorSkillInsight(
            area: name,
            message: m['message']?.toString() ??
                (isOwned
                    ? 'Listed on your profile'
                    : (targetRole.isNotEmpty
                        ? 'Required for $targetRole'
                        : 'Skill gap from your profile vs. target role')),
            score: (m['gap_score'] as num?)?.toDouble() ??
                (isOwned ? 100.0 : 70.0),
            severity:
                m['severity']?.toString() ?? (isOwned ? 'owned' : 'medium'),
          ));
        }
        skillGaps.sort((a, b) {
          if (a.severity == 'owned' && b.severity != 'owned') return 1;
          if (b.severity == 'owned' && a.severity != 'owned') return -1;
          return b.score.compareTo(a.score);
        });
      } else {
        final missing = gm['missing_skills'];
        if (missing is List) {
          for (var i = 0; i < missing.length; i++) {
            final name = missing[i].toString();
            if (name.isEmpty) continue;
            skillGaps.add(MentorSkillInsight(
              area: name,
              message: targetRole.isNotEmpty
                  ? 'Required for $targetRole'
                  : 'Skill gap from your profile vs. target role',
              score: (95 - i * 10).clamp(40, 95).toDouble(),
              severity: i == 0 ? 'high' : 'medium',
            ));
          }
        }
      }
    }

    final profileRaw = analysis['user_profile'];
    final profile = profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : <String, dynamic>{};
    final profileSkills = _normalizeProfileSkills(profile['skills']);

    final mlRating = analysis['ml_rating'] is Map
        ? Map<String, dynamic>.from(analysis['ml_rating'] as Map)
        : <String, dynamic>{};

    final dbSummary = analysis['db_summary']?.toString().trim() ?? '';
    final summary = analysis['summary']?.toString().trim() ?? '';
    final careerSummary = dbSummary.isNotEmpty
        ? dbSummary
        : (summary.isNotEmpty
            ? summary
            : _extractCareerSummary(analysis['mentor_report']?.toString()));

    final careerLevel = analysis['career_level']?.toString() ??
        profile['career_level']?.toString() ??
        progress['level']?.toString() ??
        profile['experience_level']?.toString() ??
        'Developer';

    return MentorInsights(
      careerScore: careerScore,
      performanceOverall: perfOverall ?? careerScore,
      careerSummary: careerSummary,
      careerLevel: careerLevel,
      strengths: _parseSkillInsights(analysis['strengths']),
      weaknesses: _parseSkillInsights(analysis['weaknesses']),
      skillGaps: skillGaps,
      performanceHistory: performance,
      recommendedCourses: courseList
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      rawAnalysis: analysis,
      mlRating: mlRating,
      targetRole: targetRole,
      trend: performance['trend']?.toString() ?? 'stable',
      feedbackCount: (performance['feedback_count'] as num?)?.toInt() ??
          (profile['feedback_count'] as num?)?.toInt() ??
          0,
      ratingCount: (performance['rating_count'] as num?)?.toInt() ??
          (profile['rating_count'] as num?)?.toInt() ??
          0,
      aiTip: performance['ai_tip']?.toString() ?? '',
      profileSkills: profileSkills,
      ownedSkills: ownedSkills,
      professionalField: profile['professional_field']?.toString() ?? '',
      experienceYears:
          (profile['member_experience_years'] as num?)?.toDouble() ?? 0,
      tasksAssigned: (profile['tasks_assigned'] as num?)?.toInt() ?? 0,
      tasksCompleted: (profile['tasks_completed'] as num?)?.toInt() ?? 0,
      generatedAt: analysis['generated_at']?.toString() ?? '',
    );
  }

  /// DB skills may be a list, comma string, or legacy per-character list.
  static List<String> _normalizeProfileSkills(dynamic raw) {
    if (raw == null) return const [];
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return const [];
      return text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.length > 1)
          .toList();
    }
    if (raw is List) {
      final items = raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (items.isEmpty) return const [];
      final shortCount = items.where((s) => s.length <= 2).length;
      if (items.length >= 5 && shortCount / items.length > 0.6) {
        final joined = items.join();
        return joined
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.length > 1)
            .toList();
      }
      return items.where((s) => s.length > 1).toList();
    }
    return const [];
  }

  static String _extractCareerSummary(String? report) {
    if (report == null || report.isEmpty) return "You're progressing well.";
    final parts = report.split('##');
    if (parts.length > 1) {
      return parts[1].replaceAll('Career Summary', '').trim();
    }
    return report.length > 280 ? '${report.substring(0, 280)}…' : report;
  }

  static List<MentorSkillInsight> _parseSkillInsights(dynamic value) {
    if (value is! List) return const [];
    final out = <MentorSkillInsight>[];
    for (final item in value) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        out.add(MentorSkillInsight(
          area: m['area']?.toString() ?? 'Skill',
          message: m['message']?.toString() ?? '',
          score: (m['score'] as num?)?.toDouble() ?? 0,
          severity: m['severity']?.toString() ?? '',
        ));
      } else if (item != null) {
        out.add(MentorSkillInsight(
          area: 'Insight',
          message: item.toString(),
          score: 0,
        ));
      }
    }
    return out;
  }

  /// POST /api/ai/mentor/chat — real AI mentor reply with user context.
  ///
  /// [question] is the user's message.
  /// [history] is the prior conversation (list of {role, content} maps).
  /// [taskContext] is optional context about the active task.
  Future<ApiResult<MentorChatReply>> mentorChat({
    required String question,
    List<Map<String, dynamic>> history = const [],
    Map<String, dynamic>? taskContext,
    Map<String, dynamic>? userContext,
    bool persistHistory = true,
    String threadKey = 'general',
  }) =>
      guard(() async {
        final data = await _ai.mentorChat(
          question: question,
          history: history,
          taskContext: taskContext,
          userContext: userContext,
          persistHistory: persistHistory,
          threadKey: threadKey,
        );
        final ml = data['ml'];
        return MentorChatReply(
          reply: data['reply']?.toString() ?? '',
          suggestions: (data['suggestions'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          ml: ml is Map ? Map<String, dynamic>.from(ml) : const {},
        );
      });

  /// Summarises chat transcript text into key points / actions (backend AI).
  Future<ApiResult<Map<String, dynamic>>> summarizeChat(
    String text, {
    int topN = 6,
  }) =>
      _dedup.deduplicate('summarize_chat',
          () => guard(() => _ai.summarizeChat(text, topN: topN)));

  Future<ApiResult<Map<String, dynamic>>> recommendTeammates(
    Map<String, dynamic> userStats, {
    int topN = 5,
  }) =>
      _dedup.deduplicate(
        'recommend_teammates_$topN',
        () => guard(() => _ai.recommendTeammates(userStats, topN: topN)),
      );

  Future<ApiResult<Map<String, dynamic>>> mentorCourses(String userId) =>
      _dedup.deduplicate('mentor_courses_$userId',
          () => guard(() => _ai.mentorCourses(userId)));

  /// GET /api/ai/mentor/recommendations/<id> — career summary + next steps (raw map)
  Future<ApiResult<Map<String, dynamic>>> mentorRecommendations(
          String userId) =>
      _dedup.deduplicate('mentor_recommendations_$userId',
          () => guard(() => _ai.mentorRecommendations(userId)));

  /// GET /api/ai/mentor/insights/<id> — full insights payload (raw map, for SkillsScreen etc.)
  Future<ApiResult<Map<String, dynamic>>> mentorInsights(String userId) =>
      _dedup.deduplicate('mentor_insights_raw_$userId',
          () => guard(() => _ai.mentorInsights(userId)));

  // ── Task AI features ──────────────────────────────────────────────────

  Future<ApiResult<Map<String, dynamic>>> classifyTask(String text) =>
      _dedup.deduplicate(
        'classify_task_${text.hashCode}',
        () => guard(() => _ai.classifyTask(text)),
      );

  /// POST /api/ai/feedback-assist — draft peer-feedback comment + tip.
  Future<ApiResult<Map<String, String>>> generateFeedbackAssist({
    required int rating,
    String teammateName = '',
    String projectName = '',
  }) =>
      guard(() async {
        final data = await _ai.feedbackAssist(
          rating: rating,
          teammateName: teammateName,
          projectName: projectName,
        );
        return {
          'draft': data['draft']?.toString() ?? '',
          'suggestion': data['suggestion']?.toString() ?? '',
        };
      });

  Future<ApiResult<Map<String, dynamic>>> suggestPriority({
    required String projectId,
    String title = '',
    String description = '',
  }) =>
      _dedup.deduplicate(
          'suggest_priority_$projectId',
          () => guard(() => _ai.suggestPriority(
                projectId: projectId,
                title: title,
                description: description,
              )));

  Future<ApiResult<Map<String, dynamic>>> suggestDeadline({
    required String projectId,
    String priority = 'medium',
    String title = '',
    String description = '',
  }) =>
      _dedup.deduplicate(
          'suggest_deadline_$projectId',
          () => guard(() => _ai.suggestDeadline(
                projectId: projectId,
                priority: priority,
                title: title,
                description: description,
              )));

  Future<ApiResult<Map<String, dynamic>>> predictDelay({
    String? taskId,
    String? projectId,
    bool forceRefresh = false,
  }) {
    final key = 'predict_delay_${taskId ?? projectId}';
    Future<ApiResult<Map<String, dynamic>>> fetch() => guard(
          () => _ai.predictDelay(taskId: taskId, projectId: projectId),
        );
    if (forceRefresh) return fetch();
    return _dedup.deduplicate(key, fetch);
  }

  Future<ApiResult<Map<String, dynamic>>> getDelayModelStatus() => _dedup
      .deduplicate('delay_model_status', () => guard(_ai.getDelayModelStatus));

  // ── CV AI ─────────────────────────────────────────────────────────────

  Future<ApiResult<Map<String, dynamic>>> buildCVWithAI(
          {String? targetUserId}) =>
      _dedup.deduplicate('build_cv_ai',
          () => guard(() => _cv.buildWithAI(targetUserId: targetUserId)));

  /// Downloads a CV PDF via secure token, returning raw bytes.
  Future<ApiResult<Uint8List>> downloadCVByToken(String token) =>
      _dedup.deduplicate(
          'download_cv_$token',
          () => guard(() async {
                final response = await _cv.downloadByToken(token);
                return Uint8List.fromList(response.data ?? []);
              }));
}

// ── Result Models ─────────────────────────────────────────────────────────

class TranscriptionResult {
  final String text;
  final double confidence;
  final String language;
  final int durationMs;

  const TranscriptionResult({
    required this.text,
    required this.confidence,
    required this.language,
    required this.durationMs,
  });
}

class AnomalyReport {
  final bool isAnomalous;
  final double riskScore;
  final List<AnomalyItem> anomalies;
  final String summary;

  const AnomalyReport({
    required this.isAnomalous,
    required this.riskScore,
    required this.anomalies,
    required this.summary,
  });
}

class AnomalyItem {
  final String type;
  final String description;
  final String severity;

  const AnomalyItem({
    required this.type,
    required this.description,
    required this.severity,
  });

  factory AnomalyItem.fromJson(Map<String, dynamic> json) => AnomalyItem(
        type: json['type']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        severity: json['severity']?.toString() ?? 'low',
      );
}

class MentorSkillInsight {
  final String area;
  final String message;
  final double score;
  final String severity;

  const MentorSkillInsight({
    required this.area,
    required this.message,
    this.score = 0,
    this.severity = '',
  });
}

class MentorInsights {
  /// Career progression score from tasks + feedback NLP (0–100).
  final double careerScore;

  /// Avg commitment/teamwork/quality from DB feedback & ratings (0–100).
  final double performanceOverall;

  final String careerSummary;
  final String careerLevel;
  final List<MentorSkillInsight> strengths;
  final List<MentorSkillInsight> weaknesses;
  final List<MentorSkillInsight> skillGaps;
  final Map<String, dynamic> performanceHistory;
  final List<Map<String, dynamic>> recommendedCourses;
  final Map<String, dynamic> rawAnalysis;
  final Map<String, dynamic> mlRating;
  final String targetRole;
  final String trend;
  final int feedbackCount;
  final int ratingCount;
  final String aiTip;
  final List<String> profileSkills;
  final List<String> ownedSkills;
  final String professionalField;
  final double experienceYears;
  final int tasksAssigned;
  final int tasksCompleted;
  final String generatedAt;

  const MentorInsights({
    required this.careerScore,
    required this.performanceOverall,
    required this.careerSummary,
    required this.careerLevel,
    required this.strengths,
    required this.weaknesses,
    this.skillGaps = const [],
    required this.performanceHistory,
    required this.recommendedCourses,
    required this.rawAnalysis,
    this.mlRating = const {},
    this.targetRole = '',
    this.trend = 'stable',
    this.feedbackCount = 0,
    this.ratingCount = 0,
    this.aiTip = '',
    this.profileSkills = const [],
    this.ownedSkills = const [],
    this.professionalField = '',
    this.experienceYears = 0,
    this.tasksAssigned = 0,
    this.tasksCompleted = 0,
    this.generatedAt = '',
  });

  /// Back-compat alias for career score used in progress bars.
  double get overallScore => careerScore;

  double metricScore(String key) {
    final scores = performanceHistory['scores'];
    if (scores is Map && scores[key] != null) {
      return (scores[key] as num).toDouble();
    }
    return performanceOverall;
  }

  List<Map<String, dynamic>> get recentFeedback {
    final raw = performanceHistory['recent_feedback'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  bool get hasPeerPerformanceData =>
      feedbackCount > 0 ||
      ratingCount > 0 ||
      performanceHistory['source']?.toString() == 'peer_feedback';
}

class MentorChatReply {
  final String reply;
  final List<String> suggestions;
  final Map<String, dynamic> ml;

  const MentorChatReply({
    required this.reply,
    this.suggestions = const [],
    this.ml = const {},
  });

  bool get usedMlModel => ml['source']?.toString() == 'ml_model';
}
