import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../catalog/catalog_models.dart';
import 'library_models.dart';

/// Плейлисты и библиотека `/api/v1/me/playlists`, `/me/library`, `/playlists`.
extension LibraryApi on ApiClient {
  Future<PlaylistListItem> createPlaylist({
    required String title,
    String? description,
    bool isPublic = false,
  }) async {
    final res = await send(
      (d) => d.post('/api/v1/me/playlists', data: {
        'title': title,
        'description': description,
        'isPublic': isPublic,
      }),
    );
    return PlaylistListItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PlaylistListItem> updatePlaylist(
    String id, {
    String? title,
    String? description,
    bool? isPublic,
  }) async {
    final res = await send(
      (d) => d.put('/api/v1/me/playlists/$id', data: {
        'title': ?title,
        'description': ?description,
        'isPublic': ?isPublic,
      }),
    );
    return PlaylistListItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deletePlaylist(String id) => send((d) => d.delete('/api/v1/me/playlists/$id'));

  /// Свой плейлист или чужой публичный (для чужого — `/playlists/{id}`).
  Future<PlaylistDetail> playlist(String id, {String? cursor, int limit = 50, bool own = true}) async {
    final path = own ? '/api/v1/me/playlists/$id' : '/api/v1/playlists/$id';
    final res = await send(
      (d) => d.get(path, queryParameters: {'cursor': ?cursor, 'limit': limit}),
    );
    return PlaylistDetail.fromJson(res.data as Map<String, dynamic>);
  }

  /// Все треки плейлиста: дочитывает страницы по курсору.
  Future<PlaylistDetail> playlistAll(String id, {bool own = true}) async {
    var page = await playlist(id, own: own);
    final tracks = [...page.tracks];
    var cursor = page.nextCursor;
    while (cursor != null) {
      final next = await playlist(id, cursor: cursor, own: own);
      tracks.addAll(next.tracks);
      cursor = next.nextCursor;
    }
    return PlaylistDetail(
      id: page.id,
      title: page.title,
      kind: page.kind,
      trackCount: page.trackCount,
      createdAt: page.createdAt,
      updatedAt: page.updatedAt,
      tracks: tracks,
      description: page.description,
      isPublic: page.isPublic,
      isOwner: page.isOwner,
      ownerName: page.ownerName,
      inLibrary: page.inLibrary,
      coverUrls: page.coverUrls,
    );
  }

  Future<AddedTracks> addTracksToPlaylist(String playlistId, List<String> trackIds, {int? position}) async {
    final res = await send(
      (d) => d.post('/api/v1/me/playlists/$playlistId/tracks', data: {
        'trackIds': trackIds,
        'position': ?position,
      }),
    );
    return AddedTracks.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) =>
      send((d) => d.delete('/api/v1/me/playlists/$playlistId/tracks/$trackId'));

  Future<void> reorderPlaylist(String playlistId, List<String> trackIds) =>
      send((d) => d.put('/api/v1/me/playlists/$playlistId/tracks/order', data: {'trackIds': trackIds}));

  Future<LibraryPage> library({String type = 'all', String? cursor, int limit = 50}) async {
    final res = await send(
      (d) => d.get('/api/v1/me/library', queryParameters: {
        'type': type,
        'cursor': ?cursor,
        'limit': limit,
      }),
    );
    return LibraryPage.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> savePlaylistToLibrary(String id) => send((d) => d.put('/api/v1/me/library/playlists/$id'));

  Future<void> removePlaylistFromLibrary(String id) => send((d) => d.delete('/api/v1/me/library/playlists/$id'));

  Future<void> saveAlbumToLibrary(String id) => send((d) => d.put('/api/v1/me/library/albums/$id'));

  Future<void> removeAlbumFromLibrary(String id) => send((d) => d.delete('/api/v1/me/library/albums/$id'));

  Future<bool> albumInLibrary(String id) async {
    final res = await send((d) => d.get('/api/v1/me/library/albums/$id'));
    return (res.data as Map<String, dynamic>)['inLibrary'] as bool? ?? false;
  }

  /// https-ссылка с превью: `{api}/s/{type}/{id}`.
  String shareUrl(String type, String id) => '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/s/$type/$id';
}

@visibleForTesting
String joinShareUrl(String base, String type, String id) => '${base.replaceAll(RegExp(r'/+$'), '')}/s/$type/$id';
