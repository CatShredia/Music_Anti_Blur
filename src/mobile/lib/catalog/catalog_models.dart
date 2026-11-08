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
  ArtistListItem({required this.id, required this.name, this.coverUrl});

  final String id;
  final String name;
  final String? coverUrl;

  factory ArtistListItem.fromJson(Map<String, dynamic> json) => ArtistListItem(
        id: json['id'] as String,
        name: json['name'] as String,
        coverUrl: json['coverUrl'] as String?,
      );
}

class ArtistAlbumItem {
  ArtistAlbumItem({
    required this.id,
    required this.title,
    this.year,
    this.coverObjectKey,
    this.coverUrl,
  });

  final String id;
  final String title;
  final int? year;
  final String? coverObjectKey;
  final String? coverUrl;

  factory ArtistAlbumItem.fromJson(Map<String, dynamic> json) => ArtistAlbumItem(
        id: json['id'] as String,
        title: json['title'] as String,
        year: json['year'] as int?,
        coverObjectKey: json['coverObjectKey'] as String?,
        coverUrl: json['coverUrl'] as String?,
      );
}

class ArtistDetail {
  ArtistDetail({
    required this.id,
    required this.name,
    required this.albums,
    this.coverUrl,
    this.popular = const [],
    this.genres = const [],
  });

  final String id;
  final String name;
  final String? coverUrl;
  final List<ArtistAlbumItem> albums;
  final List<PopularTrack> popular;
  final List<GenreRef> genres;

  /// Сколько популярных треков сервер отдаёт в самой странице исполнителя.
  static const popularPreview = 5;

  factory ArtistDetail.fromJson(Map<String, dynamic> json) => ArtistDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        coverUrl: json['coverUrl'] as String?,
        albums: (json['albums'] as List<dynamic>)
            .map((e) => ArtistAlbumItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        popular: PopularTrack.listFrom(json['popular']),
        genres: GenreRef.listFrom(json['genres']),
      );
}

class GenreRef {
  GenreRef({required this.id, required this.name});

  final String id;
  final String name;

  factory GenreRef.fromJson(Map<String, dynamic> json) =>
      GenreRef(id: json['id'] as String, name: json['name'] as String);

  static List<GenreRef> listFrom(Object? raw) =>
      (raw as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(GenreRef.fromJson).toList();
}

/// Трек в разделе «Популярное» (числа прослушиваний нет).
class PopularTrack {
  PopularTrack({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumTitle,
    this.durationMs,
    this.coverUrl,
  });

  final String id;
  final String title;
  final int? durationMs;
  final String artistId;
  final String artistName;
  final String albumId;
  final String albumTitle;
  final String? coverUrl;

  factory PopularTrack.fromJson(Map<String, dynamic> json) => PopularTrack(
        id: json['id'] as String,
        title: json['title'] as String,
        durationMs: json['durationMs'] as int?,
        artistId: json['artistId'] as String,
        artistName: json['artistName'] as String,
        albumId: json['albumId'] as String,
        albumTitle: json['albumTitle'] as String,
        coverUrl: json['coverUrl'] as String?,
      );

  static List<PopularTrack> listFrom(Object? raw) =>
      (raw as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(PopularTrack.fromJson).toList();
}

class AlbumListItem {
  AlbumListItem({
    required this.id,
    required this.title,
    required this.artist,
    this.year,
    this.coverObjectKey,
    this.coverUrl,
  });

  final String id;
  final String title;
  final int? year;
  final String? coverObjectKey;
  final String? coverUrl;
  final ArtistRef artist;

  factory AlbumListItem.fromJson(Map<String, dynamic> json) => AlbumListItem(
        id: json['id'] as String,
        title: json['title'] as String,
        year: json['year'] as int?,
        coverObjectKey: json['coverObjectKey'] as String?,
        coverUrl: json['coverUrl'] as String?,
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
    this.coverUrl,
    this.genres = const [],
  });

  final String id;
  final String title;
  final int? year;
  final String? coverObjectKey;
  final String? coverUrl;
  final ArtistRef artist;
  final List<TrackListItem> tracks;
  final List<GenreRef> genres;

  factory AlbumDetail.fromJson(Map<String, dynamic> json) => AlbumDetail(
        id: json['id'] as String,
        title: json['title'] as String,
        year: json['year'] as int?,
        coverObjectKey: json['coverObjectKey'] as String?,
        coverUrl: json['coverUrl'] as String?,
        artist: ArtistRef.fromJson(json['artist'] as Map<String, dynamic>),
        tracks: (json['tracks'] as List<dynamic>)
            .map((e) => TrackListItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        genres: GenreRef.listFrom(json['genres']),
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
    this.coverUrl,
    this.coverObjectKey,
    this.liked = false,
    this.genres = const [],
  });

  final String id;
  final String title;
  final int trackNumber;
  final int? durationMs;
  final String? isrc;
  final ArtistRef artist;
  final AlbumRef album;
  final List<TrackQuality> availableQualities;
  final String? coverUrl;
  final String? coverObjectKey;
  final bool liked;
  final List<GenreRef> genres;

  TrackDetail copyWith({bool? liked}) => TrackDetail(
        id: id,
        title: title,
        trackNumber: trackNumber,
        artist: artist,
        album: album,
        availableQualities: availableQualities,
        durationMs: durationMs,
        isrc: isrc,
        coverUrl: coverUrl,
        coverObjectKey: coverObjectKey,
        liked: liked ?? this.liked,
        genres: genres,
      );

