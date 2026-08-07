/// Centralised reference data for all registration screens.
///
/// Keep this file as the single source of truth for:
///   • Major options  (Student signup)
///   • Skill options  (Student + Freelancer signup)
///   • Demo-mode username blocklist  (local uniqueness simulation)
class RegistrationOptions {
  // ── Majors ─────────────────────────────────────────────────────────────────
  static const List<String> majors = [
    // Technology
    'Computer Science',
    'Information Technology',
    'Software Engineering',
    'Computer Engineering',
    'Information Systems',
    'Network Engineering',
    'Cybersecurity',
    'Cloud Computing',
    'Web Development',
    'Mobile Development',
    // AI & Data
    'Artificial Intelligence',
    'Machine Learning',
    'Data Science',
    'Data Engineering',
    'Business Intelligence',
    'Robotics',
    // Engineering
    'Electrical Engineering',
    'Mechanical Engineering',
    'Civil Engineering',
    'Chemical Engineering',
    'Biomedical Engineering',
    'Industrial Engineering',
    'Environmental Engineering',
    // Business & Management
    'Business Administration',
    'Management Information Systems',
    'Entrepreneurship',
    'International Business',
    'Supply Chain Management',
    'Operations Management',
    'Project Management',
    'Human Resources Management',
    // Finance & Economics
    'Finance',
    'Accounting',
    'Economics',
    'Financial Technology (FinTech)',
    'Banking & Finance',
    // Design & Media
    'Graphic Design',
    'UI/UX Design',
    'Digital Media',
    'Multimedia',
    'Animation & VFX',
    'Film & Television',
    'Photography',
    'Game Design',
    // Marketing & Communication
    'Marketing',
    'Digital Marketing',
    'Mass Communication',
    'Public Relations',
    'Journalism',
    'Content Creation',
    // Product & Research
    'Product Management',
    'Research & Development',
    'Cognitive Science',
    'Human-Computer Interaction',
    // Other fields
    'Architecture',
    'Law',
    'Medicine',
    'Pharmacy',
    'Dentistry',
    'Languages',
    'Nursing',
    'Psychology',
    'Sociology',
    'Education',
    'Political Science',
    'International Relations',
    'Other',
  ];

  // ── Skills ─────────────────────────────────────────────────────────────────
  static const List<String> skills = [
    // Programming Languages
    'Python',
    'JavaScript',
    'TypeScript',
    'Java',
    'Kotlin',
    'Swift',
    'Dart',
    'C',
    'C++',
    'C#',
    'Go',
    'Rust',
    'Ruby',
    'PHP',
    'R',
    'MATLAB',
    'Scala',
    'Perl',
    // Frontend
    'Flutter',
    'React',
    'React Native',
    'Vue.js',
    'Angular',
    'HTML & CSS',
    'Tailwind CSS',
    'Next.js',
    'Svelte',
    // Backend
    'Node.js',
    'Django',
    'Flask',
    'FastAPI',
    'Spring Boot',
    'Laravel',
    'Ruby on Rails',
    'Express.js',
    '.NET',
    // Mobile
    'Android Development',
    'iOS Development',
    'Mobile App Development',
    'Cross-Platform Development',
    // Databases
    'SQL',
    'MySQL',
    'PostgreSQL',
    'MongoDB',
    'Firebase',
    'Redis',
    'SQLite',
    'Oracle DB',
    'DynamoDB',
    // Cloud & DevOps
    'AWS',
    'Google Cloud',
    'Azure',
    'Docker',
    'Kubernetes',
    'CI/CD',
    'Terraform',
    'Linux',
    'Shell Scripting',
    // Data & AI
    'Machine Learning',
    'Deep Learning',
    'Data Analysis',
    'Data Visualization',
    'TensorFlow',
    'PyTorch',
    'scikit-learn',
    'NLP',
    'Computer Vision',
    'Big Data',
    'Tableau',
    'Power BI',
    // Design
    'UI/UX Design',
    'Product Design',
    'Figma',
    'Adobe XD',
    'Sketch',
    'Graphic Design',
    'Motion Design',
    'Wireframing',
    'Prototyping',
    'User Research',
    'Adobe Photoshop',
    'Adobe Illustrator',
    'After Effects',
    // Project & Product
    'Project Management',
    'Product Management',
    'Agile / Scrum',
    'Kanban',
    'Jira',
    'Notion',
    'Trello',
    // Marketing & Business
    'Digital Marketing',
    'SEO',
    'Content Marketing',
    'Social Media Marketing',
    'Copywriting',
    'Email Marketing',
    'Brand Strategy',
    'Market Research',
    'Sales',
    'Business Analysis',
    // Communication & Soft Skills
    'Technical Writing',
    'Public Speaking',
    'Leadership',
    'Team Management',
    'Mentoring',
    'Customer Support',
    // Security
    'Cybersecurity',
    'Penetration Testing',
    'Network Security',
    'Ethical Hacking',
    'SIEM',
    // Other
    'Blockchain',
    'Web3',
    'AR / VR',
    'Game Development',
    'Embedded Systems',
    'IoT',
    'API Design',
    'Microservices',
    'AI Tools',
    'Other',
  ];

