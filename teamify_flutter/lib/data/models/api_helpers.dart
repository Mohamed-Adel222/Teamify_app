String asString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

int asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double asDouble(dynamic value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

bool asBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  final normalized = value?.toString().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}

List<String> asStringList(dynamic value) {
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value is List) {
    return value.map(asMap).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

/// Parse an API ISO-8601 timestamp, treating timezone-less values as UTC.
///
/// The backend stores UTC; older payloads may lack the `Z`/offset suffix and
/// Dart would otherwise interpret them as local time.
DateTime? parseApiDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  var value = iso.trim();
  // SQLite / API sometimes returns "2026-05-25 10:00:00" without "T".
  if (value.contains(' ') && !value.contains('T')) {
    value = value.replaceFirst(' ', 'T');
  }
  final hasOffset = value.endsWith('Z') ||
      value.endsWith('z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  final parsed = DateTime.tryParse(hasOffset ? value : '${value}Z');
  return parsed?.toLocal();
}

/// Human-readable relative time from an ISO-8601 timestamp.
String formatRelativeTime(String isoString) {
  if (isoString.isEmpty) return '';
  final local = parseApiDateTime(isoString);
  if (local == null) {
    return isoString.replaceFirst('T', ' ').split('.').first;
  }
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
