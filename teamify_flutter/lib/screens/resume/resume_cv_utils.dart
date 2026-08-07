import 'package:flutter/material.dart';

import '../../data/models/api_user.dart';
import '../../core/theme.dart';

/// Normalizes AI build output and saved CV rows for [ResumePreviewScreen].
Map<String, dynamic> normalizeCvForPreview(Map<String, dynamic> raw) {
  final skills = <String>[];
  final skillsRaw = raw['skills'];
  if (skillsRaw is Map) {
    for (final key in ['technical', 'soft']) {
      final list = skillsRaw[key];
      if (list is List) {
        skills.addAll(list.map((e) => e.toString()).where((s) => s.isNotEmpty));
      }
    }
  } else if (skillsRaw is List) {
    for (final item in skillsRaw) {
      if (item is Map) {
        final name = item['name']?.toString() ?? '';
        if (name.isNotEmpty) skills.add(name);
      } else {
        final s = item.toString();
        if (s.isNotEmpty) skills.add(s);
      }
    }
  } else if (skillsRaw is String) {
    final s = skillsRaw.trim();
    if (s.isNotEmpty) {
      skills.addAll(
        s.contains(',')
            ? s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)
            : [s],
      );
    }
  }
  final sanitized =
      filterSkillsForCvApi(sanitizeSkillsList(List<String>.from(skills))).kept;
  skills
    ..clear()
    ..addAll(sanitized);

  final experience = <Map<String, dynamic>>[];
  void addProjectLike(dynamic entry) {
    if (entry is! Map) return;
    final bullets = entry['bullets'];
    final desc = bullets is List
        ? bullets.map((b) => b.toString()).join('\n')
        : (entry['description']?.toString() ?? '');
    experience.add({
      'title': entry['title'] ?? entry['name'] ?? entry['company'] ?? '',
      'role': entry['role'] ?? '',
      'description': desc,
    });
  }

  for (final listKey in ['projects', 'experience']) {
    final list = raw[listKey];
    if (list is List) {
      for (final item in list) {
        addProjectLike(item);
      }
    }
  }

  final achievements = <String>[];
  final achRaw = raw['achievements'];
  if (achRaw is List) {
    achievements.addAll(achRaw.map((a) => a.toString()));
  }

  final userRaw = raw['user'];
  final user =
      userRaw is Map ? Map<String, dynamic>.from(userRaw) : <String, dynamic>{};

  if (user.isEmpty && raw['personal_info'] is Map) {
    final pi = Map<String, dynamic>.from(raw['personal_info'] as Map);
    user['name'] = pi['full_name'] ?? pi['name'];
    user['email'] = pi['email'];
    user['role'] = pi['title'] ?? pi['role'];
  }

  return {
    'id': raw['id']?.toString(),
    'summary': raw['summary']?.toString() ?? '',
    'skills': skills,
    'experience': experience,
    'achievements': achievements,
    'user': user,
    'generated_at': raw['generated_at'],
    'source': raw['source'],
    'design': designPrefsFromCv(raw),
  };
}

Map<String, dynamic> designPrefsFromCv(Map<String, dynamic> raw) {
  final pi = raw['personal_info'];
  if (pi is Map) {
    final m = Map<String, dynamic>.from(pi);
    final orderRaw = m['section_order'] ?? raw['section_order'];
    final orderList = orderRaw is List
        ? orderRaw.map((e) => e.toString()).toList()
        : defaultSectionOrder();
    return {
      'style': m['resume_style']?.toString() ?? 'Modern',
      'accent': m['accent_color']?.toString() ?? '#2D5FA6',
      'font_family': m['font_family']?.toString() ?? 'Default',
      'body_size': (m['body_size'] as num?)?.toDouble() ?? 12.0,
      'heading_size': (m['heading_size'] as num?)?.toDouble() ?? 18.0,
      'section_order': orderList,
      'sections': m['section_visibility'] is Map
          ? Map<String, dynamic>.from(m['section_visibility'] as Map)
          : defaultSectionVisibility(),
    };
  }
  if (raw['design'] is Map) {
    final d = Map<String, dynamic>.from(raw['design'] as Map);
    d['font_family'] ??= 'Default';
    d['body_size'] ??= 12.0;
    d['heading_size'] ??= 18.0;
    d['section_order'] ??= defaultSectionOrder();
    d['sections'] ??= defaultSectionVisibility();
    return d;
  }
  return defaultDesignPrefs();
}

Map<String, dynamic> defaultDesignPrefs() => {
      'style': 'Modern',
      'accent': '#2D5FA6',
      'font_family': 'Default',
      'body_size': 12.0,
      'heading_size': 18.0,
      'section_order': defaultSectionOrder(),
      'sections': defaultSectionVisibility(),
    };

List<String> defaultSectionOrder() => [
      'Personal Information',
      'Professional Summary',
      'Skills',
      'Experience',
      'Projects',
      'Education',
      'Certifications',
      'Languages',
      'Contact Information',
    ];

