import '../../config/app_config.dart';
import '../../core/network/api_client.dart';
import '../models/models.dart';
import 'repository_helpers.dart';

class SearchRepository {
  final ApiClient _client;

  SearchRepository(this._client);

  static const List<ApiUser> _demoUsers = [
    ApiUser(
      id: 'demo_user_1',
      displayName: 'alex_dev',
      fullName: 'Alex Chen',
      email: 'alex.chen@example.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=alex_dev',
      userType: 'freelancer',
      role: 'member',
      professionalField: 'Frontend Development',
      experienceLevel: 'Senior',
      skills: ['Flutter', 'Dart', 'React', 'TypeScript', 'Tailwind'],
      bio:
          'Senior Flutter & Frontend developer building high-performance cross-platform apps.',
    ),
    ApiUser(
      id: 'demo_user_2',
      displayName: 'sarah_m',
      fullName: 'Sarah Miller',
      email: 'sarah.m@example.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=sarah_m',
      userType: 'student',
      role: 'member',
      major: 'Computer Science',
      currentLevel: 'Senior',
      universityId: 'uni_cairo',
      universityName: 'Cairo University',
      isCustomUniversity: false,
      skills: ['Python', 'Machine Learning', 'Data Analysis', 'PyTorch'],
      bio:
          'CS Senior researching AI/ML algorithms and intelligent automated systems.',
    ),
    ApiUser(
      id: 'demo_user_3',
      displayName: 'david_ui',
      fullName: 'David Ross',
      email: 'david.ross@example.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=david_ui',
      userType: 'freelancer',
      role: 'member',
      professionalField: 'UI/UX Design',
      experienceLevel: 'Expert',
      skills: [
        'Figma',
        'UI/UX Design',
        'Prototyping',
        'User Research',
        'Design Systems'
      ],
      bio:
          'Product Designer crafting intuitive user experiences and modern visual design systems.',
    ),
    ApiUser(
      id: 'demo_user_4',
      displayName: 'emily_sec',
      fullName: 'Emily Watson',
      email: 'emily.watson@example.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=emily_sec',
      userType: 'student',
      role: 'member',
      major: 'Cybersecurity',
      currentLevel: 'Junior',
      universityId: 'uni_ain_shams',
      universityName: 'Ain Shams University',
      isCustomUniversity: false,
      skills: [
        'Cybersecurity',
        'Linux',
        'Network Security',
        'Penetration Testing'
      ],
      bio:
          'Cybersecurity enthusiast passionate about cloud security and ethical hacking.',
    ),
    ApiUser(
      id: 'demo_user_5',
      displayName: 'michael_founder',
      fullName: 'Michael Vance',
      email: 'michael.v@startup.io',
      avatarFileId: 'https://i.pravatar.cc/150?u=michael_founder',
      userType: 'startup_founder',
      role: 'admin',
      professionalField: 'Product Strategy',
      skills: [
        'Product Strategy',
        'Venture Capital',
        'Team Leadership',
        'Growth Marketing'
      ],
      bio:
          'Founder & CEO building next-gen collaboration platforms for remote technical teams.',
    ),
    ApiUser(
      id: 'demo_user_6',
      displayName: 'hannah_recruiter',
      fullName: 'Hannah Abbot',
      email: 'hannah.a@talentagency.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=hannah_recruiter',
      userType: 'recruiter',
      role: 'admin',
      professionalField: 'Tech Talent Acquisition',
      skills: [
        'Tech Recruiting',
        'Headhunting',
        'Career Coaching',
        'Interviewing'
      ],
      bio:
          'Senior Tech Recruiter connecting top software engineering talent with high-growth startups.',
    ),
    ApiUser(
      id: 'demo_user_7',
      displayName: 'jason_backend',
      fullName: 'Jason Lee',
      email: 'jason.lee@enterprise.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=jason_backend',
      userType: 'employee',
      role: 'member',
      professionalField: 'Backend Development',
      experienceLevel: 'Staff Engineer',
      skills: ['Go', 'Microservices', 'Kubernetes', 'PostgreSQL', 'Docker'],
      bio:
          'Staff Systems Engineer specializing in scalable distributed microservices.',
    ),
    ApiUser(
      id: 'demo_user_8',
      displayName: 'lisa_ai',
      fullName: 'Lisa Zhang',
      email: 'lisa.zhang@example.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=lisa_ai',
      userType: 'freelancer',
      role: 'member',
      professionalField: 'Artificial Intelligence',
      experienceLevel: 'Senior',
      skills: [
        'Artificial Intelligence',
        'NLP',
        'LLMs',
        'Prompt Engineering',
        'Python'
      ],
      bio:
          'AI Solutions Architect building custom LLM workflows and intelligent automation agents.',
    ),
    ApiUser(
      id: 'demo_user_9',
      displayName: 'kevin_student',
      fullName: 'Kevin Patel',
      email: 'kevin.patel@univ.edu',
      avatarFileId: 'https://i.pravatar.cc/150?u=kevin_student',
      userType: 'student',
      role: 'member',
      major: 'Software Engineering',
      currentLevel: 'Sophomore',
      universityId: 'uni_cairo',
      universityName: 'Cairo University',
      isCustomUniversity: false,
      skills: ['Java', 'Spring Boot', 'SQL', 'Git'],
      bio:
          'Software Engineering sophomore eager to collaborate on open-source student projects.',
    ),
    ApiUser(
      id: 'demo_user_16',
      displayName: 'nour_guc',
      fullName: 'Nour El-Din',
      email: 'nour.eldin@guc.edu.eg',
      avatarFileId: 'https://i.pravatar.cc/150?u=nour_guc',
      userType: 'student',
      role: 'member',
      major: 'Digital Media Engineering',
      currentLevel: 'Senior',
      universityId: 'uni_guc',
      universityName: 'German University in Cairo',
      isCustomUniversity: false,
      skills: ['Flutter', 'UI/UX Design', 'Computer Graphics'],
      bio: 'GUC Senior specializing in mobile graphics and cross-platform UI.',
    ),
    ApiUser(
      id: 'demo_user_17',
      displayName: 'tarek_custom',
      fullName: 'Tarek Omar',
      email: 'tarek.omar@delta.edu.eg',
      avatarFileId: 'https://i.pravatar.cc/150?u=tarek_custom',
      userType: 'student',
      role: 'member',
      major: 'Information Systems',
      currentLevel: 'Junior',
      universityId: 'custom_delta',
      universityName: 'Delta Institute of Technology',
      isCustomUniversity: true,
      skills: ['Web Development', 'PHP', 'Laravel', 'MySQL'],
      bio: 'Junior IS student building fullstack web solutions.',
    ),
    ApiUser(
      id: 'demo_user_10',
      displayName: 'rachel_qa',
      fullName: 'Rachel Green',
      email: 'rachel.g@company.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=rachel_qa',
      userType: 'employee',
      role: 'member',
      professionalField: 'QA & Software Testing',
      experienceLevel: 'Mid-Level',
      skills: ['Automated Testing', 'Selenium', 'Cypress', 'CI/CD', 'QA'],
      bio:
          'QA Automation Engineer ensuring robust software quality and automated release pipelines.',
    ),
    ApiUser(
      id: 'demo_user_11',
      displayName: 'daniel_mobile',
      fullName: 'Daniel Kim',
      email: 'daniel.k@mobileapps.io',
      avatarFileId: 'https://i.pravatar.cc/150?u=daniel_mobile',
      userType: 'freelancer',
      role: 'member',
      professionalField: 'Mobile App Development',
      experienceLevel: 'Senior',
      skills: [
        'Android Development',
        'iOS Development',
        'Kotlin',
        'Swift',
        'Flutter'
      ],
      bio:
          'Native & cross-platform mobile developer with 30+ published App Store apps.',
    ),
    ApiUser(
      id: 'demo_user_12',
      displayName: 'sophia_pm',
      fullName: 'Sophia Martinez',
      email: 'sophia.m@techcorp.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=sophia_pm',
      userType: 'employee',
      role: 'admin',
      professionalField: 'Agile Project Management',
      skills: ['Scrum Master', 'Agile Management', 'Jira', 'Sprint Planning'],
      bio:
          'Certified Scrum Master driving agile team efficiency and roadmap execution.',
    ),
    ApiUser(
      id: 'demo_user_13',
      displayName: 'nathan_devops',
      fullName: 'Nathan Drake',
      email: 'nathan.d@cloudservices.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=nathan_devops',
      userType: 'employee',
      role: 'member',
      professionalField: 'Cloud Engineering & DevOps',
      skills: ['AWS', 'DevOps', 'Terraform', 'CI/CD Pipelines', 'Linux'],
      bio:
          'Cloud Architect automating infrastructure as code and high-availability cloud deployments.',
    ),
    ApiUser(
      id: 'demo_user_14',
      displayName: 'olivia_data',
      fullName: 'Olivia Taylor',
      email: 'olivia.t@analytics.io',
      avatarFileId: 'https://i.pravatar.cc/150?u=olivia_data',
      userType: 'freelancer',
      role: 'member',
      professionalField: 'Data Science',
      skills: [
        'Data Science',
        'Data Analysis',
        'Tableau',
        'R',
        'SQL',
        'Pandas'
      ],
      bio:
          'Data Scientist turning complex data streams into actionable business intelligence.',
    ),
    ApiUser(
      id: 'demo_user_15',
      displayName: 'ethan_game',
      fullName: 'Ethan Hunt',
      email: 'ethan.h@games.com',
      avatarFileId: 'https://i.pravatar.cc/150?u=ethan_game',
      userType: 'startup_founder',
      role: 'admin',
      professionalField: 'Game Development',
      skills: [
        'Game Development',
        'Unity',
        'Unreal Engine',
        'C++',
        '3D Design'
      ],
      bio: 'Indie Game Studio Founder crafting immersive 3D multiplayer games.',
    ),
  ];

