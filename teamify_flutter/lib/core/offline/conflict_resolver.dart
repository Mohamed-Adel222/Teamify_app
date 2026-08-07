import 'package:flutter/foundation.dart';

enum MergeStrategy { serverWins, clientWins, manual }

class ConflictResolver<T> {
  final MergeStrategy strategy;
  final DateTime Function(T) getUpdatedAt;
  final T Function(T client, T server) customMerge;

  ConflictResolver({
    this.strategy = MergeStrategy.serverWins,
    required this.getUpdatedAt,
    required this.customMerge,
  });

  /// Resolves a conflict between a local mutation and a server response
  T resolve(T clientPayload, T serverPayload) {
    if (strategy == MergeStrategy.serverWins) {
      return serverPayload;
    }

    if (strategy == MergeStrategy.clientWins) {
      return clientPayload;
    }

    final clientTime = getUpdatedAt(clientPayload);
    final serverTime = getUpdatedAt(serverPayload);

    // Optimistic concurrency fallback based on time
    if (clientTime.isAfter(serverTime)) {
      debugPrint('[ConflictResolver] Client time newer, using custom merge');
      return customMerge(clientPayload, serverPayload);
    }

    debugPrint(
        '[ConflictResolver] Server time newer, resolving with server payload');
    return serverPayload;
  }
}
