import 'package:flutter/foundation.dart';

import 'playback_models.dart';

/// Grep: `[sync]`
class SyncLog {
  static void stage(String stage, [Map<String, Object?> extra = const {}]) {
    final bits = extra.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint(bits.isEmpty ? '[sync] $stage' : '[sync] $stage $bits');
  }

  static Map<String, Object?> snapshot(PlaybackSnapshot snapshot) => {
        'rev': snapshot.revision,
        'device': shortId(snapshot.deviceId),
        'track': shortId(snapshot.trackId),
        'playing': snapshot.isPlaying,
        'posMs': snapshot.positionMs,
        'source': snapshot.source ?? '-',
        'items': snapshot.queue.items.length,
      };

  static String shortId(String? id) {
    if (id == null || id.isEmpty) {
      return '-';
    }
    return id.length <= 8 ? id : id.substring(0, 8);
  }
}
