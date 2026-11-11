import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../catalog/catalog_models.dart';
import '../overrides/override_models.dart';
import 'admin_models.dart';

/// Админ-эндпоинты `/api/v1/admin/*` поверх общего [ApiClient].
extension AdminApi on ApiClient {
  Future<void> adminCreateArtist(String name) =>
      send((d) => d.post('/api/v1/admin/artists', data: {'name': name}));

  /// Создаёт исполнителя и возвращает его id.
  Future<String> adminCreateArtistId(String name) async {
    final res = await send((d) => d.post('/api/v1/admin/artists', data: {'name': name}));
    return (res.data as Map<String, dynamic>)['id'] as String;
  }

  Future<void> adminUpdateArtist(String id, String name) =>
      send((d) => d.put('/api/v1/admin/artists/$id', data: {'name': name}));

  /// [cascade]: вместе с альбомами и треками (они уходят в корзину).
  Future<void> adminDeleteArtist(String id, {bool cascade = false}) => send((d) => d.delete(
        '/api/v1/admin/artists/$id',
        queryParameters: cascade ? {'cascade': true} : null,
      ));

  Future<String> adminCreateAlbum({
    required String artistId,
    required String title,
    int? year,
  }) async {
    final res = await send(
      (d) => d.post('/api/v1/admin/albums', data: {'artistId': artistId, 'title': title, 'year': year}),
    );
    return (res.data as Map<String, dynamic>)['id'] as String;
  }

  Future<void> adminUpdateAlbum({
    required String id,
    required String artistId,
    required String title,
    int? year,
    String? coverObjectKey,
  }) =>
      send(
        (d) => d.put('/api/v1/admin/albums/$id', data: {
          'artistId': artistId,
          'title': title,
          'year': year,
          'coverObjectKey': coverObjectKey,
        }),
      );

  Future<void> adminDeleteAlbum(String id, {bool cascade = false}) => send((d) => d.delete(
        '/api/v1/admin/albums/$id',
        queryParameters: cascade ? {'cascade': true} : null,
      ));

  Future<void> adminRestoreAlbum(String id) => send((d) => d.post('/api/v1/admin/albums/$id/restore'));

