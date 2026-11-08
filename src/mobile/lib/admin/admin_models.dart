class AdminTrackRow {
  AdminTrackRow({
    required this.id,
    required this.title,
    required this.trackNumber,
    required this.status,
    required this.readyRenditions,
    required this.totalRenditions,
    this.durationMs,
    this.isrc,
  });

  final String id;
  final String title;
  final int trackNumber;
  final int? durationMs;
  final String? isrc;

  /// none | processing | ready | failed
  final String status;
  final int readyRenditions;
  final int totalRenditions;

  factory AdminTrackRow.fromJson(Map<String, dynamic> json) => AdminTrackRow(
        id: json['id'] as String,
        title: json['title'] as String,
        trackNumber: (json['trackNumber'] as num).toInt(),
        durationMs: (json['durationMs'] as num?)?.toInt(),
        isrc: json['isrc'] as String?,
        status: json['status'] as String? ?? 'none',
        readyRenditions: (json['readyRenditions'] as num?)?.toInt() ?? 0,
        totalRenditions: (json['totalRenditions'] as num?)?.toInt() ?? 0,
      );
}

class DeletedTrack {
  DeletedTrack({
    required this.id,
    required this.title,
    required this.trackNumber,
    required this.artistName,
    required this.albumTitle,
    required this.deletedAt,
    required this.purgeAt,
  });

  final String id;
  final String title;
  final int trackNumber;
  final String artistName;
  final String albumTitle;
  final DateTime deletedAt;
  final DateTime purgeAt;

  factory DeletedTrack.fromJson(Map<String, dynamic> json) => DeletedTrack(
        id: json['id'] as String,
        title: json['title'] as String,
        trackNumber: (json['trackNumber'] as num).toInt(),
        artistName: (json['artist'] as Map<String, dynamic>)['name'] as String,
        albumTitle: (json['album'] as Map<String, dynamic>)['title'] as String,
        deletedAt: DateTime.parse(json['deletedAt'] as String),
        purgeAt: DateTime.parse(json['purgeAt'] as String),
      );
}

class AdminRendition {
  AdminRendition({
    required this.generationId,
    required this.code,
    required this.status,
    required this.isActive,
    this.bitrateKbps,
    this.errorMessage,
  });

  final String generationId;
  final String code;
  final String status;
  final bool isActive;
  final int? bitrateKbps;
  final String? errorMessage;

  bool get isFailed => status == 'failed';
  bool get isBusy => status == 'pending' || status == 'processing';

  factory AdminRendition.fromJson(Map<String, dynamic> json) => AdminRendition(
        generationId: json['generationId'] as String,
        code: json['code'] as String,
        status: json['status'] as String,
        isActive: json['isActive'] as bool? ?? false,
        bitrateKbps: (json['bitrateKbps'] as num?)?.toInt(),
        errorMessage: json['errorMessage'] as String?,
      );
}

/// Жанр справочника с числом связанных треков и альбомов.
class AdminGenre {
  AdminGenre({required this.id, required this.name, required this.albumCount, required this.trackCount});

  final String id;
  final String name;
  final int albumCount;
  final int trackCount;

  factory AdminGenre.fromJson(Map<String, dynamic> json) => AdminGenre(
        id: json['id'] as String,
        name: json['name'] as String,
        albumCount: json['albumCount'] as int? ?? 0,
        trackCount: json['trackCount'] as int? ?? 0,
      );
}
