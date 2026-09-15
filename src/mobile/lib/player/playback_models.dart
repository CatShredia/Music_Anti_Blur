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

  factory PlaybackSnapshot.fromJson(Map<String, dynamic> json) => PlaybackSnapshot(
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        writerSessionId: json['writerSessionId']?.toString(),
        deviceId: json['deviceId']?.toString(),
        trackId: json['trackId']?.toString(),
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        isPlaying: json['isPlaying'] as bool? ?? false,
        qualityCode: json['qualityCode'] as String?,
        source: json['source'] as String?,
        queue: json['queue'] is Map
            ? PlayerQueue.fromJson(_stringKeyMap(json['queue'] as Map))
            : PlayerQueue.empty,
        updatedAt: _parseTime(json['updatedAt']),
      );
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

  factory CreatePlaybackSession.fromJson(Map<String, dynamic> json) => CreatePlaybackSession(
        writerSessionId: json['writerSessionId'] as String,
        snapshot: PlaybackSnapshot.fromJson(json['snapshot'] as Map<String, dynamic>),
      );
}

class DevicePresenceItem {
  DevicePresenceItem({required this.deviceId, this.lastSeen, this.name});

  final String deviceId;
  final DateTime? lastSeen;
  final String? name;

  factory DevicePresenceItem.fromJson(Map<String, dynamic> json) => DevicePresenceItem(
        deviceId: json['deviceId']?.toString() ?? '',
        lastSeen: json['lastSeen'] == null ? null : DateTime.tryParse(json['lastSeen'].toString())?.toUtc(),
        name: json['name'] as String?,
      );
}

class DevicePresence {
  DevicePresence({required this.devices});

  final List<DevicePresenceItem> devices;

  factory DevicePresence.fromJson(Map<String, dynamic> json) {
    final raw = json['devices'] as List<dynamic>? ?? const [];
    return DevicePresence(
      devices: [
        for (final item in raw)
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
        trackId: json['trackId']?.toString() ?? '',
        generationId: json['generationId']?.toString() ?? '',
        scope: json['scope'] as String? ?? '',
      );
}
