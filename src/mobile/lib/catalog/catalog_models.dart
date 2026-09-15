class ArtistRef {
  ArtistRef({required this.id, required this.name});

  final String id;
  final String name;

  factory ArtistRef.fromJson(Map<String, dynamic> json) => ArtistRef(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class AlbumRef {
  AlbumRef({required this.id, required this.title});

  final String id;
  final String title;

  factory AlbumRef.fromJson(Map<String, dynamic> json) => AlbumRef(
        id: json['id'] as String,
        title: json['title'] as String,
      );
}

class ArtistListItem {
  ArtistListItem({required this.id, required this.name});

  final String id;
  final String name;

  factory ArtistListItem.fromJson(Map<String, dynamic> json) => ArtistListItem(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class ArtistAlbumItem {
  ArtistAlbumItem({required this.id, required this.title, this.year});

  final String id;
  final String title;
  final int? year;

  factory ArtistAlbumItem.fromJson(Map<String, dynamic> json) => ArtistAlbumItem(
        id: json['id'] as String,
        title: json['title'] as String,
        year: json['year'] as int?,
      );
}

class ArtistDetail {
  ArtistDetail({required this.id, required this.name, required this.albums});

  final String id;
  final String name;
  final List<ArtistAlbumItem> albums;

  factory ArtistDetail.fromJson(Map<String, dynamic> json) => ArtistDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        albums: (json['albums'] as List<dynamic>)
            .map((e) => ArtistAlbumItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AlbumListItem {
  AlbumListItem({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.coverObjectKey,
  });

  final String id;
  final String title;
  final int? year;
  final String? coverObjectKey;
  final ArtistRef artist;

  factory AlbumListItem.fromJson(Map<String, dynamic> json) => AlbumListItem(
        id: json['id'] as String,
        title: json['title'] as String,
        year: json['year'] as int?,
        coverObjectKey: json['coverObjectKey'] as String?,
        artist: ArtistRef.fromJson(json['artist'] as Map<String, dynamic>),
      );
}

class TrackListItem {
  TrackListItem({
    required this.id,
    required this.title,
    required this.trackNumber,
    this.durationMs,
    this.isrc,
  });

  final String id;
  final String title;
  final int trackNumber;
  final int? durationMs;
  final String? isrc;

  factory TrackListItem.fromJson(Map<String, dynamic> json) => TrackListItem(
        id: json['id'] as String,
        title: json['title'] as String,
        trackNumber: json['trackNumber'] as int,
        durationMs: json['durationMs'] as int?,
        isrc: json['isrc'] as String?,
      );
}

class AlbumDetail {
  AlbumDetail({
    required this.id,
    required this.title,
    required this.artist,
    required this.tracks,
    this.year,
    this.coverObjectKey,
  });

  final String id;
  final String title;
  final int? year;
  final String? coverObjectKey;
  final ArtistRef artist;
  final List<TrackListItem> tracks;

  factory AlbumDetail.fromJson(Map<String, dynamic> json) => AlbumDetail(
        id: json['id'] as String,
        title: json['title'] as String,
        year: json['year'] as int?,
        coverObjectKey: json['coverObjectKey'] as String?,
        artist: ArtistRef.fromJson(json['artist'] as Map<String, dynamic>),
        tracks: (json['tracks'] as List<dynamic>)
            .map((e) => TrackListItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TrackQuality {
  TrackQuality({required this.code, required this.bitrateKbps});

  final String code;
  final int bitrateKbps;

  factory TrackQuality.fromJson(Map<String, dynamic> json) => TrackQuality(
        code: json['code'] as String,
        bitrateKbps: json['bitrateKbps'] as int,
      );

  String get label => '$code · $bitrateKbps kbps';
}

class TrackDetail {
  TrackDetail({
    required this.id,
    required this.title,
    required this.trackNumber,
    required this.artist,
    required this.album,
    required this.availableQualities,
    this.durationMs,
    this.isrc,
  });

  final String id;
  final String title;
  final int trackNumber;
  final int? durationMs;
  final String? isrc;
  final ArtistRef artist;
  final AlbumRef album;
  final List<TrackQuality> availableQualities;

  factory TrackDetail.fromJson(Map<String, dynamic> json) => TrackDetail(
        id: json['id'] as String,
        title: json['title'] as String,
        trackNumber: json['trackNumber'] as int,
        durationMs: json['durationMs'] as int?,
        isrc: json['isrc'] as String?,
        artist: ArtistRef.fromJson(json['artist'] as Map<String, dynamic>),
        album: AlbumRef.fromJson(json['album'] as Map<String, dynamic>),
        availableQualities: (json['availableQualities'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TrackQuality.fromJson)
            .toList(),
      );
}

class SearchItem {
  SearchItem({
    required this.type,
    required this.id,
    required this.title,
    required this.rank,
    this.subtitle,
  });

  final String type;
  final String id;
  final String title;
  final String? subtitle;
  final double rank;

  factory SearchItem.fromJson(Map<String, dynamic> json) => SearchItem(
        type: json['type'] as String,
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        rank: (json['rank'] as num).toDouble(),
      );
}

class CatalogPage<T> {
  CatalogPage({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  factory CatalogPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) map,
  ) =>
      CatalogPage(
        items: (json['items'] as List<dynamic>)
            .map((e) => map(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

class PlaybackUrl {
  PlaybackUrl({
    required this.resolvedSource,
    required this.delivery,
    this.resolvedQuality,
    this.url,
    this.expiresAt,
    this.generationId,
    this.durationMs,
    this.qualityFallbackFrom,
    this.fallbackReason,
  });

  final String resolvedSource;
  final String delivery;
  final String? resolvedQuality;
  final String? url;
  final DateTime? expiresAt;
  final String? generationId;
  final int? durationMs;
  final String? qualityFallbackFrom;
  final String? fallbackReason;

  bool get isLocal => delivery == 'local' || resolvedSource == 'local';

  factory PlaybackUrl.fromJson(Map<String, dynamic> json) => PlaybackUrl(
        resolvedSource: json['resolvedSource'] as String,
        delivery: json['delivery'] as String? ?? json['resolvedSource'] as String,
        resolvedQuality: json['resolvedQuality'] as String?,
        url: json['url'] as String?,
        expiresAt: json['expiresAt'] == null ? null : DateTime.parse(json['expiresAt'] as String),
        generationId: json['generationId'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt(),
        qualityFallbackFrom: json['qualityFallbackFrom'] as String?,
        fallbackReason: json['fallbackReason'] as String?,
      );
}

String formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) {
    return '—';
  }
  final total = Duration(milliseconds: durationMs);
  final minutes = total.inMinutes;
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
