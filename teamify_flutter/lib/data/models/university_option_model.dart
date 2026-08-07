/// Model representing a University option.
class UniversityOption {
  final String id;
  final String name;
  final String normalizedName;
  final bool isCustom;
  final String countryCode;
  final String? city;
  final String? type;
  final List<String> aliases;

  const UniversityOption({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.isCustom = false,
    this.countryCode = 'EG',
    this.city,
    this.type,
    this.aliases = const [],
  });

  /// Factory constructor to create a UniversityOption with automatic normalization.
  factory UniversityOption.create({
    required String id,
    required String name,
    bool isCustom = false,
    String countryCode = 'EG',
    String? city,
    String? type,
    List<String> aliases = const [],
  }) {
    final cleanedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return UniversityOption(
      id: id,
      name: cleanedName,
      normalizedName: normalizeUniversityName(cleanedName),
      isCustom: isCustom,
      countryCode: countryCode,
      city: city,
      type: type,
      aliases: aliases,
    );
  }

  factory UniversityOption.fromJson(Map<String, dynamic> json) {
    final aliases = json['aliases'];
    return UniversityOption.create(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      isCustom: json['is_custom'] == true,
      city: json['city']?.toString(),
      type: json['type']?.toString(),
      aliases: aliases is List
          ? aliases.map((a) => a.toString()).toList()
          : const <String>[],
    );
  }

  /// Builds a client-side option for a university the user typed manually. The
  /// name is persisted on the user record and appears in the catalog afterwards.
  factory UniversityOption.custom(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final slug =
        normalizeUniversityName(cleaned).replaceAll(RegExp(r'\s+'), '_');
    return UniversityOption.create(
      id: 'custom_$slug',
      name: cleaned,
      isCustom: true,
    );
  }

  /// Helper to normalize university names for collision checks.
  static String normalizeUniversityName(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Validate a custom university input name.
  static String? validateCustomUniversityName(String? raw) {
    if (raw == null) return 'University name is required.';
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (trimmed.isEmpty) {
      return 'University name is required.';
    }

    // Reject values containing only numbers
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return 'University name cannot contain only numbers.';
    }

    // Reject values containing only symbols
    if (RegExp(r'^[^\w\s]+$').hasMatch(trimmed)) {
      return 'University name cannot contain only symbols.';
    }

    // Accept valid university names containing letters, spaces, apostrophes, hyphens, periods, and numbers
    final validPattern = RegExp(r"^[a-zA-Z0-9\s\'\.\-]+$");
    if (!validPattern.hasMatch(trimmed)) {
      return 'Please enter a valid university name.';
    }

    return null;
  }
}
