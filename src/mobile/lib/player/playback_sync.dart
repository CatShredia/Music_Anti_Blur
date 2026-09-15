import 'dart:convert';

import 'playback_models.dart';
import 'sync_log.dart';

Map<String, dynamic>? asJsonMap(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return asJsonMap(jsonDecode(trimmed));
    } catch (_) {
      return null;
    }
  }
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): canonicalizeJson(entry.value),
    };
  }
  try {
    return asJsonMap(jsonDecode(jsonEncode(value)));
  } catch (_) {
    return null;
  }
}

Object? canonicalizeJson(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is Map) {
    return {for (final entry in value.entries) entry.key.toString(): canonicalizeJson(entry.value)};
  }
  if (value is Iterable && value is! String) {
    return [for (final entry in value) canonicalizeJson(entry)];
  }
  try {
    return jsonDecode(jsonEncode(value));
  } catch (_) {
    return value.toString();
  }
}

bool shouldIgnoreRemoteSnapshot({
  required int localRevision,
  required int incomingRevision,
  required String? localDeviceId,
  required String? incomingDeviceId,
}) {
  if (localDeviceId != null &&
      localDeviceId.isNotEmpty &&
      incomingDeviceId != null &&
      incomingDeviceId == localDeviceId) {
    return true;
  }
  // Same revision from another device is a writer handoff, not a stale echo.
  if (incomingRevision < localRevision) {
    return true;
  }
  return false;
}

int interpolatePositionMs({
  required int positionMs,
  required bool isPlaying,
  required DateTime updatedAt,
  required DateTime now,
  int? durationMs,
}) {
  var ms = positionMs;
  if (isPlaying) {
    ms += now.difference(updatedAt).inMilliseconds;
  }
  if (ms < 0) {
    ms = 0;
  }
  if (durationMs != null && durationMs > 0 && ms > durationMs) {
    ms = durationMs;
  }
  return ms;
}

PlaybackSnapshot? snapshotFromHubArgs(List<Object?>? args) {
  try {
    final map = _firstJsonMap(args);
    return map == null ? null : PlaybackSnapshot.fromJson(map);
  } catch (e) {
    SyncLog.stage('parse-fail', {'kind': 'PlaybackSnapshot', 'error': '$e'});
    return null;
  }
}

DevicePresence? presenceFromHubArgs(List<Object?>? args) {
  try {
    final map = _firstJsonMap(args);
    return map == null ? null : DevicePresence.fromJson(map);
  } catch (e) {
    SyncLog.stage('parse-fail', {'kind': 'DevicePresence', 'error': '$e'});
    return null;
  }
}

RenditionReady? renditionReadyFromHubArgs(List<Object?>? args) {
  try {
    final map = _firstJsonMap(args);
    return map == null ? null : RenditionReady.fromJson(map);
  } catch (e) {
    SyncLog.stage('parse-fail', {'kind': 'RenditionReady', 'error': '$e'});
    return null;
  }
}

Map<String, dynamic>? _firstJsonMap(List<Object?>? args) {
  if (args == null || args.isEmpty) {
    return null;
  }
  return asJsonMap(args.first);
}
