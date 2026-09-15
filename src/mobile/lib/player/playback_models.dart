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
