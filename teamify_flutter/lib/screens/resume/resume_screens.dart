import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/files/file_downloader.dart';
import '../../core/network/api_result.dart';
import '../../core/routes.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';
import 'resume_cv_utils.dart';

// ── In-Memory Demo Mode Draft Store ──────────────────────────────────────────
class CvDraftStore {
  static Map<String, dynamic>? _draftData;
  static Map<String, dynamic>? _draftDesign;

  static Map<String, dynamic>? get draftData => _draftData;
  static Map<String, dynamic>? get draftDesign => _draftDesign;

  static void saveDraft(
      Map<String, dynamic> data, Map<String, dynamic> design) {
    _draftData = Map<String, dynamic>.from(data);
    _draftDesign = Map<String, dynamic>.from(design);
  }

  static void clear() {
    _draftData = null;
    _draftDesign = null;
  }
}

// ── CV Start Screen ──────────────────────────────────────────────────────────
class ResumeCVStartScreen extends StatelessWidget {
  const ResumeCVStartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Resume',
          style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                SizedBox(height: 12),
                Text(
                  'CV & Resume Builder',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Build, customize, and export a professional CV tailored for your career',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ...<Map<String, dynamic>>[
            {
              'icon': Icons.edit_note,
              'title': 'CV Builder & Customizer',
              'desc':
                  'Edit sections, reorder layout, select colors and templates',
              'badge': 'Recommended',
              'route': R.resumeBuilder,
            },
            {
              'icon': Icons.visibility_outlined,
              'title': 'Preview & Export Resume',
              'desc': 'View printable document and download as PDF',
              'badge': null,
              'route': R.resumePreview,
            },
            {
              'icon': Icons.palette_outlined,
              'title': 'Quick Design Settings',
              'desc': 'Change resume theme color, font, and section visibility',
              'badge': null,
              'route': R.resumeCustomize,
            },
          ].map(
            (o) => GestureDetector(
              onTap: () => Navigator.pushNamed(context, o['route'] as String),
              child: TCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        o['icon'] as IconData,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                o['title'] as String,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: onSurface,
                                ),
                              ),
                              if (o['badge'] != null) ...[
                                const SizedBox(width: 8),
                                TChip(
                                  label: o['badge'] as String,
                                  bg: AppColors.success.withValues(alpha: 0.1),
                                  textColor: AppColors.success,
                                  fontSize: 10,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            o['desc'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared CV Builder Screen ─────────────────────────────────────────────────
class ResumeBuilderScreen extends StatefulWidget {
  const ResumeBuilderScreen({super.key});

  @override
  State<ResumeBuilderScreen> createState() => _ResumeBuilderScreenState();
}

class _ResumeBuilderScreenState extends State<ResumeBuilderScreen> {
  int _activeTab = 0; // 0: Content, 1: Design & Style, 2: Live Preview
  bool _loading = true;
  bool _generating = false;

  // Personal Information
  final _nameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _portfolioCtrl = TextEditingController();

  // Summary & Contact
  final _summaryCtrl = TextEditingController();
  final _skillInputCtrl = TextEditingController();

  // Itemized lists
  List<String> _skills = [];
  List<Map<String, String>> _experience = [];
  List<Map<String, String>> _projects = [];
  List<Map<String, String>> _education = [];
  List<Map<String, String>> _certifications = [];
  List<Map<String, String>> _languages = [];

  // Design Options
  String _style = 'Modern'; // Modern, Classic, Minimal
  Color _accentColor = AppColors.primary;
  final _customHexCtrl = TextEditingController(text: '#2D5FA6');
  String _fontFamily = 'Default';
  double _bodyFontSize = 12.0;
  double _headingFontSize = 18.0;

  List<String> _sectionOrder = defaultSectionOrder();
  Map<String, bool> _sectionVisibility = defaultSectionVisibility();

  static final List<Color> _presetColors = [
    AppColors.primary,
    const Color(0xFF8B5CF6), // Purple
    const Color(0xFFEC4899), // Pink
    const Color(0xFF10B981), // Emerald
    const Color(0xFFF59E0B), // Amber
    const Color(0xFF3B82F6), // Indigo
    const Color(0xFF64748B), // Slate
    const Color(0xFFDC2626), // Red
  ];

  static final List<String> _fontOptions = [
    'Default',
    'Roboto',
    'Poppins',
    'Inter',
    'Montserrat',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCvData());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _portfolioCtrl.dispose();
    _summaryCtrl.dispose();
    _skillInputCtrl.dispose();
    _customHexCtrl.dispose();
    super.dispose();
  }

  Future<void> _initCvData() async {
    final user = context.read<SessionController>().currentUser;
    final draftData = CvDraftStore.draftData;
    final draftDesign = CvDraftStore.draftDesign;

    if (draftData != null) {
      _applyCvDataMap(draftData);
      if (draftDesign != null) _applyDesignMap(draftDesign);
      setState(() => _loading = false);
      return;
    }

    if (user != null) {
      _nameCtrl.text =
          user.fullName.isNotEmpty ? user.fullName : user.displayName;
      _titleCtrl.text = user.professionalField.isNotEmpty
          ? user.professionalField
          : user.displayRole;
      _emailCtrl.text = user.email;
      _phoneCtrl.text = '+1 (555) 019-2834';
      _locationCtrl.text = user.major.isNotEmpty ? user.major : 'Remote';
      _portfolioCtrl.text = 'github.com/${user.displayName}';
      _summaryCtrl.text = user.bio.isNotEmpty
          ? user.bio
          : 'Dedicated software professional focused on high quality application design and effective team collaboration.';
      _skills = List<String>.from(user.skills);
      if (_skills.isEmpty) {
        _skills = ['Flutter', 'Dart', 'React', 'TypeScript', 'UI/UX Design'];
      }
      _experience = [
        {
          'role': 'Senior Software Developer',
          'company': 'Tech Corp',
          'duration': '2024 - Present',
          'description':
              'Leading cross-functional feature delivery and mobile application architecture.',
        },
      ];
      _projects = [
        {
          'title': 'Teamify Platform',
          'role': 'Frontend Lead',
          'description':
              'Collaborative workspace suite built with Flutter Web and real-time backend services.',
          'link': 'github.com/teamify/app',
        },
      ];
      _education = [
        {
          'degree': 'B.S. Computer Science',
          'institution': 'State University',
          'year': '2020 - 2024',
        },
      ];
      _certifications = [
        {
          'name': 'Certified Mobile Developer',
          'issuer': 'Tech Institute',
          'year': '2025',
        },
      ];
      _languages = [
        {'language': 'English', 'proficiency': 'Native / Fluent'},
        {'language': 'Spanish', 'proficiency': 'Intermediate'},
      ];
    }

    setState(() => _loading = false);
  }

  void _applyCvDataMap(Map<String, dynamic> data) {
    final userMap =
        data['user'] is Map ? Map<String, dynamic>.from(data['user']) : {};
    _nameCtrl.text = userMap['name']?.toString() ?? _nameCtrl.text;
    _titleCtrl.text = userMap['role']?.toString() ?? _titleCtrl.text;
    _emailCtrl.text = userMap['email']?.toString() ?? _emailCtrl.text;
    _phoneCtrl.text = userMap['phone']?.toString() ?? _phoneCtrl.text;
    _locationCtrl.text = userMap['location']?.toString() ?? _locationCtrl.text;
    _portfolioCtrl.text =
        userMap['portfolio']?.toString() ?? _portfolioCtrl.text;
    _summaryCtrl.text = data['summary']?.toString() ?? _summaryCtrl.text;

    if (data['skills'] is List) {
      _skills = (data['skills'] as List).map((e) => e.toString()).toList();
    }
    if (data['experience'] is List) {
      _experience = (data['experience'] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    }
    if (data['projects'] is List) {
      _projects = (data['projects'] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    }
    if (data['education'] is List) {
      _education = (data['education'] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    }
    if (data['certifications'] is List) {
      _certifications = (data['certifications'] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    }
    if (data['languages'] is List) {
      _languages = (data['languages'] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    }
  }

  void _applyDesignMap(Map<String, dynamic> d) {
    _style = d['style']?.toString() ?? 'Modern';
    final accentHex = d['accent']?.toString() ?? '#2D5FA6';
    _accentColor = colorFromHex(accentHex) ?? AppColors.primary;
    _customHexCtrl.text = accentHex;
    _fontFamily = d['font_family']?.toString() ?? 'Default';
    _bodyFontSize = (d['body_size'] as num?)?.toDouble() ?? 12.0;
    _headingFontSize = (d['heading_size'] as num?)?.toDouble() ?? 18.0;

    if (d['section_order'] is List) {
      _sectionOrder =
          (d['section_order'] as List).map((e) => e.toString()).toList();
    }
    if (d['sections'] is Map) {
      final secMap = Map<String, dynamic>.from(d['sections']);
      _sectionVisibility = secMap.map((k, v) => MapEntry(k, v == true));
    }
  }

  Map<String, dynamic> _buildCvDataPayload() {
    return {
      'user': {
        'name': _nameCtrl.text,
        'role': _titleCtrl.text,
        'email': _emailCtrl.text,
        'phone': _phoneCtrl.text,
        'location': _locationCtrl.text,
        'portfolio': _portfolioCtrl.text,
      },
      'summary': _summaryCtrl.text,
      'skills': _skills,
      'experience': _experience,
      'projects': _projects,
      'education': _education,
      'certifications': _certifications,
      'languages': _languages,
    };
  }

  Map<String, dynamic> _buildDesignPayload() {
    return {
      'style': _style,
      'accent': _colorToHex(_accentColor),
      'font_family': _fontFamily,
      'body_size': _bodyFontSize,
      'heading_size': _headingFontSize,
      'section_order': _sectionOrder,
      'sections': _sectionVisibility,
    };
  }

  String _colorToHex(Color c) {
    final rgb = c.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _syncDraftState() {
    CvDraftStore.saveDraft(_buildCvDataPayload(), _buildDesignPayload());
  }

  void _generateLocalAiSummary() {
    final user = context.read<SessionController>().currentUser;
    final userType = (user?.userType ?? '').toLowerCase();
    final roleStr = (user?.role ?? '').toLowerCase();
    final isStudent = userType == 'student' || roleStr.contains('student');

    final title = _titleCtrl.text.trim();
    final major = user?.major.trim() ?? '';
    final skillsList = _skills.where((s) => s.trim().isNotEmpty).toList();
    final expList = _experience
        .where((e) =>
            (e['role'] ?? '').trim().isNotEmpty ||
            (e['company'] ?? '').trim().isNotEmpty)
        .toList();
    final projList =
        _projects.where((p) => (p['title'] ?? '').trim().isNotEmpty).toList();
    final certList = _certifications
        .where((c) => (c['name'] ?? '').trim().isNotEmpty)
        .toList();

    final hasAnyData = title.isNotEmpty ||
        major.isNotEmpty ||
        skillsList.isNotEmpty ||
        expList.isNotEmpty ||
        projList.isNotEmpty ||
        certList.isNotEmpty;

    if (!hasAnyData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please complete your CV sections first before generating an AI summary.',
          ),
        ),
      );
      return;
    }

    final parts = <String>[];

    if (isStudent) {
      if (major.isNotEmpty) {
        parts.add(
          'Motivated $major student pursuing excellence in software development, technical innovation, and project execution.',
        );
      } else if (title.isNotEmpty) {
        parts.add(
          'Dedicated $title student focused on building practical engineering solutions and expanding core capabilities.',
        );
      } else {
        parts.add(
          'Enthusiastic technology student committed to applying technical concepts through hands-on project work.',
        );
      }
    } else {
      if (title.isNotEmpty) {
        parts.add(
          'Results-driven $title with a focus on delivering high-quality, scalable digital solutions.',
        );
      } else {
        parts.add(
          'Versatile freelance software professional specializing in modern application development, user experience, and client success.',
        );
      }
    }

    if (skillsList.isNotEmpty) {
      final topSkills = skillsList.take(4).join(', ');
      parts.add(
        'Proficient in $topSkills with strong problem-solving skills and technical versatility.',
      );
    }

    if (expList.isNotEmpty) {
      final firstExp = expList.first;
      final expRole = (firstExp['role'] ?? '').isNotEmpty
          ? firstExp['role']!
          : 'Software Developer';
      final company = firstExp['company'] ?? '';
      if (company.isNotEmpty) {
        parts.add('Brings hands-on experience as a $expRole at $company.');
      } else {
        parts.add(
            'Demonstrated professional growth through work as a $expRole.');
      }
    } else if (projList.isNotEmpty) {
      final firstProj = projList.first['title'] ?? 'featured applications';
      parts.add('Successfully engineered key projects including $firstProj.');
    }

    if (certList.isNotEmpty) {
      final certName = certList.first['name'] ?? '';
      if (certName.isNotEmpty) {
        parts.add('Holds certifications in $certName.');
      }
    }

    final generated = parts.join(' ');
    setState(() {
      _summaryCtrl.text = generated;
      _syncDraftState();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI Professional Summary generated successfully!'),
      ),
    );
  }

  Future<void> _autoFillWithAI() async {
    setState(() => _generating = true);
    try {
      final result = await context.read<AppServices>().ai.buildCVWithAI();
      if (!mounted) return;
      setState(() => _generating = false);
      if (result.isSuccess && result.data != null) {
        final preview = normalizeCvForPreview(result.data!);
        _applyCvDataMap(preview);
        _syncDraftState();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('CV populated with AI Profile Insights!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Could not auto-fill with AI.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Auto-fill note: Using local profile data. ($e)')),
      );
    }
  }

  void _addSkill() {
    final s = _skillInputCtrl.text.trim();
    if (s.isEmpty) return;
    if (!_skills.contains(s)) {
      setState(() {
        _skills.add(s);
        _skillInputCtrl.clear();
      });
      _syncDraftState();
    }
  }

  void _exportCv() {
    _syncDraftState();
    final data = _buildCvDataPayload();
    final design = _buildDesignPayload();
    final user = context.read<SessionController>().currentUser;
    final filename = cvPdfFilename(data, user);

    // TODO: Real backend PDF export API integration (POST /api/cv/export)
    // For Demo Mode frontend export, prepare PDF file bytes & open Export Success Screen
    saveDownloadedBytes(
      filename: filename,
      bytes: Uint8List.fromList('PDF_CV_EXPORT_DEMO_DATA'.codeUnits),
      mimeType: 'application/pdf',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CV prepared successfully')),
    );

    Navigator.pushNamed(
      context,
      R.resumeExportSuccess,
      arguments: {
        'filename': filename,
        'cv_data': data,
        'design': design,
      },
    );
  }

  void _openFullPreviewModal() {
    _syncDraftState();
    final data = _buildCvDataPayload();
    final design = _buildDesignPayload();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (_, scroll) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                AppBar(
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  title: const Text('Printable CV Preview'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _exportCv();
                      },
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Export CV'),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: CvPaperPreview(
                            data: data,
                            design: design,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    border: Border(
                        top: BorderSide(color: Theme.of(ctx).dividerColor)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Back to Edit'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _exportCv();
                          },
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Export CV'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 850;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'CV Builder & Customizer',
          style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
        ),
        actions: [
          IconButton(
            icon: _generating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, color: AppColors.primary),
            tooltip: 'Auto-fill with AI Profile Data',
            onPressed: _generating ? null : _autoFillWithAI,
          ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'Preview Printable CV',
            onPressed: _openFullPreviewModal,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isWide
              ? Row(
                  children: [
                    SizedBox(
                      width: 440,
                      child: Column(
                        children: [
                          _buildTabBar(),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: _activeTab == 0
                                  ? _buildContentEditor()
                                  : _buildDesignCustomizer(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Container(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Center(
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 780),
                                child: CvPaperPreview(
                                  data: _buildCvDataPayload(),
                                  design: _buildDesignPayload(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildTabBar(),
                    Expanded(
                      child: IndexedStack(
                        index: _activeTab,
                        children: [
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _buildContentEditor(),
                          ),
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: _buildDesignCustomizer(),
                          ),
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              CvPaperPreview(
                                data: _buildCvDataPayload(),
                                design: _buildDesignPayload(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          border:
              Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openFullPreviewModal,
                icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                label: const Text('Full Preview'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _exportCv,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Export CV'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 850;
    final tabs = isWide
        ? ['Content Sections', 'Design & Style']
        : ['Content', 'Design', 'Live Preview'];

    return Container(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final sel = _activeTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.primary
                      : (isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tabs[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: sel
                        ? Colors.white
                        : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildContentEditor() {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      children: [
        // Personal Information
        _editorAccordion(
          title: 'Personal Information',
          icon: Icons.person_outline,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name *'),
              onChanged: (_) => setState(_syncDraftState),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _titleCtrl,
              decoration:
                  const InputDecoration(labelText: 'Professional Title *'),
              onChanged: (_) => setState(_syncDraftState),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email *'),
              onChanged: (_) => setState(_syncDraftState),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              onChanged: (_) => setState(_syncDraftState),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _locationCtrl,
              decoration:
                  const InputDecoration(labelText: 'Location / Address'),
              onChanged: (_) => setState(_syncDraftState),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _portfolioCtrl,
              decoration: const InputDecoration(
                  labelText: 'Portfolio / GitHub / Website'),
              onChanged: (_) => setState(_syncDraftState),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Professional Summary (Always Visible Card)
        Builder(
          builder: (context) {
            final session = context.watch<SessionController>();
            final user = session.currentUser;
            final userType = (user?.userType ?? '').toLowerCase();
            final roleStr = (user?.role ?? '').toLowerCase();
            final displayRole = (user?.displayRole ?? '').toLowerCase();

            final isStudentOrFreelancer = userType == 'student' ||
                userType == 'freelancer' ||
                roleStr.contains('student') ||
                roleStr.contains('freelance') ||
                displayRole.contains('student') ||
                displayRole.contains('freelance') ||
                (AppConfig.isDemoMode &&
                    !userType.contains('admin') &&
                    !userType.contains('recruiter') &&
                    !roleStr.contains('admin'));

            return TCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.description_outlined,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Professional Summary',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      if (isStudentOrFreelancer)
                        ElevatedButton.icon(
                          onPressed: _generateLocalAiSummary,
                          icon: const Icon(Icons.auto_awesome,
                              size: 16, color: Colors.white),
                          label: Text(
                            _summaryCtrl.text.trim().isEmpty
                                ? 'Generate AI Summary'
                                : 'Regenerate',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _summaryCtrl,
                    maxLines: 4,
                    onChanged: (_) => setState(_syncDraftState),
                    decoration: const InputDecoration(
                      hintText:
                          'Summarize your expertise and key qualifications...',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Skills
        _editorAccordion(
          title: 'Skills',
          icon: Icons.auto_awesome_outlined,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _skillInputCtrl,
                    decoration: const InputDecoration(labelText: 'Add Skill'),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ElevatedButton(
                    onPressed: _addSkill,
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _skills
                  .map(
                    (s) => Chip(
                      label: Text(s),
                      onDeleted: () {
                        setState(() => _skills.remove(s));
                        _syncDraftState();
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Experience
        _editorAccordion(
          title: 'Work Experience',
          icon: Icons.work_outline,
          children: [
            ..._experience.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Role #${idx + 1}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.error, size: 20),
                          onPressed: () {
                            setState(() => _experience.removeAt(idx));
                            _syncDraftState();
                          },
                        ),
                      ],
                    ),
                    TextFormField(
                      initialValue: item['role'],
                      decoration: const InputDecoration(labelText: 'Job Title'),
                      onChanged: (v) {
                        item['role'] = v;
                        _syncDraftState();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: item['company'],
                      decoration: const InputDecoration(labelText: 'Company'),
                      onChanged: (v) {
                        item['company'] = v;
                        _syncDraftState();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: item['duration'],
                      decoration: const InputDecoration(
                          labelText: 'Duration (e.g. 2023 - Present)'),
                      onChanged: (v) {
                        item['duration'] = v;
                        _syncDraftState();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: item['description'],
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                      onChanged: (v) {
                        item['description'] = v;
                        _syncDraftState();
                      },
                    ),
                  ],
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _experience.add({
                    'role': 'Software Role',
                    'company': 'Company Name',
                    'duration': '2024 - Present',
                    'description': 'Key responsibilities & accomplishments',
                  });
                });
                _syncDraftState();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Experience'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Projects
        _editorAccordion(
          title: 'Projects',
          icon: Icons.folder_outlined,
          children: [
            ..._projects.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Project #${idx + 1}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.error, size: 20),
                          onPressed: () {
                            setState(() => _projects.removeAt(idx));
                            _syncDraftState();
                          },
                        ),
                      ],
                    ),
                    TextFormField(
                      initialValue: item['title'],
                      decoration:
                          const InputDecoration(labelText: 'Project Name'),
                      onChanged: (v) {
                        item['title'] = v;
                        _syncDraftState();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: item['role'],
                      decoration: const InputDecoration(labelText: 'Your Role'),
                      onChanged: (v) {
                        item['role'] = v;
                        _syncDraftState();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: item['description'],
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                      onChanged: (v) {
                        item['description'] = v;
                        _syncDraftState();
                      },
                    ),
                  ],
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _projects.add({
                    'title': 'New Project',
                    'role': 'Developer',
                    'description': 'Project details and technical highlights',
                  });
                });
                _syncDraftState();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Project'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Education
        _editorAccordion(
          title: 'Education',
          icon: Icons.school_outlined,
          children: [
            ..._education.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Education #${idx + 1}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: onSurface)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.error, size: 20),
                          onPressed: () {
                            setState(() => _education.removeAt(idx));
                            _syncDraftState();
                          },
                        ),
                      ],
                    ),
                    TextFormField(
                      initialValue: item['degree'],
                      decoration: const InputDecoration(
                          labelText: 'Degree / Certificate'),
                      onChanged: (v) {
                        item['degree'] = v;
                        _syncDraftState();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: item['institution'],
                      decoration: const InputDecoration(
                          labelText: 'School / University'),
                      onChanged: (v) {
                        item['institution'] = v;
                        _syncDraftState();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: item['year'],
                      decoration:
                          const InputDecoration(labelText: 'Graduation Year'),
                      onChanged: (v) {
                        item['year'] = v;
                        _syncDraftState();
                      },
                    ),
                  ],
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _education.add({
                    'degree': 'Degree Title',
                    'institution': 'University Name',
                    'year': '2024',
                  });
                });
                _syncDraftState();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Education'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Certifications
        _editorAccordion(
          title: 'Certifications',
          icon: Icons.verified_outlined,
          children: [
            ..._certifications.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: item['name'],
                      decoration:
                          const InputDecoration(labelText: 'Certification'),
                      onChanged: (v) {
                        item['name'] = v;
                        _syncDraftState();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: item['issuer'],
                      decoration: const InputDecoration(labelText: 'Issuer'),
                      onChanged: (v) {
                        item['issuer'] = v;
                        _syncDraftState();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.error),
                    onPressed: () {
                      setState(() => _certifications.removeAt(idx));
                      _syncDraftState();
                    },
                  ),
                ],
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _certifications
                      .add({'name': 'New Certificate', 'issuer': 'Issuer Org'});
                });
                _syncDraftState();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Certification'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Languages
        _editorAccordion(
          title: 'Languages',
          icon: Icons.language_outlined,
          children: [
            ..._languages.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: item['language'],
                      decoration: const InputDecoration(labelText: 'Language'),
                      onChanged: (v) {
                        item['language'] = v;
                        _syncDraftState();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: item['proficiency'],
                      decoration:
                          const InputDecoration(labelText: 'Proficiency'),
                      onChanged: (v) {
                        item['proficiency'] = v;
                        _syncDraftState();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.error),
                    onPressed: () {
                      setState(() => _languages.removeAt(idx));
                      _syncDraftState();
                    },
                  ),
                ],
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _languages
                      .add({'language': 'Language', 'proficiency': 'Fluent'});
                });
                _syncDraftState();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Language'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesignCustomizer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Template Selection
        TCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Template Selection',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: onSurface),
              ),
              const SizedBox(height: 12),
              Row(
                children: ['Modern', 'Classic', 'Minimal'].map((tpl) {
                  final sel = _style == tpl;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _style = tpl);
                        _syncDraftState();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : (isDark
                                  ? const Color(0xFF1E293B)
                                  : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel
                                ? AppColors.primary
                                : Theme.of(context).dividerColor,
                            width: sel ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Visual Thumbnail
                            Container(
                              height: 60,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: sel
                                        ? AppColors.primary
                                        : Theme.of(context).dividerColor),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                crossAxisAlignment: tpl == 'Classic'
                                    ? CrossAxisAlignment.center
                                    : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 6,
                                    width: tpl == 'Classic' ? 30 : 40,
                                    color: _accentColor,
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                      height: 3,
                                      width: 50,
                                      color: Colors.grey[400]),
                                  const SizedBox(height: 3),
                                  Container(
                                      height: 3,
                                      width: 35,
                                      color: Colors.grey[300]),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tpl,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    sel ? FontWeight.bold : FontWeight.normal,
                                color: sel ? AppColors.primary : onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Color Customization
        TCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accent Color',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: onSurface),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ..._presetColors.map((c) {
                    final sel = _accentColor == c;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _accentColor = c;
                          _customHexCtrl.text = _colorToHex(c);
                        });
                        _syncDraftState();
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: sel ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                      color: c.withValues(alpha: 0.5),
                                      blurRadius: 6)
                                ]
                              : null,
                        ),
                        child: sel
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Custom Hex: ',
                      style: TextStyle(color: onSurface, fontSize: 13)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    height: 38,
                    child: TextFormField(
                      controller: _customHexCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (hex) {
                        final parsed = colorFromHex(hex);
                        if (parsed != null) {
                          setState(() => _accentColor = parsed);
                          _syncDraftState();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Font Customization
        TCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Typography',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: onSurface),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _fontFamily,
                decoration: const InputDecoration(labelText: 'Font Family'),
                items: _fontOptions
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _fontFamily = v);
                    _syncDraftState();
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text('Heading Size: ${_headingFontSize.round()}pt',
                        style: TextStyle(fontSize: 12, color: onSurface)),
                  ),
                  Slider(
                    value: _headingFontSize,
                    min: 14.0,
                    max: 26.0,
                    divisions: 12,
                    onChanged: (v) {
                      setState(() => _headingFontSize = v);
                      _syncDraftState();
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('Body Size: ${_bodyFontSize.round()}pt',
                        style: TextStyle(fontSize: 12, color: onSurface)),
                  ),
                  Slider(
                    value: _bodyFontSize,
                    min: 10.0,
                    max: 16.0,
                    divisions: 6,
                    onChanged: (v) {
                      setState(() => _bodyFontSize = v);
                      _syncDraftState();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. Rearrange & Hide/Show Sections
        TCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rearrange & Hide Sections',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'Use up/down buttons to reorder sections. Toggle switches to show/hide sections.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              ..._sectionOrder.asMap().entries.map((entry) {
                final idx = entry.key;
                final sec = entry.value;
                final isVisible = _sectionVisibility[sec] ?? true;
                final isRequired = sec == 'Personal Information';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      // Reorder controls
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                            onPressed: idx > 0
                                ? () {
                                    setState(() {
                                      final item = _sectionOrder.removeAt(idx);
                                      _sectionOrder.insert(idx - 1, item);
                                    });
                                    _syncDraftState();
                                  }
                                : null,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon:
                                const Icon(Icons.keyboard_arrow_down, size: 18),
                            onPressed: idx < _sectionOrder.length - 1
                                ? () {
                                    setState(() {
                                      final item = _sectionOrder.removeAt(idx);
                                      _sectionOrder.insert(idx + 1, item);
                                    });
                                    _syncDraftState();
                                  }
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sec,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isVisible ? onSurface : Colors.grey,
                          ),
                        ),
                      ),
                      Switch(
                        value: isVisible,
                        onChanged: isRequired
                            ? null
                            : (val) {
                                setState(() => _sectionVisibility[sec] = val);
                                _syncDraftState();
                              },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editorAccordion({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return TCard(
      child: ExpansionTile(
        initiallyExpanded:
            title.contains('Personal') || title.contains('Summary'),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15, color: onSurface),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 10),
        children: children,
      ),
    );
  }
}

// ── Live Rendered CV Paper Preview ───────────────────────────────────────────
class CvPaperPreview extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic> design;

  const CvPaperPreview({
    super.key,
    required this.data,
    required this.design,
  });

  @override
  Widget build(BuildContext context) {
    final user =
        data['user'] is Map ? Map<String, dynamic>.from(data['user']) : {};
    final name = user['name']?.toString() ?? 'John Doe';
    final role = user['role']?.toString() ?? 'Software Engineer';
    final email = user['email']?.toString() ?? '';
    final phone = user['phone']?.toString() ?? '';
    final location = user['location']?.toString() ?? '';
    final portfolio = user['portfolio']?.toString() ?? '';

    final summary = data['summary']?.toString() ?? '';
    final skills =
        (data['skills'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final experience =
        (data['experience'] as List?)?.whereType<Map>().toList() ?? [];
    final projects =
        (data['projects'] as List?)?.whereType<Map>().toList() ?? [];
    final education =
        (data['education'] as List?)?.whereType<Map>().toList() ?? [];
    final certs =
        (data['certifications'] as List?)?.whereType<Map>().toList() ?? [];
    final languages =
        (data['languages'] as List?)?.whereType<Map>().toList() ?? [];

    final style = design['style']?.toString() ?? 'Modern';
    final accentHex = design['accent']?.toString() ?? '#2D5FA6';
    final accent = colorFromHex(accentHex) ?? AppColors.primary;
    final fontFamily = design['font_family']?.toString() ?? 'Default';
    final bodySize = (design['body_size'] as num?)?.toDouble() ?? 12.0;
    final headingSize = (design['heading_size'] as num?)?.toDouble() ?? 18.0;

    final order = design['section_order'] is List
        ? (design['section_order'] as List).map((e) => e.toString()).toList()
        : defaultSectionOrder();
    final visibility = design['sections'] is Map
        ? Map<String, dynamic>.from(design['sections'])
        : defaultSectionVisibility();

    TextStyle resolveFont({
      double? fontSize,
      FontWeight? fontWeight,
      Color? color,
    }) {
      return TextStyle(
        fontSize: fontSize ?? bodySize,
        fontWeight: fontWeight ?? FontWeight.normal,
        color: color ?? const Color(0xFF1E293B),
        fontFamily: fontFamily != 'Default' ? fontFamily : null,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          if (style == 'Modern')
            Container(
              padding: const EdgeInsets.all(24),
              color: accent.withValues(alpha: 0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: resolveFont(
                      fontSize: headingSize + 4,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  Text(
                    role,
                    style: resolveFont(
                      fontSize: bodySize + 2,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (email.isNotEmpty)
                        Text('✉ $email',
                            style: resolveFont(fontSize: bodySize - 1)),
                      if (phone.isNotEmpty)
                        Text('📞 $phone',
                            style: resolveFont(fontSize: bodySize - 1)),
                      if (location.isNotEmpty)
                        Text('📍 $location',
                            style: resolveFont(fontSize: bodySize - 1)),
                    ],
                  ),
                ],
              ),
            )
          else if (style == 'Classic')
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                children: [
                  Text(
                    name.toUpperCase(),
                    style: resolveFont(
                      fontSize: headingSize + 2,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    role,
                    style: resolveFont(
                      fontSize: bodySize + 1,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF475569),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [email, phone, location, portfolio]
                        .where((s) => s.isNotEmpty)
                        .join('  |  '),
                    style: resolveFont(
                        fontSize: bodySize - 1, color: const Color(0xFF64748B)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Divider(color: accent, thickness: 1.5),
                ],
              ),
            )
          else
            // Minimal
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: resolveFont(
                      fontSize: headingSize + 2,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  Text(
                    role,
                    style: resolveFont(
                      fontSize: bodySize + 1,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [email, phone, location]
                        .where((s) => s.isNotEmpty)
                        .join('  •  '),
                    style: resolveFont(
                        fontSize: bodySize - 1, color: const Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),

          // Body Content Sections
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: order.map((sectionName) {
                if (visibility[sectionName] == false) {
                  return const SizedBox.shrink();
                }

                Widget sectionWidget;
                switch (sectionName) {
                  case 'Personal Information':
                    sectionWidget = style == 'Modern'
                        ? const SizedBox.shrink()
                        : const SizedBox.shrink();
                    break;
                  case 'Professional Summary':
                  case 'Summary':
                    if (summary.isEmpty) return const SizedBox.shrink();
                    sectionWidget = Text(summary, style: resolveFont());
                    break;
                  case 'Skills':
                    if (skills.isEmpty) return const SizedBox.shrink();
                    sectionWidget = Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: skills
                          .map(
                            (s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s,
                                style: resolveFont(
                                  fontSize: bodySize - 1,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                    break;
                  case 'Experience':
                    if (experience.isEmpty) return const SizedBox.shrink();
                    sectionWidget = Column(
                      children: experience.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item['role']?.toString() ?? '',
                                    style: resolveFont(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    item['duration']?.toString() ?? '',
                                    style: resolveFont(
                                      fontSize: bodySize - 1,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                item['company']?.toString() ?? '',
                                style: resolveFont(
                                  fontSize: bodySize - 1,
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if ((item['description']?.toString() ?? '')
                                  .isNotEmpty)
                                Text(
                                  item['description'].toString(),
                                  style: resolveFont(fontSize: bodySize - 1),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                    break;
                  case 'Projects':
                    if (projects.isEmpty) return const SizedBox.shrink();
                    sectionWidget = Column(
                      children: projects.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title']?.toString() ?? '',
                                style: resolveFont(fontWeight: FontWeight.bold),
                              ),
                              if ((item['role']?.toString() ?? '').isNotEmpty)
                                Text(
                                  'Role: ${item['role']}',
                                  style: resolveFont(
                                    fontSize: bodySize - 1,
                                    color: accent,
                                  ),
                                ),
                              if ((item['description']?.toString() ?? '')
                                  .isNotEmpty)
                                Text(
                                  item['description'].toString(),
                                  style: resolveFont(fontSize: bodySize - 1),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                    break;
                  case 'Education':
                    if (education.isEmpty) return const SizedBox.shrink();
                    sectionWidget = Column(
                      children: education.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['degree']?.toString() ?? '',
                                    style: resolveFont(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    item['institution']?.toString() ?? '',
                                    style: resolveFont(
                                      fontSize: bodySize - 1,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                item['year']?.toString() ?? '',
                                style: resolveFont(fontSize: bodySize - 1),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                    break;
                  case 'Certifications':
                    if (certs.isEmpty) return const SizedBox.shrink();
                    sectionWidget = Column(
                      children: certs.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(Icons.verified, size: 14, color: accent),
                              const SizedBox(width: 6),
                              Text(
                                item['name']?.toString() ?? '',
                                style: resolveFont(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(${item['issuer'] ?? ''})',
                                style: resolveFont(
                                  fontSize: bodySize - 1,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                    break;
                  case 'Languages':
                    if (languages.isEmpty) return const SizedBox.shrink();
                    sectionWidget = Wrap(
                      spacing: 12,
                      children: languages
                          .map(
                            (item) => Text(
                              '${item['language']} (${item['proficiency']})',
                              style: resolveFont(fontSize: bodySize - 1),
                            ),
                          )
                          .toList(),
                    );
                    break;
                  case 'Contact Information':
                    sectionWidget = Wrap(
                      spacing: 12,
                      children: [
                        if (email.isNotEmpty)
                          Text('✉ $email',
                              style: resolveFont(fontSize: bodySize - 1)),
                        if (phone.isNotEmpty)
                          Text('📞 $phone',
                              style: resolveFont(fontSize: bodySize - 1)),
                        if (portfolio.isNotEmpty)
                          Text('🌐 $portfolio',
                              style: resolveFont(fontSize: bodySize - 1)),
                      ],
                    );
                    break;
                  default:
                    sectionWidget = const SizedBox.shrink();
                }

                if (sectionWidget is SizedBox && sectionWidget.child == null) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (style == 'Modern') ...[
                            Container(width: 4, height: 16, color: accent),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            sectionName.toUpperCase(),
                            style: resolveFont(
                              fontSize: headingSize - 4,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Divider(
                          color: accent.withValues(alpha: 0.3), thickness: 1),
                      const SizedBox(height: 8),
                      sectionWidget,
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Resume Preview Screen ────────────────────────────────────────────────────
class ResumePreviewScreen extends StatefulWidget {
  const ResumePreviewScreen({super.key});

  @override
  State<ResumePreviewScreen> createState() => _ResumePreviewScreenState();
}

class _ResumePreviewScreenState extends State<ResumePreviewScreen> {
  Map<String, dynamic>? _cvData;
  Map<String, dynamic> _design = defaultDesignPrefs();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCV());
  }

  Future<void> _loadCV() async {
    final draftData = CvDraftStore.draftData;
    final draftDesign = CvDraftStore.draftDesign;

    if (draftData != null) {
      setState(() {
        _cvData = draftData;
        if (draftDesign != null) _design = draftDesign;
        _loading = false;
      });
      return;
    }

    final svc = context.read<AppServices>();
    try {
      final cvs = await svc.cvs.listCVs(forceRefresh: true).unwrap();
      if (!mounted) return;
      if (cvs.isNotEmpty) {
        final row = cvs.first.data;
        final preview = normalizeCvForPreview(row);
        setState(() {
          _cvData = preview;
          _design = designPrefsFromCv(row);
          _loading = false;
        });
        return;
      }
    } catch (_) {}

    final user = context.read<SessionController>().currentUser;
    final fallbackUser = user != null
        ? {
            'name': user.fullName.isNotEmpty ? user.fullName : user.displayName,
            'role': user.professionalField.isNotEmpty
                ? user.professionalField
                : user.displayRole,
            'email': user.email,
          }
        : {
            'name': 'Alex Chen',
            'role': 'Senior Software Developer',
            'email': 'alex.chen@example.com'
          };

    setState(() {
      _cvData = {
        'user': fallbackUser,
        'summary':
            'Experienced developer skilled in building high performance mobile and web applications.',
        'skills': ['Flutter', 'Dart', 'React', 'TypeScript', 'Node.js'],
        'experience': [
          {
            'role': 'Senior Developer',
            'company': 'Tech Corp',
            'duration': '2024 - Present',
            'description': 'Leading team innovation and feature releases.',
          }
        ],
      };
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Resume Preview',
          style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.pushNamed(context, R.resumeBuilder),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                CvPaperPreview(
                  data: _cvData ?? {},
                  design: _design,
                ),
              ],
            ),
    );
  }
}

// ── Resume Customize Screen ──────────────────────────────────────────────────
class ResumeCustomizeScreen extends StatefulWidget {
  const ResumeCustomizeScreen({super.key});

  @override
  State<ResumeCustomizeScreen> createState() => _ResumeCustomizeScreenState();
}

class _ResumeCustomizeScreenState extends State<ResumeCustomizeScreen> {
  @override
  Widget build(BuildContext context) {
    return const ResumeBuilderScreen();
  }
}

// ── Resume Edit Content Screen ───────────────────────────────────────────────
class ResumeEditContentScreen extends StatefulWidget {
  const ResumeEditContentScreen({super.key});

  @override
  State<ResumeEditContentScreen> createState() =>
      _ResumeEditContentScreenState();
}

class _ResumeEditContentScreenState extends State<ResumeEditContentScreen> {
  @override
  Widget build(BuildContext context) {
    return const ResumeBuilderScreen();
  }
}

// ── Export Success Screen ────────────────────────────────────────────────────
class ResumeExportSuccessScreen extends StatelessWidget {
  const ResumeExportSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final filename = args is Map
        ? (args['filename']?.toString() ?? 'Resume_Alex_Chen.pdf')
        : 'Resume_Alex_Chen.pdf';
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Export Status',
          style: TextStyle(fontWeight: FontWeight.w600, color: onSurface),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.check, color: AppColors.success, size: 40),
              ),
              const SizedBox(height: 24),
              Text(
                'Your resume is ready!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'CV prepared successfully as PDF',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              TCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_outlined,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            filename,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: onSurface,
                            ),
                          ),
                          const Text(
                            'Demo Mode file ready for download',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.download, color: AppColors.primary),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              TButton(
                label: 'Back to Builder',
                onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  R.resumeBuilder,
                  (r) => false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