  Future<List<ApiUser>> users(
    String query, {
    String? userType,
    int perPage = 100,
  }) async {
    if (AppConfig.isDemoMode) {
      return _filterDemoUsers(query, userType: userType);
    }
    final response = await _client.get<dynamic>(
      '/api/search/users',
      queryParameters: {
        if (query.isNotEmpty) 'q': query,
        if (userType != null) 'user_type': userType,
        'per_page': perPage,
      },
    );
    return responseList(response.data, ['users', 'data'])
        .map(ApiUser.fromJson)
        .toList();
  }

  List<ApiUser> _filterDemoUsers(String query, {String? userType}) {
    final q = query.toLowerCase();
    return _demoUsers.where((u) {
      if (userType != null && userType.isNotEmpty && u.userType != userType) {
        return false;
      }
      if (q.isEmpty) return true;
      final matchName = u.primaryName.toLowerCase().contains(q);
      final matchDisplay = u.displayName.toLowerCase().contains(q);
      final matchMajor = u.major.toLowerCase().contains(q);
      final matchField = u.professionalField.toLowerCase().contains(q);
      final matchSkills = u.skills.any((s) => s.toLowerCase().contains(q));
      final matchBio = u.bio.toLowerCase().contains(q);
      return matchName ||
          matchDisplay ||
          matchMajor ||
          matchField ||
          matchSkills ||
          matchBio;
    }).toList();
  }

  Future<List<ApiProject>> projects(String query) async {
    if (AppConfig.isDemoMode) {
      return const [];
    }
    final response = await _client.get<dynamic>(
      '/api/search/projects',
      queryParameters: {if (query.isNotEmpty) 'q': query},
    );
    return responseList(response.data, ['projects', 'data'])
        .map(ApiProject.fromJson)
        .toList();
  }
}