Map<String, bool> defaultSectionVisibility() => {
      'Personal Information': true,
      'Professional Summary': true,
      'Skills': true,
      'Experience': true,
      'Projects': true,
      'Education': true,
      'Certifications': true,
      'Languages': true,
      'Contact Information': true,
      // Backward compatibility keys
      'Summary': true,
      'Achievements': true,
    };

/// Parse `#RRGGBB` or `#AARRGGBB` from saved CV design prefs.
Color? colorFromHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(v);
}

Color accentColorFromDesign(
  Map<String, dynamic> design, {
  Color fallback = AppColors.primary,
}) {
  return colorFromHex(design['accent']?.toString()) ?? fallback;
}

/// Build API payload for POST /api/cv or PATCH /api/cv/<id>.
Map<String, dynamic> buildCvApiPayload({
  required ApiUser user,
  required String summary,
  required List<String> skills,
  required List<Map<String, String>> projects,
  List<String> achievements = const [],
  Map<String, dynamic>? design,
}) {
  final d = design ?? defaultDesignPrefs();
  final sections = d['sections'];
  final sectionMap = sections is Map
      ? sections.map((k, v) => MapEntry(k.toString(), v == true))
      : defaultSectionVisibility();

  final personalInfo = <String, dynamic>{
    'full_name': user.fullName.isNotEmpty ? user.fullName : user.displayName,
    'email': user.email,
    'title': user.professionalField.isNotEmpty
        ? user.professionalField
        : user.displayRole,
    'resume_style': d['style']?.toString() ?? 'Modern',
    'accent_color': d['accent']?.toString() ?? '#2D5FA6',
    'section_visibility': sectionMap,
  };

  final filtered = filterSkillsForCvApi(skills);
  final skillRows = filtered.kept
      .map((name) => {'name': name, 'level': 'Intermediate'})
      .toList();

  final projectRows = <Map<String, dynamic>>[];
  for (final p in projects) {
    final title = (p['title'] ?? '').trim();
    if (title.isEmpty) continue;
    projectRows.add({
      'name': title,
      'description': (p['description'] ?? '').trim(),
    });
  }

  return {
    'personal_info': personalInfo,
    'summary': summary.trim(),
    'skills': skillRows,
    'projects': projectRows,
    'experience': <Map<String, dynamic>>[],
    'education': <Map<String, dynamic>>[],
    'certifications': <Map<String, dynamic>>[],
    'is_public': false,
  };
}

/// Drops empty entries and single-character junk from corrupted CV data.
List<String> sanitizeSkillsList(List<String> skills) {
  final cleaned = <String>[];
  for (final raw in skills) {
    final s = raw.trim();
    if (s.length < 2) continue;
    cleaned.add(s);
  }
  return cleaned;
}

/// Skills accepted by POST/PATCH /api/cv (mirrors backend cv_validator.py).
const Set<String> _allowedCvSkills = {
  'Python',
  'JavaScript',
  'TypeScript',
  'Java',
  'C',
  'C++',
  'C#',
  'Go',
  'Rust',
  'Kotlin',
  'Swift',
  'Ruby',
  'PHP',
  'Scala',
  'R',
  'Dart',
  'Lua',
  'Perl',
  'Haskell',
  'Elixir',
  'Clojure',
  'MATLAB',
  'Shell',
  'Bash',
  'PowerShell',
  'SQL',
  'HTML',
  'CSS',
  'Objective-C',
  'Assembly',
  'React',
  'Angular',
  'Vue',
  'Svelte',
  'Next.js',
  'Nuxt.js',
  'jQuery',
  'Bootstrap',
  'TailwindCSS',
  'Sass',
  'LESS',
  'Redux',
  'Zustand',
  'Webpack',
  'Vite',
  'Figma',
  'Adobe XD',
  'Flask',
  'Django',
  'FastAPI',
  'Express',
  'NestJS',
  'Spring Boot',
  'Ruby on Rails',
  'Laravel',
  'ASP.NET',
  'Node.js',
  'Deno',
  'Bun',
  'Flutter',
  'React Native',
  'SwiftUI',
  'Jetpack Compose',
  'Xamarin',
  'Ionic',
  'Machine Learning',
  'Deep Learning',
  'TensorFlow',
  'PyTorch',
  'Keras',
  'Scikit-learn',
  'Pandas',
  'NumPy',
  'OpenCV',
  'NLP',
  'Computer Vision',
  'Data Analysis',
  'Data Science',
  'Big Data',
  'Apache Spark',
  'Hadoop',
  'Power BI',
  'Tableau',
  'AWS',
  'Azure',
  'GCP',
  'Docker',
  'Kubernetes',
  'Terraform',
  'Ansible',
  'Jenkins',
  'GitHub Actions',
  'CI/CD',
  'Linux',
  'Nginx',
  'Apache',
  'PostgreSQL',
  'MySQL',
  'MongoDB',
  'Redis',
  'SQLite',
  'Firebase',
  'Elasticsearch',
  'DynamoDB',
  'Oracle',
  'SQL Server',
  'Cassandra',
  'Neo4j',
  'Supabase',
  'Pytest',
  'Jest',
  'Selenium',
  'Cypress',
  'Playwright',
  'Penetration Testing',
  'OWASP',
  'Cryptography',
  'Agile',
  'Scrum',
  'Git',
  'GitHub',
  'GitLab',
  'Jira',
  'REST API',
  'REST APIs',
  'GraphQL',
  'gRPC',
  'WebSocket',
  'Microservices',
  'System Design',
  'Technical Writing',
  'UI/UX Design',
  'Project Management',
  'Leadership',
  'Communication',
  'Problem Solving',
  'Team Management',
  'Reliability & Consistency',
  'Teamwork & Synergy',
  'HTML/CSS',
  'Unit Testing',
  'Code Review',
  'Product Thinking',
  'Stakeholder Communication',
  'Architecture',
  'OKRs',
  'Backend Development',
  'Frontend Development',
  'Mobile App Development',
  'Full Stack Development',
  'AI Tools',
  'DevOps Engineering',
  'Cloud Engineering',
  'Software Engineering',
  'Web Development',
  'Team Leadership',
  'Cross-functional Collaboration',
  'Time Management',
  'Efficient Execution',
  'Professional Integrity',
  'High Initiative & Engagement',
};