  Future<List<DeletedAlbum>> adminDeletedAlbums() async {
    final res = await send((d) => d.get('/api/v1/admin/albums/deleted'));
    return [
      for (final row in res.data as List<dynamic>) DeletedAlbum.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<void> adminUploadCover({
    required String albumId,
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) =>
      send(
        (d) => d.put(
          '/api/v1/admin/albums/$albumId/cover',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes(
              bytes,
              filename: fileName,
              contentType: DioMediaType.parse(contentType),
            ),
          }),
          options: Options(contentType: 'multipart/form-data'),
        ),
      );

  Future<String> adminCreateTrack({
    required String albumId,
    required String artistId,
    required String title,
    required int trackNumber,
    int? durationMs,
    String? isrc,
  }) async {
    final res = await send(
      (d) => d.post('/api/v1/admin/tracks', data: {
        'albumId': albumId,
        'artistId': artistId,
        'title': title,
        'trackNumber': trackNumber,
        'durationMs': durationMs,
        'isrc': isrc,
      }),
    );
    return (res.data as Map<String, dynamic>)['id'] as String;
  }

  Future<void> adminUpdateTrack({
    required String id,
    required String albumId,
    required String artistId,
    required String title,
    required int trackNumber,
    int? durationMs,
    String? isrc,
  }) =>
      send(
        (d) => d.put('/api/v1/admin/tracks/$id', data: {
          'albumId': albumId,
          'artistId': artistId,
          'title': title,
          'trackNumber': trackNumber,
          'durationMs': durationMs,
          'isrc': isrc,
        }),
      );

  Future<void> adminDeleteTrack(String id) => send((d) => d.delete('/api/v1/admin/tracks/$id'));

  Future<void> adminRestoreTrack(String id) => send((d) => d.post('/api/v1/admin/tracks/$id/restore'));

  Future<List<DeletedTrack>> adminDeletedTracks() async {
    final res = await send((d) => d.get('/api/v1/admin/tracks/deleted'));
    return [
      for (final row in res.data as List<dynamic>) DeletedTrack.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<List<AdminTrackRow>> adminAlbumTracks(String albumId) async {
    final res = await send((d) => d.get('/api/v1/admin/albums/$albumId/tracks'));
    return [
      for (final row in res.data as List<dynamic>) AdminTrackRow.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<List<AdminRendition>> adminRenditions(String trackId) async {
    final res = await send((d) => d.get('/api/v1/admin/tracks/$trackId/renditions'));
    return [
      for (final row in res.data as List<dynamic>) AdminRendition.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<void> adminRetranscode(String trackId, {String? generationId}) => send(
        (d) => d.post(
          '/api/v1/admin/tracks/$trackId/transcode',
          data: {'generationId': generationId},
        ),
      );

  Future<InitiatePrivateUpload> adminInitiateUpload({
    required String trackId,
    required String fileName,
    required int sizeBytes,
    required String contentType,
    required String checksumSha256,
  }) async {
    final res = await send(
      (d) => d.post(
        '/api/v1/admin/tracks/$trackId/uploads',
        data: {
          'fileName': fileName,
          'sizeBytes': sizeBytes,
          'contentType': contentType,
          'checksumSha256': checksumSha256,
        },
        options: Options(headers: {'Idempotency-Key': const Uuid().v4()}),
      ),
    );
    return InitiatePrivateUpload.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<UploadPartUrl>> adminUploadParts({
    required String trackId,
    required String generationId,
    required List<int> partNumbers,
  }) async {
    final res = await send(
      (d) => d.post(
        '/api/v1/admin/tracks/$trackId/uploads/$generationId/parts',
        data: {'partNumbers': partNumbers},
      ),
    );
    final parts = (res.data as Map<String, dynamic>)['parts'] as List<dynamic>? ?? const [];
    return [
      for (final part in parts)
        if (part is Map<String, dynamic>) UploadPartUrl.fromJson(part),
    ];
  }

  Future<void> adminCompleteUpload({
    required String trackId,
    required String generationId,
    required List<({int partNumber, String eTag})> parts,
  }) =>
      send(
        (d) => d.post(
          '/api/v1/admin/tracks/$trackId/uploads/$generationId/complete',
          data: {
            'parts': [
              for (final part in parts) {'partNumber': part.partNumber, 'eTag': part.eTag},
            ],
          },
          options: Options(headers: {'Idempotency-Key': const Uuid().v4()}),
        ),
      );

  Future<PrivateUploadStatus> adminUploadStatus({
    required String trackId,
    required String generationId,
  }) async {
    final res = await send((d) => d.get('/api/v1/admin/tracks/$trackId/uploads/$generationId'));
    return PrivateUploadStatus.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> adminCancelUpload({required String trackId, required String generationId}) =>
      send((d) => d.delete('/api/v1/admin/tracks/$trackId/uploads/$generationId'));

  Future<List<AdminGenre>> adminGenres() async {
    final res = await send((d) => d.get('/api/v1/admin/genres'));
    return [
      for (final row in res.data as List<dynamic>) AdminGenre.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<void> adminCreateGenre(String name) => send((d) => d.post('/api/v1/admin/genres', data: {'name': name}));

  Future<void> adminRenameGenre(String id, String name) =>
      send((d) => d.put('/api/v1/admin/genres/$id', data: {'name': name}));

  Future<void> adminDeleteGenre(String id) => send((d) => d.delete('/api/v1/admin/genres/$id'));

  Future<void> adminSetAlbumGenres(String albumId, List<String> genreIds) =>
      send((d) => d.put('/api/v1/admin/albums/$albumId/genres', data: {'genreIds': genreIds}));

  Future<void> adminSetTrackGenres(String trackId, List<String> genreIds) =>
      send((d) => d.put('/api/v1/admin/tracks/$trackId/genres', data: {'genreIds': genreIds}));

  /// Поиск для админа: треки из корзины тоже в выдаче (`deleted`).
  Future<List<SearchItem>> adminSearch(String query) async {
    final res = await send((d) => d.get('/api/v1/admin/search', queryParameters: {'q': query, 'limit': 50}));
    final items = (res.data as Map<String, dynamic>)['items'] as List<dynamic>? ?? const [];
    return [
      for (final row in items)
        if (row is Map<String, dynamic>) SearchItem.fromJson(row),
    ];
  }
}
