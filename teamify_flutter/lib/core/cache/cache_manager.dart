import 'dart:convert' as convert;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';

/// Lightweight cache layer backed by Hive.
///
/// Uses a cache-first strategy: reads from local storage immediately,
/// then syncs with the backend in the background.
class CacheManager {
  static const _metaBoxName = '_cache_meta';

  bool _initialized = false;

  /// Guards against concurrent `openBox` calls for the same name.
  final Map<String, Future<Box<dynamic>>> _openingBoxes = {};

  Future<void>? _initFuture;

  /// Call once at app startup (before runApp).
  Future<void> init() {
    if (_initialized) return Future.value();
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(_metaBoxName);
    _initialized = true;
    _initFuture = null;
  }

  /// Test-only setter for [_initialized]. Allows test subclasses to bypass
  /// [Hive.initFlutter()] which requires Flutter bindings.
  @visibleForTesting
  void setInitialized(bool value) => _initialized = value;

  /// Open (or reuse) a typed box. Safe against concurrent calls.
  Future<Box<T>> openBox<T>(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<T>(name);
    // Deduplicate concurrent open calls for the same box name
    if (_openingBoxes.containsKey(name)) {
      await _openingBoxes[name];
      return Hive.box<T>(name);
    }
    final future = Hive.openBox<T>(name);
    _openingBoxes[name] = future;
    try {
      await future;
      return Hive.box<T>(name);
    } finally {
      _openingBoxes.remove(name);
    }
  }

  /// Store a JSON-serializable map list under [key] in [boxName].
  Future<void> putList(
    String boxName,
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    if (!_initialized) return;
    final box = await openBox<String>(boxName);
    final encoded = convert.jsonEncode(items);
    final tempKey = 'temp_$key';
    await box.put(tempKey, encoded);
    await box.put(key, encoded);
    await box.delete(tempKey);
    await _setTimestamp(boxName, key);
    await enforceMaxSize(boxName);
  }

  /// Store a single JSON-serializable map under [key] in [boxName].
  Future<void> putMap(
    String boxName,
    String key,
    Map<String, dynamic> data,
  ) async {
    if (!_initialized) return;
    final box = await openBox<String>(boxName);
    final encoded = convert.jsonEncode(data);
    final tempKey = 'temp_$key';
    await box.put(tempKey, encoded);
    await box.put(key, encoded);
    await box.delete(tempKey);
    await _setTimestamp(boxName, key);
    await enforceMaxSize(boxName);
  }

  /// Retrieve a cached list, or null if missing / expired.
  Future<List<Map<String, dynamic>>?> getList(
    String boxName,
    String key, {
    Duration maxAge = const Duration(minutes: 10),
  }) async {
    if (!_initialized) return null;
    if (isExpired(boxName, key, maxAge)) return null;
    try {
      final box = await openBox<String>(boxName);
      final raw = box.get(key);
      if (raw == null) return null;
      final decoded = convert.jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
      return null;
    } catch (_) {
      // Corrupted cache — treat as miss
      await invalidate(boxName, key);
      return null;
    }
  }

  /// Retrieve a cached map, or null if missing / expired.
  Future<Map<String, dynamic>?> getMap(
    String boxName,
    String key, {
    Duration maxAge = const Duration(minutes: 10),
  }) async {
    if (!_initialized) return null;
    if (isExpired(boxName, key, maxAge)) return null;
    try {
      final box = await openBox<String>(boxName);
      final raw = box.get(key);
      if (raw == null) return null;
      final decoded = convert.jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      await invalidate(boxName, key);
      return null;
    }
  }

  /// Invalidate a specific cache entry.
  Future<void> invalidate(String boxName, String key) async {
    if (!_initialized) return;
    final box = await openBox<String>(boxName);
    await box.delete(key);
    final meta = Hive.box<String>(_metaBoxName);
    await meta.delete('${boxName}_${key}_ts');
  }

  /// Invalidate everything in a box, including timestamps.
  Future<void> invalidateBox(String boxName) async {
    if (!_initialized) return;
    final box = await openBox<String>(boxName);
    await box.clear();
    // Also clear all timestamps for this box
    final meta = Hive.box<String>(_metaBoxName);
    final keysToDelete =
        meta.keys.where((k) => k.toString().startsWith('${boxName}_')).toList();
    for (final key in keysToDelete) {
      await meta.delete(key);
    }
  }

