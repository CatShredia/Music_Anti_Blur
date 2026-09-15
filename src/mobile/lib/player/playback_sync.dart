import 'playback_models.dart';

Map<String, dynamic>? asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return {for (final entry in value.entries) entry.key.toString(): entry.value};
  }
  return null;
}

bool shouldIgnoreRemoteSnapshot({
  required int localRevision,
  required int incomingRevision,
  required String? localDeviceId,
  required String? incomingDeviceId,
}) {
  if (incomingRevision <= localRevision) {
    return true;
  }
  if (localDeviceId != null &&
      localDeviceId.isNotEmpty &&
      incomingDeviceId != null &&
      incomingDeviceId == localDeviceId) {
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
  if (args == null || args.isEmpty) {
    return null;
  }
  final map = asJsonMap(args.first);
  return map == null ? null : PlaybackSnapshot.fromJson(map);
}