const Map<String, String> _skillAliases = {
  'rest apis': 'REST APIs',
  'rest api': 'REST API',
  'html/css': 'HTML/CSS',
  'html': 'HTML',
  'css': 'CSS',
  'node': 'Node.js',
  'nodejs': 'Node.js',
  'node.js': 'Node.js',
  'react.js': 'React',
  'reactjs': 'React',
  'vue.js': 'Vue',
  'ts': 'TypeScript',
  'js': 'JavaScript',
  'py': 'Python',
  'ai/ml': 'Machine Learning',
  'ai': 'Machine Learning',
  'ml': 'Machine Learning',
  'k8s': 'Kubernetes',
  'postgres': 'PostgreSQL',
  'mongo': 'MongoDB',
  'github actions': 'GitHub Actions',
  'cicd': 'CI/CD',
  'ci/cd': 'CI/CD',
  'fast api': 'FastAPI',
  'spring': 'Spring Boot',
  'tailwind': 'TailwindCSS',
  'tailwind css': 'TailwindCSS',
  'backend': 'Backend Development',
  'backend development': 'Backend Development',
  'backend dev': 'Backend Development',
  'frontend': 'Frontend Development',
  'frontend development': 'Frontend Development',
  'mobile': 'Mobile App Development',
  'mobile development': 'Mobile App Development',
  'mobile app development': 'Mobile App Development',
  'full stack': 'Full Stack Development',
  'fullstack': 'Full Stack Development',
  'full-stack': 'Full Stack Development',
  'full stack development': 'Full Stack Development',
  'ai tools': 'AI Tools',
  'devops': 'DevOps Engineering',
  'software engineering': 'Software Engineering',
  'web development': 'Web Development',
};

final _safeSkillPattern = RegExp(r'^[\w][\w\s&+#./\-]{1,79}$');

String? canonicalSkillName(String raw) {
  final s = raw.trim();
  if (s.length < 2 || s.length > 80) return null;
  final key = s.toLowerCase();
  if (_skillAliases.containsKey(key)) return _skillAliases[key];
  if (_allowedCvSkills.map((e) => e.toLowerCase()).contains(key)) {
    return _allowedCvSkills.firstWhere((e) => e.toLowerCase() == key);
  }
  if (_safeSkillPattern.hasMatch(s)) return s;
  return null;
}

/// Keeps only skills the API will accept; returns names removed.
({List<String> kept, List<String> removed}) filterSkillsForCvApi(
  List<String> skills,
) {
  final kept = <String>[];
  final removed = <String>[];
  final seen = <String>{};
  for (final raw in sanitizeSkillsList(skills)) {
    final canon = canonicalSkillName(raw);
    if (canon == null) {
      removed.add(raw);
      continue;
    }
    if (seen.add(canon)) kept.add(canon);
  }
  return (kept: kept, removed: removed);
}

/// Parse edit form state from preview / saved CV.
({
  String summary,
  List<String> skills,
  List<Map<String, String>> projects,
}) editFormFromPreview(Map<String, dynamic> preview) {
  final summary = preview['summary']?.toString() ?? '';
  final rawSkills = (preview['skills'] as List?)
          ?.map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList() ??
      <String>[];
  final skills = filterSkillsForCvApi(rawSkills).kept;

  final projects = <Map<String, String>>[];
  final exp = preview['experience'];
  if (exp is List) {
    for (final item in exp) {
      if (item is! Map) continue;
      projects.add({
        'title': (item['title'] ?? '').toString(),
        'description': (item['description'] ?? '').toString(),
        'role': (item['role'] ?? '').toString(),
      });
    }
  }
  if (projects.isEmpty) {
    projects.add({'title': '', 'description': '', 'role': ''});
  }
  return (summary: summary, skills: skills, projects: projects);
}

String cvPdfFilename(Map<String, dynamic> preview, ApiUser? user) {
  final name = user?.displayName ?? user?.fullName ?? 'resume';
  final safe = name.replaceAll(RegExp(r'[^\w\-]+'), '_');
  return 'Resume_$safe.pdf';
}