  /// Clear all caches. Safe to call during logout.
  Future<void> clearAll() async {
    _initialized = false;
    _openingBoxes.clear();
    // Close all boxes first to prevent write-after-delete
    await Hive.close();
    await Hive.deleteFromDisk();
    await init();
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  bool isExpired(String boxName, String key, Duration maxAge) {
    if (!Hive.isBoxOpen(_metaBoxName)) return true;
    final meta = Hive.box<String>(_metaBoxName);
    final tsStr = meta.get('${boxName}_${key}_ts');
    if (tsStr == null) return true;
    final ts = DateTime.tryParse(tsStr);
    if (ts == null) return true;
    return DateTime.now().difference(ts) > maxAge;
  }

  // ── Pagination Cache Segmentation ───────────────────────────────────────

  /// Stores a specific page of a paginated list
  Future<void> putPagedList(
    String boxName,
    String keyPrefix,
    int page,
    List<Map<String, dynamic>> items,
  ) async {
    await putList(boxName, '${keyPrefix}_page_$page', items);

    // Update the metadata for total pages tracked
    if (!_initialized) return;
    final meta = Hive.box<String>(_metaBoxName);
    final totalStr = meta.get('${boxName}_${keyPrefix}_pages');
    final currentMax = totalStr != null ? int.tryParse(totalStr) ?? 0 : 0;
    if (page > currentMax) {
      await meta.put('${boxName}_${keyPrefix}_pages', page.toString());
    }
  }

  /// Retrieves a specific page of a paginated list
  Future<List<dynamic>?> getPagedList(
    String boxName,
    String keyPrefix,
    int page, {
    Duration maxAge = const Duration(minutes: 10),
  }) async {
    return getList(boxName, '${keyPrefix}_page_$page', maxAge: maxAge);
  }

  /// Clears all pages for a paginated list
  Future<void> invalidatePagedList(String boxName, String keyPrefix) async {
    if (!_initialized) return;
    final meta = Hive.box<String>(_metaBoxName);
    final totalStr = meta.get('${boxName}_${keyPrefix}_pages');
    final totalPages = totalStr != null ? int.tryParse(totalStr) ?? 0 : 0;

    for (var i = 1; i <= totalPages; i++) {
      await invalidate(boxName, '${keyPrefix}_page_$i');
    }
    await meta.delete('${boxName}_${keyPrefix}_pages');
  }

  // ── Advanced Cache Hardening ───────────────────────────────────────────

  /// Enforce LRU eviction if a box exceeds a given size
  Future<void> enforceMaxSize(String boxName, {int maxItems = 100}) async {
    if (!_initialized) return;
    final box = await openBox<String>(boxName);
    if (box.length <= maxItems) return;

    final meta = Hive.box<String>(_metaBoxName);

    // Build a list of (key, timestamp)
    final entries = <MapEntry<String, DateTime>>[];
    for (final key in box.keys) {
      final tsStr = meta.get('${boxName}_${key}_ts');
      if (tsStr != null) {
        final ts =
            DateTime.tryParse(tsStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
        entries.add(MapEntry(key.toString(), ts));
      } else {
        entries.add(
            MapEntry(key.toString(), DateTime.fromMillisecondsSinceEpoch(0)));
      }
    }

    // Sort by oldest first
    entries.sort((a, b) => a.value.compareTo(b.value));

    // Remove oldest entries until we're under the limit
    final toRemove =
        entries.take(box.length - maxItems).map((e) => e.key).toList();
    for (final key in toRemove) {
      await box.delete(key);
      await meta.delete('${boxName}_${key}_ts');
    }
  }

  /// Clean up metadata for keys that no longer exist
  Future<void> cleanupOrphans(String boxName) async {
    if (!_initialized) return;
    final box = await openBox<String>(boxName);
    final meta = Hive.box<String>(_metaBoxName);

    final prefix = '${boxName}_';
    final keysToDelete = <dynamic>[];

    for (final metaKey in meta.keys) {
      final keyStr = metaKey.toString();
      if (keyStr.startsWith(prefix) && keyStr.endsWith('_ts')) {
        final actualKey = keyStr.substring(prefix.length, keyStr.length - 3);
        if (!box.containsKey(actualKey)) {
          keysToDelete.add(metaKey);
        }
      }
    }

    for (final metaKey in keysToDelete) {
      await meta.delete(metaKey);
    }
  }

  Future<void> _setTimestamp(String boxName, String key) async {
    if (!Hive.isBoxOpen(_metaBoxName)) return;
    final meta = Hive.box<String>(_metaBoxName);
    await meta.put(
      '${boxName}_${key}_ts',
      DateTime.now().toIso8601String(),
    );
  }
}
