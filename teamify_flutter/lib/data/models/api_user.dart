import '../../models/models.dart';
import 'api_helpers.dart';

class ApiUser {
  final String id;
  final String displayName;
  final String fullName;
  final String email;
  final String role;
  final String systemRole;
  final String projectRole;
  final String userType;
  final List<String> skills;
  final String professionalField;
  final String availability;
  final String experienceLevel;
  final String joinedAt;
  final String phone;
  final String bio;
  final String avatarFileId;
  final String accountStatus;
  final String major;
  final String currentLevel;
  final bool? lookingForTeam;
  final String reasonForJoining;
  final int memberExperienceYears;
  final int tasksCompleted;
  final double qualityScore;
  final double attendanceRate;
  final double memberOnTimeRate;
  final bool totpEnabled;
  final String preferredLanguage;
  final String universityId;
  final String universityName;
  final bool isCustomUniversity;

  const ApiUser({
    required this.id,
    required this.displayName,
    required this.fullName,
    required this.email,
    required this.role,
    this.systemRole = '',
    this.projectRole = '',
    required this.userType,
    this.skills = const [],
    this.professionalField = '',
    this.availability = '',
    this.experienceLevel = '',
    this.joinedAt = '',
    this.phone = '',
    this.bio = '',
    this.avatarFileId = '',
    this.accountStatus = 'approved',
    this.major = '',
    this.currentLevel = '',
    this.lookingForTeam,
    this.reasonForJoining = '',
    this.memberExperienceYears = 0,
    this.tasksCompleted = 0,
    this.qualityScore = 0,
    this.attendanceRate = 0,
    this.memberOnTimeRate = 0,
    this.totpEnabled = false,
    this.preferredLanguage = 'en',
    this.universityId = '',
    this.universityName = '',
    this.isCustomUniversity = false,
  });

  /// Best label for lists (full name, else @display_name).
  String get primaryName => fullName.isNotEmpty ? fullName : displayName;

  /// Secondary line: email · account type · field · availability.
  String get memberMetaLine {
    final parts = <String>[];
    if (email.isNotEmpty) parts.add(email);
    if (displayRole.isNotEmpty) parts.add(displayRole);
    if (professionalField.isNotEmpty) parts.add(professionalField);
    if (availability.isNotEmpty) parts.add(availability);
    if (experienceLevel.isNotEmpty) parts.add(experienceLevel);
    return parts.join(' · ');
  }

  /// Skills summary for member cards.
  String get skillsSummary => skills.isEmpty ? '' : skills.take(6).join(', ');

  /// Role label for project member lists (Owner / Member).
  String get projectRoleLabel {
    final pr = projectRole.isNotEmpty ? projectRole : role;
    if (pr == 'owner' || pr == 'member') {
      return pr[0].toUpperCase() + pr.substring(1);
    }
    return '';
  }

  bool get isAdmin =>
      (systemRole.isNotEmpty ? systemRole : role).toLowerCase() == 'admin';
  bool get needsAdmin2faSetup => isAdmin && !totpEnabled;
  bool get isStudent => userType.toLowerCase() == 'student';
  bool get isFreelancer => userType.toLowerCase() == 'freelancer';

  /// Account approval workflow removed — always false.
  bool get isPending => accountStatus.toLowerCase() == 'pending';

  /// True when OAuth or minimal sign-up left extended profile fields empty.
  bool get needsProfileSetup {
    if (isStudent) {
      return major.isEmpty || currentLevel.isEmpty || skills.isEmpty;
    }
    if (isFreelancer || userType.isEmpty) {
      return professionalField.isEmpty ||
          experienceLevel.isEmpty ||
          availability.isEmpty ||
          skills.isEmpty;
    }
    return false;
  }

  String get accountStatusLabel {
    switch (accountStatus.toLowerCase()) {
      case 'approved':
        return 'Active';
      case 'pending':
        return 'Pending';
      case 'rejected':
        return 'Rejected';
      case 'locked':
      case 'suspended':
        return accountStatus[0].toUpperCase() + accountStatus.substring(1);
      default:
        return accountStatus.isEmpty ? 'Active' : accountStatus;
    }
  }

  String get displayRole {
    if (isAdmin) return 'Admin';
    if (isStudent) return 'Student';
    return 'Freelancer';
  }

