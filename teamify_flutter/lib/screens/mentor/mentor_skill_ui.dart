import 'package:flutter/material.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../services/ai_service.dart';

/// Skill card layout used in AI Career Mentor → Skills and /skills route.
class MentorSkillCard extends StatelessWidget {
  const MentorSkillCard({
    super.key,
    required this.title,
    required this.score,
    required this.levelLabel,
    this.subtitle = 'Based on your work history',
    this.onExplore,
  });

  final String title;
  final double score;
  final String levelLabel;
  final String subtitle;
  final VoidCallback? onExplore;

  static IconData iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('design') || n.contains('system')) {
      return Icons.architecture_outlined;
    }
    if (n.contains('graphql') || n.contains('api')) {
      return Icons.hub_outlined;
    }
    if (n.contains('performance') || n.contains('optim')) {
      return Icons.speed_outlined;
    }
    if (n.contains('flutter') || n.contains('mobile')) {
      return Icons.phone_android_outlined;
    }
    if (n.contains('python') || n.contains('backend')) {
      return Icons.code_outlined;
    }
    return Icons.auto_awesome_outlined;
  }

  static String levelForScore(double score, {bool owned = false}) {
    if (owned || score >= 80) return 'Advanced';
    if (score >= 55) return 'Intermediate';
    return 'Beginner';
  }

  static void openExploreChat(
    BuildContext context, {
    required String skillName,
    required double score,
    required String levelLabel,
  }) {
    Navigator.pushNamed(
      context,
      R.aiMentorChat,
      arguments: MentorSkillChatArgs(
        skillName: skillName,
        score: score,
        levelLabel: levelLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pct = score.clamp(0.0, 100.0) / 100.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(iconFor(title), color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  levelLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Relevance Score',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onExplore ??
                  () => openExploreChat(
                        context,
                        skillName: title,
                        score: score,
                        levelLabel: levelLabel,
                      ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Explore Skill',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Route arguments when opening AI Mentor from **Explore Skill**.
class MentorSkillChatArgs {
  final String skillName;
  final double score;
  final String levelLabel;

  const MentorSkillChatArgs({
    required this.skillName,
    required this.score,
    required this.levelLabel,
  });

  String get threadKey => 'skill:${skillName.trim().toLowerCase()}';
}

/// Route arguments when opening AI Mentor from the **Ask AI Mentor** FAB
/// with live ML insights (teamify_model.pkl).
class MentorGeneralChatArgs {
  static const threadKey = 'general';
  static const mlModelPath = 'Profiles&AI Rating/teamify_model.pkl';

  final Map<String, dynamic> mlRating;
  final String careerLevel;
  final double careerScore;
  final List<String> skillGaps;
  final List<Map<String, dynamic>> recommendedCourses;

  const MentorGeneralChatArgs({
    required this.mlRating,
    required this.careerLevel,
    required this.careerScore,
    this.skillGaps = const [],
    this.recommendedCourses = const [],
  });

  factory MentorGeneralChatArgs.fromInsights(MentorInsights insights) {
    final gaps = <String>[];
    for (final g in insights.skillGaps) {
      if (g.severity == 'owned') continue;
      if (g.area.trim().isNotEmpty) gaps.add(g.area);
    }
    for (final w in insights.weaknesses) {
      if (w.area.trim().isNotEmpty && !gaps.contains(w.area)) {
        gaps.add(w.area);
      }
    }

    return MentorGeneralChatArgs(
      mlRating: Map<String, dynamic>.from(insights.mlRating),
      careerLevel: insights.careerLevel,
      careerScore: insights.careerScore,
      skillGaps: gaps.take(3).toList(),
      recommendedCourses: insights.recommendedCourses
          .take(4)
          .map((c) => Map<String, dynamic>.from(c))
          .toList(),
    );
  }

  bool get usesMlModel => mlRating['source']?.toString() == 'ml_model';

  String buildGreeting() {
    final pred = mlRating['predicted_rating'];
    final label = mlRating['percentile_label'] ?? mlRating['performance_label'];
    final mlLine = pred != null
        ? (usesMlModel
            ? 'ML rating (**$mlModelPath**): **$pred/5**${label != null ? ' ($label)' : ''}.'
            : 'Estimated rating: **$pred/5**.')
        : '';

    final gapsTxt =
        skillGaps.isNotEmpty ? skillGaps.join(', ') : 'building core skills';

    var courseBlock = '';
    if (recommendedCourses.isNotEmpty) {
      courseBlock = recommendedCourses
          .take(3)
          .map(
            (c) =>
                '• **${c['title'] ?? 'Course'}** (${c['platform'] ?? 'Online'}, ${c['hours'] ?? '?'} hrs)',
          )
          .join('\n');
      courseBlock = '\n\nTop ML-recommended courses:\n$courseBlock';
    }

    return "Hi! I'm your AI Career Mentor, powered by **Teamify ML** (`$mlModelPath`).\n\n"
        "${mlLine.isNotEmpty ? '$mlLine\n' : ''}"
        "You're **$careerLevel** with career score **${careerScore.toStringAsFixed(0)}/100**.\n"
        "Focus areas: $gapsTxt."
        "$courseBlock\n\n"
        "Ask about courses, promotion, or your ML performance rating.";
  }

  List<String> buildSuggestions() {
    final out = <String>[
      'What does my ML performance rating mean?',
      'Recommend courses for me',
      'How do I get promoted?',
    ];
    if (skillGaps.isNotEmpty) {
      out.insert(0, 'How do I improve my ${skillGaps.first}?');
    }
    return out.take(4).toList();
  }

  Map<String, dynamic> toUserContext() => {
        'source': 'mentor_fab',
        'models': [mlModelPath],
        'ml_rating': mlRating,
        'career_level': careerLevel,
        'career_score': careerScore.round(),
        'skill_gaps': skillGaps,
      };

  static void openFromInsights(BuildContext context, MentorInsights insights) {
    Navigator.pushNamed(
      context,
      R.aiMentorChat,
      arguments: MentorGeneralChatArgs.fromInsights(insights),
    );
  }
}