  factory TrackDetail.fromJson(Map<String, dynamic> json) => TrackDetail(
        id: json['id'] as String,
        title: json['title'] as String,
        trackNumber: json['trackNumber'] as int,
        durationMs: json['durationMs'] as int?,
        isrc: json['isrc'] as String?,
        artist: ArtistRef.fromJson(json['artist'] as Map<String, dynamic>),
        album: AlbumRef.fromJson(json['album'] as Map<String, dynamic>),
        coverUrl: json['coverUrl'] as String?,
        coverObjectKey: json['coverObjectKey'] as String?,
        availableQualities: (json['availableQualities'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TrackQuality.fromJson)
            .toList(),
        liked: json['liked'] as bool? ?? false,
        genres: GenreRef.listFrom(json['genres']),
      );
}

class PlaylistListItem {
  PlaylistListItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.trackCount,
    required this.updatedAt,
    this.isPublic = false,
  });

  final String id;
  final String title;
  final String kind;
  final int trackCount;
  final DateTime updatedAt;
  final bool isPublic;

  bool get isLiked => kind == 'liked';

  factory PlaylistListItem.fromJson(Map<String, dynamic> json) => PlaylistListItem(
        id: json['id'] as String,
        title: json['title'] as String,
        kind: json['kind'] as String,
        trackCount: json['trackCount'] as int,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isPublic: json['isPublic'] as bool? ?? false,
      );
}

class LikedPlaylistTrack {
  LikedPlaylistTrack({
    required this.id,
    required this.title,
    required this.trackNumber,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumTitle,
    required this.likedAt,
    this.durationMs,
  });

  final String id;
  final String title;
  final int trackNumber;
  final int? durationMs;
  final String artistId;
  final String artistName;
  final String albumId;
  final String albumTitle;
  final DateTime likedAt;

  factory LikedPlaylistTrack.fromJson(Map<String, dynamic> json) => LikedPlaylistTrack(
        id: json['id'] as String,
        title: json['title'] as String,
        trackNumber: json['trackNumber'] as int,
        durationMs: json['durationMs'] as int?,
        artistId: json['artistId'] as String,
        artistName: json['artistName'] as String,
        albumId: json['albumId'] as String,
        albumTitle: json['albumTitle'] as String,
        likedAt: DateTime.parse((json['addedAt'] ?? json['likedAt']) as String),
      );
}

class PlaylistDetail {
  PlaylistDetail({
    required this.id,
    required this.title,
    required this.kind,
    required this.trackCount,
    required this.createdAt,
    required this.updatedAt,
    required this.tracks,
    this.nextCursor,
    this.description,
    this.isPublic = false,
    this.isOwner = true,
    this.ownerName,
    this.inLibrary = false,
    this.coverUrls = const [],
  });

  final String id;
  final String title;
  final String kind;
  final int trackCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<LikedPlaylistTrack> tracks;
  final String? nextCursor;
  final String? description;
  final bool isPublic;
  final bool isOwner;
  final String? ownerName;
  final bool inLibrary;
  final List<String> coverUrls;

  bool get isLiked => kind == 'liked';

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) => PlaylistDetail(
        id: json['id'] as String,
        title: json['title'] as String,
        kind: json['kind'] as String,
        trackCount: json['trackCount'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        tracks: (json['tracks'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LikedPlaylistTrack.fromJson)
            .toList(),
        nextCursor: json['nextCursor'] as String?,
        description: json['description'] as String?,
        isPublic: json['isPublic'] as bool? ?? false,
        isOwner: json['isOwner'] as bool? ?? true,
        ownerName: json['ownerName'] as String?,
        inLibrary: json['inLibrary'] as bool? ?? false,
        coverUrls: (json['coverUrls'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      );
}

class SearchItem {
  SearchItem({
    required this.type,
    required this.id,
    required this.title,
    required this.rank,
    this.subtitle,
    this.deleted = false,
  });

  final String type;
  final String id;
  final String title;
  final String? subtitle;
  final double rank;

  /// Только в админском поиске: трек лежит в корзине.
  final bool deleted;

  bool get isGenre => type == 'genre';

  factory SearchItem.fromJson(Map<String, dynamic> json) => SearchItem(
        type: json['type'] as String,
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        rank: (json['rank'] as num).toDouble(),
        deleted: json['deleted'] as bool? ?? false,
      );
}

class PlayHistoryItem {
  PlayHistoryItem({
    required this.id,
    required this.trackId,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumTitle,
    required this.playedAt,
    required this.playCount,
    this.coverUrl,
  });

  final String id;
  final String trackId;
  final String title;
  final String artistId;
  final String artistName;
  final String albumId;
  final String albumTitle;
  final String? coverUrl;
  final DateTime playedAt;
  final int playCount;

  factory PlayHistoryItem.fromJson(Map<String, dynamic> json) => PlayHistoryItem(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        title: json['title'] as String,
        artistId: json['artistId'] as String,
        artistName: json['artistName'] as String,
        albumId: json['albumId'] as String,
        albumTitle: json['albumTitle'] as String,
        coverUrl: json['coverUrl'] as String?,
        playedAt: DateTime.parse(json['playedAt'] as String),
        playCount: (json['playCount'] as num?)?.toInt() ?? 0,
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