  // ── Professional Fields ───────────────────────────────────────────────────
  static const List<String> professionalFields = [
    // Technology & Software
    'Frontend Development',
    'Backend Development',
    'Full-Stack Development',
    'Mobile App Development',
    'Flutter Development',
    'Android Development',
    'iOS Development',
    'Software Engineering',
    'Game Development',
    'WordPress Development',
    'QA & Software Testing',
    'Technical Support',
    'IT Support',
    // Artificial Intelligence & Data
    'Artificial Intelligence',
    'Machine Learning',
    'Deep Learning',
    'Data Science',
    'Data Analysis',
    'Data Engineering',
    'Business Intelligence',
    'NLP',
    'Computer Vision',
    'AI Automation',
    'Prompt Engineering',
    // Cybersecurity & Infrastructure
    'Cybersecurity',
    'SOC Analysis',
    'Penetration Testing',
    'Digital Forensics',
    'Cloud Security',
    'Network Engineering',
    'System Administration',
    'Cloud Computing',
    'DevOps',
    'Site Reliability Engineering',
    'Database Administration',
    // Design & Creative
    'UI/UX Design',
    'Product Design',
    'Graphic Design',
    'Branding',
    'Motion Graphics',
    'Illustration',
    '3D Design',
    'Interior Design',
    'Architecture',
    'Video Editing',
    'Photography',
    // Business & Management
    'Business Development',
    'Product Management',
    'Project Management',
    'Operations Management',
    'Entrepreneurship',
    'Business Analysis',
    'Management Consulting',
    'Customer Success',
    'Sales',
    'Human Resources',
    'Recruitment',
    // Marketing & Content
    'Digital Marketing',
    'Social Media Marketing',
    'Content Marketing',
    'SEO',
    'SEM',
    'Performance Marketing',
    'Email Marketing',
    'Copywriting',
    'Content Writing',
    'Script Writing',
    'Public Relations',
    'Community Management',
    // Finance & Legal
    'Accounting',
    'Finance',
    'Financial Analysis',
    'Bookkeeping',
    'Investment Analysis',
    'Legal Services',
    'Tax Consulting',
    // Engineering
    'Civil Engineering',
    'Mechanical Engineering',
    'Electrical Engineering',
    'Mechatronics Engineering',
    'Electronics Engineering',
    'Communications Engineering',
    'Industrial Engineering',
    'Architectural Engineering',
    // Education, Languages & Other
    'Teaching',
    'Training',
    'Translation',
    'Language Services',
    'Research',
    'Healthcare',
    'Medicine',
    'Pharmacy',
    'Customer Service',
    'Virtual Assistance',
    'Data Entry',
    'Other',
  ];

  // ── Demo-mode username blocklist ────────────────────────────────────────────
  /// Simulates existing usernames when Demo Mode is active.
  /// Add any username here to make it appear "already taken" in demo flows.
  static const Set<String> takenDemoUsernames = {
    'admin',
    'test',
    'user',
    'demo',
    'teamify',
    'student',
    'freelancer',
    'manager',
    'superuser',
    'root',
    'guest',
    'support',
    'info',
  };

  // ── Username validation ─────────────────────────────────────────────────────
  /// Returns an error string if the username is invalid, or null if valid.
  static String? validateUsername(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return 'Username is required.';
    if (username.contains(' ')) return 'Spaces are not allowed in username.';
    if (username.length < 3) return 'Username must be at least 3 characters.';
    if (username.length > 20) return 'Username must be 20 characters or fewer.';
    if (!RegExp(r'^[a-zA-Z]').hasMatch(username)) {
      return 'Username must start with a letter.';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      return 'Only letters, numbers, and underscores are allowed.';
    }
    return null;
  }

  /// Returns true when the username is already taken in demo mode.
  static bool isDemoUsernameTaken(String username) =>
      takenDemoUsernames.contains(username.toLowerCase());
}