  ApiUser copyWith({
    String? displayName,
    String? fullName,
    String? email,
    List<String>? skills,
    String? professionalField,
    String? availability,
    String? experienceLevel,
    String? phone,
    String? bio,
    String? avatarFileId,
    String? major,
    String? currentLevel,
    bool? lookingForTeam,
    bool? totpEnabled,
    String? preferredLanguage,
    String? universityId,
    String? universityName,
    bool? isCustomUniversity,
  }) {
    return ApiUser(
      id: id,
      displayName: displayName ?? this.displayName,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role,
      systemRole: systemRole,
      projectRole: projectRole,
      userType: userType,
      skills: skills ?? this.skills,
      professionalField: professionalField ?? this.professionalField,
      availability: availability ?? this.availability,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      joinedAt: joinedAt,
      phone: phone ?? this.phone,
      bio: bio ?? this.bio,
      avatarFileId: avatarFileId ?? this.avatarFileId,
      accountStatus: accountStatus,
      major: major ?? this.major,
      currentLevel: currentLevel ?? this.currentLevel,
      lookingForTeam: lookingForTeam ?? this.lookingForTeam,
      reasonForJoining: reasonForJoining,
      memberExperienceYears: memberExperienceYears,
      tasksCompleted: tasksCompleted,
      qualityScore: qualityScore,
      attendanceRate: attendanceRate,
      memberOnTimeRate: memberOnTimeRate,
      totpEnabled: totpEnabled ?? this.totpEnabled,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      universityId: universityId ?? this.universityId,
      universityName: universityName ?? this.universityName,
      isCustomUniversity: isCustomUniversity ?? this.isCustomUniversity,
    );
  }

  factory ApiUser.fromJson(Map<String, dynamic> json) {
    final display = asString(
      json['display_name'] ?? json['displayName'] ?? json['name'],
      'User',
    );
    final projectRole = asString(
      json['project_role'] ?? json['projectRole'],
    );
    final systemRole = asString(json['role'], 'member');
    return ApiUser(
      id: asString(json['user_id'] ?? json['id']),
      displayName: display,
      fullName: asString(json['full_name'] ?? json['fullName'], display),
      email: asString(json['email']),
      systemRole: systemRole,
      role: systemRole.toLowerCase() == 'admin'
          ? systemRole
          : (projectRole.isNotEmpty ? projectRole : systemRole),
      projectRole: projectRole.isNotEmpty ? projectRole : systemRole,
      userType: asString(json['user_type'] ?? json['userType'], 'freelancer'),
      skills: asStringList(json['skills']),
      professionalField: asString(
        json['professional_field'] ?? json['professionalField'],
      ),
      availability: asString(json['availability']),
      experienceLevel: asString(
        json['experience_level'] ?? json['experienceLevel'],
      ),
      joinedAt: asString(
        json['joined_at'] ?? json['joinedAt'] ?? json['created_at'],
      ),
      phone: asString(json['phone']),
      bio: asString(json['bio']),
      avatarFileId: asString(json['avatar_file_id'] ?? json['avatarFileId']),
      accountStatus: asString(
        json['account_status'] ?? json['accountStatus'],
        'approved',
      ),
      major: asString(json['major']),
      currentLevel: asString(json['current_level'] ?? json['currentLevel']),
      lookingForTeam:
          json['looking_for_team'] == null && json['lookingForTeam'] == null
              ? null
              : asBool(json['looking_for_team'] ?? json['lookingForTeam']),
      reasonForJoining: asString(
        json['reason_for_joining'] ?? json['reasonForJoining'],
      ),
      memberExperienceYears: asInt(
        json['member_experience_years'] ?? json['memberExperienceYears'],
      ),
      tasksCompleted: asInt(json['tasks_completed'] ?? json['tasksCompleted']),
      qualityScore: asDouble(json['quality_score'] ?? json['qualityScore']),
      attendanceRate: asDouble(
        json['attendance_rate'] ?? json['attendanceRate'],
      ),
      memberOnTimeRate: asDouble(
        json['member_on_time_rate'] ?? json['memberOnTimeRate'],
      ),
      totpEnabled: asBool(json['totp_enabled'] ?? json['totpEnabled']),
      preferredLanguage: asString(json['preferred_language'], 'en'),
      universityId: asString(json['university_id'] ?? json['universityId']),
      universityName: asString(json['university_name'] ?? json['universityName']),
      isCustomUniversity: asBool(json['is_custom_university'] ?? json['isCustomUniversity']),
    );
  }

  String get initials {
    final n = primaryName.trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return n[0].toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'full_name': fullName,
        'email': email,
        'role': role,
        'user_type': userType,
        'skills': skills,
        'professional_field': professionalField,
        'availability': availability,
        'experience_level': experienceLevel,
        'joined_at': joinedAt,
        'phone': phone,
        'bio': bio,
        'avatar_file_id': avatarFileId.isEmpty ? null : avatarFileId,
        'account_status': accountStatus,
      };

  UserModel toDisplayModel() {
    return UserModel(
      id: id,
      name: fullName.isNotEmpty ? fullName : displayName,
      email: email,
      role: displayRole,
      skills: skills,
    );
  }
}
