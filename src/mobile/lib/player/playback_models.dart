import 'player_queue.dart';

class PlaybackSnapshot {
  PlaybackSnapshot({
    required this.revision,
    required this.positionMs,
    required this.isPlaying,
    required this.queue,
    this.writerSessionId,
    this.deviceId,
    this.trackId,
    this.qualityCode,
    this.source,
    this.updatedAt,
  });

  final int revision;
  final String? writerSessionId;
  final String? deviceId;
  final String? trackId;
  final int positionMs;
  final bool isPlaying;
  final String? qualityCode;
  final String? source;
  final PlayerQueue queue;
  final DateTime? updatedAt;

  factory PlaybackSnapshot.fromJson(Map<String, dynamic> json) {
    final queueRaw = jsonValue(json, 'queue');
    return PlaybackSnapshot(
      revision: jsonInt(json, 'revision'),
      writerSessionId: jsonString(json, 'writerSessionId'),
      deviceId: jsonString(json, 'deviceId'),
      trackId: jsonString(json, 'trackId'),
      positionMs: jsonInt(json, 'positionMs'),
      isPlaying: jsonBool(json, 'isPlaying'),
      qualityCode: jsonString(json, 'qualityCode'),
      source: jsonString(json, 'source'),
      queue: queueRaw is Map ? PlayerQueue.fromJson(_stringKeyMap(queueRaw)) : PlayerQueue.empty,
      updatedAt: _parseTime(jsonValue(json, 'updatedAt')),
    );
  }
}

Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> value) => {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };

DateTime? _parseTime(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString())?.toUtc();
}

class CreatePlaybackSession {
  CreatePlaybackSession({required this.writerSessionId, required this.snapshot});

  final String writerSessionId;
  final PlaybackSnapshot snapshot;

  factory CreatePlaybackSession.fromJson(Map<String, dynamic> json) {
    final raw = jsonValue(json, 'snapshot');
    if (raw is! Map) {
      throw FormatException('playback session snapshot');
    }
    return CreatePlaybackSession(
      writerSessionId: jsonString(json, 'writerSessionId') ?? '',
      snapshot: PlaybackSnapshot.fromJson(_stringKeyMap(raw)),
    );
  }
}

class DevicePresenceItem {
  DevicePresenceItem({required this.deviceId, this.lastSeen, this.name});

  final String deviceId;
  final DateTime? lastSeen;
  final String? name;

  factory DevicePresenceItem.fromJson(Map<String, dynamic> json) => DevicePresenceItem(
        deviceId: jsonString(json, 'deviceId') ?? '',
        lastSeen: _parseTime(jsonValue(json, 'lastSeen')),
        name: jsonString(json, 'name'),
      );
}

class DevicePresence {
  DevicePresence({required this.devices});

  final List<DevicePresenceItem> devices;

  factory DevicePresence.fromJson(Map<String, dynamic> json) {
    final raw = jsonValue(json, 'devices');
    final items = raw is Iterable ? raw : const [];
    return DevicePresence(
      devices: [
        for (final item in items)
          if (item is Map)
            DevicePresenceItem.fromJson({
              for (final entry in item.entries) entry.key.toString(): entry.value,
            }),
      ],
    );
  }
}

class RenditionReady {
  RenditionReady({
    required this.trackId,
    required this.generationId,
    required this.scope,
  });

  final String trackId;
  final String generationId;
  final String scope;

  factory RenditionReady.fromJson(Map<String, dynamic> json) => RenditionReady(
        trackId: jsonString(json, 'trackId') ?? '',
        generationId: jsonString(json, 'generationId') ?? '',
        scope: jsonString(json, 'scope') ?? '',
      );
}

Object? jsonValue(Map<String, dynamic> json, String camel) =>
    json[camel] ?? json[_pascalKey(camel)];

String? jsonString(Map<String, dynamic> json, String camel) {
  final value = jsonValue(json, camel);
  if (value == null) {
    return null;
  }
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int jsonInt(Map<String, dynamic> json, String camel) {
  final value = jsonValue(json, camel);
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool jsonBool(Map<String, dynamic> json, String camel) {
  final value = jsonValue(json, camel);
  if (value is bool) {
    return value;
  }
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1';
}

String _pascalKey(String camel) {
  if (camel.isEmpty) {
    return camel;
  }
  return '${camel[0].toUpperCase()}${camel.substring(1)}';
}
