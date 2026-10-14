import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../catalog/catalog_models.dart';
import '../overrides/override_models.dart';
import '../player/playback_models.dart';
import '../validation/auth_rules.dart';

class ApiException implements Exception {
  ApiException(
    this.status,
    this.code,
    this.title, {
    this.errors = const {},
    this.retryAfterSeconds,
    this.snapshot,
  });

  final int status;
  final String code;
  final String title;
  final Map<String, List<String>> errors;
  final int? retryAfterSeconds;
  final PlaybackSnapshot? snapshot;

  Map<String, String> get fieldCodes {
    final out = <String, String>{};
    for (final entry in errors.entries) {
      if (entry.value.isNotEmpty) {
        out[entry.key] = entry.value.first;
      }
    }
    if (code == 'identifier_taken' &&
        !out.containsKey('login') &&
        !out.containsKey('email') &&
        !out.containsKey('identifier')) {
      out['login'] = AuthRules.identifierTaken;
      out['email'] = AuthRules.identifierTaken;
    }
    return out;
  }

  Map<String, String> get localizedFields => AuthMessages.localizeFields(fieldCodes);

  bool get hasFieldErrors => fieldCodes.isNotEmpty;

  bool get useBanner =>
      code != 'validation_failed' && !(code == 'invalid_token' && hasFieldErrors);

  String get localizedMessage =>
      AuthMessages.problem(code, retryAfterSeconds: retryAfterSeconds);

  @override
  String toString() => localizedMessage;
}

class Session {
  Session({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final UserDto user;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessExpiresAt: DateTime.parse(json['accessExpiresAt'] as String),
        refreshExpiresAt: DateTime.parse(json['refreshExpiresAt'] as String),
        user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
      );
}

class SettingsDto {
  SettingsDto({required this.preferredQuality});
  final String preferredQuality;

  factory SettingsDto.fromJson(Map<String, dynamic> json) =>
      SettingsDto(preferredQuality: json['preferredQuality'] as String);
}

class UserDto {
  UserDto({
    required this.id,
    this.login,
    this.email,
    required this.role,
    this.emailVerifiedAt,
  });

  final String id;
  final String? login;
  final String? email;
  final String role;
  final DateTime? emailVerifiedAt;

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
        id: json['id'] as String,
        login: json['login'] as String?,
        email: json['email'] as String?,
        role: json['role'] as String,
        emailVerifiedAt: json['emailVerifiedAt'] == null
            ? null
            : DateTime.parse(json['emailVerifiedAt'] as String),
      );
}

class ApiClient {
  ApiClient({String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: resolveBaseUrl(baseUrl),
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Content-Type': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.headers['X-Device-Id'] = await deviceId();
          final token = await _storage.read(key: _accessKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          final path = error.requestOptions.path;
          if (status == 401 &&
              !_refreshing &&
              !path.contains('/auth/login') &&
              !path.contains('/auth/refresh') &&
              !path.contains('/auth/register')) {
            _refreshing = true;
            try {
              final refreshed = await refresh();
              if (refreshed) {
                final req = error.requestOptions;
                req.headers['Authorization'] =
                    'Bearer ${await _storage.read(key: _accessKey)}';
                final clone = await _dio.fetch(req);
                _refreshing = false;
                return handler.resolve(clone);
              }
              await clearSession();
            } catch (_) {
              await clearSession();
            }
            _refreshing = false;
          }
          handler.next(error);
        },
      ),
    );
  }

  static const _accessKey = 'access';
  static const _refreshKey = 'refresh';
  static const _deviceKey = 'device';

  static String resolveBaseUrl(String? baseUrl) {
    if (baseUrl != null && baseUrl.isNotEmpty) {
      return baseUrl;
    }
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5080';
    }
    return 'http://127.0.0.1:5080';
  }

  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _refreshing = false;

  String get hubUrl {
    final base = _dio.options.baseUrl;
    return '$base/hubs/playback';
  }

  Future<String> deviceId() async {
    var id = await _storage.read(key: _deviceKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _storage.write(key: _deviceKey, value: id);
    }
    return id;
  }

  Future<String?> accessToken() => _storage.read(key: _accessKey);

  Future<void> saveSession(Session session) async {
    await _storage.write(key: _accessKey, value: session.accessToken);
    await _storage.write(key: _refreshKey, value: session.refreshToken);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  Future<bool> hasSession() async {
    try {
      final token = await _storage.read(key: _accessKey);
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<Session> register({
    required String login,
    required String email,
    required String password,
  }) async {
    final res = await _send(
      () => _dio.post(
        '/api/v1/auth/register',
        data: {
          'login': login,
          'email': email,
          'password': password,
        },
      ),
    );
    final session = Session.fromJson(res.data as Map<String, dynamic>);
    await saveSession(session);
    return session;
  }

  Future<Session> login({
    required String identifierType,
    required String identifier,
    required String password,
  }) async {
    final res = await _send(
      () => _dio.post(
        '/api/v1/auth/login',
        data: {
          'identifierType': identifierType,
          'identifier': identifier,
          'password': password,
        },
      ),
    );
    final session = Session.fromJson(res.data as Map<String, dynamic>);
    await saveSession(session);
    return session;
  }

  Future<bool> refresh() async {
    final refreshToken = await _storage.read(key: _refreshKey);
    if (refreshToken == null) {
      return false;
    }
    final res = await _dio.post(
      '/api/v1/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    if (res.statusCode == 200) {
      await saveSession(Session.fromJson(res.data as Map<String, dynamic>));
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    final refreshToken = await _storage.read(key: _refreshKey);
    try {
      await _dio.post('/api/v1/auth/logout', data: {'refreshToken': refreshToken});
    } catch (_) {}
    await clearSession();
  }

  Future<void> forgot(String email) async {
    await _send(() => _dio.post('/api/v1/auth/forgot-password', data: {'email': email}));
  }

  Future<void> reset({required String code, required String newPassword}) async {
    await _send(
      () => _dio.post(
        '/api/v1/auth/reset-password',
        data: {'code': code, 'newPassword': newPassword},
      ),
    );
  }

  Future<void> verify(String code) async {
    await _send(() => _dio.post('/api/v1/auth/email/verify', data: {'code': code}));
  }

  Future<void> resend(String email) async {
    await _send(() => _dio.post('/api/v1/auth/email/resend', data: {'email': email}));
  }

  Future<UserDto> me() async {
    final res = await _send(() => _dio.get('/api/v1/me'));
    return UserDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SettingsDto> settings() async {
    final res = await _send(() => _dio.get('/api/v1/me/settings'));
    return SettingsDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SettingsDto> updateSettings(String preferredQuality) async {
    final res = await _send(
      () => _dio.patch('/api/v1/me/settings', data: {'preferredQuality': preferredQuality}),
    );
    return SettingsDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CatalogPage<ArtistListItem>> listArtists({String? cursor, int limit = 20}) async {
    final res = await _send(
      () => _dio.get('/api/v1/artists', queryParameters: {
        'cursor': ?cursor,
        'limit': limit,
      }),
    );
    return CatalogPage.fromJson(res.data as Map<String, dynamic>, ArtistListItem.fromJson);
  }

  Future<ArtistDetail> artist(String id) async {
    final res = await _send(() => _dio.get('/api/v1/artists/$id'));
    return ArtistDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CatalogPage<AlbumListItem>> listAlbums({
    required String artistId,
    String? cursor,
    int limit = 20,
  }) async {
    final res = await _send(
      () => _dio.get('/api/v1/albums', queryParameters: {
        'artistId': artistId,
        'cursor': ?cursor,
        'limit': limit,
      }),
    );
    return CatalogPage.fromJson(res.data as Map<String, dynamic>, AlbumListItem.fromJson);
  }

  Future<AlbumDetail> album(String id) async {
    final res = await _send(() => _dio.get('/api/v1/albums/$id'));
    return AlbumDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TrackDetail> track(String id) async {
    final res = await _send(() => _dio.get('/api/v1/tracks/$id'));
    return TrackDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PlaybackUrl> playbackUrl({
    required String trackId,
    String sourcePreference = 'auto',
    required String qualityPreference,
    bool localAvailable = false,
  }) async {
    final res = await _send(
      () => _dio.post(
        '/api/v1/tracks/$trackId/playback-url',
        data: {
          'sourcePreference': sourcePreference,
          'qualityPreference': qualityPreference,
          'localAvailable': localAvailable,
        },
      ),
    );
    return PlaybackUrl.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> recordPlay(String trackId) async {
    await _send(() => _dio.post('/api/v1/me/plays', data: {'trackId': trackId}));
  }

  Future<CatalogPage<PlayHistoryItem>> playHistory({String? cursor, int limit = 20}) async {
    final res = await _send(
      () => _dio.get('/api/v1/me/history', queryParameters: {
        'cursor': ?cursor,
        'limit': limit,
      }),
    );
    return CatalogPage.fromJson(res.data as Map<String, dynamic>, PlayHistoryItem.fromJson);
  }

  Future<TrackOverride?> trackOverride(String trackId) async {
    try {
      final res = await _send(() => _dio.get('/api/v1/tracks/$trackId/override'));
      return TrackOverride.fromJson(res.data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.status == 404 || e.code == 'not_found') {
        return null;
      }
      rethrow;
    }
  }

  Future<TrackOverride> putTrackOverride({
    required String trackId,
    required String sourcePreference,
    String? displayName,
    int? durationMs,
    int? sizeBytes,
  }) async {
    final res = await _send(
      () => _dio.put(
        '/api/v1/tracks/$trackId/override',
        data: {
          'sourcePreference': sourcePreference,
          'displayName': displayName,
          'durationMs': durationMs,
          'sizeBytes': sizeBytes,
        },
      ),
    );
    return TrackOverride.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteTrackOverride(String trackId) async {
    await _send(() => _dio.delete('/api/v1/tracks/$trackId/override'));
  }

  Future<void> deletePrivateCopy(String trackId) async {
    await _send(() => _dio.delete('/api/v1/tracks/$trackId/private-copy'));
  }

  Future<InitiatePrivateUpload> initiatePrivateUpload({
    required String trackId,
    required String fileName,
    required int sizeBytes,
    required String contentType,
    required String checksumSha256,
  }) async {
    final res = await _send(
      () => _dio.post(
        '/api/v1/tracks/$trackId/private-uploads',
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

  Future<List<UploadPartUrl>> privateUploadParts({
    required String trackId,
    required String generationId,
    required List<int> partNumbers,
  }) async {
    final res = await _send(
      () => _dio.post(
        '/api/v1/tracks/$trackId/private-uploads/$generationId/parts',
        data: {'partNumbers': partNumbers},
      ),
    );
    final parts = (res.data as Map<String, dynamic>)['parts'] as List<dynamic>? ?? const [];
    return [
      for (final part in parts)
        if (part is Map<String, dynamic>) UploadPartUrl.fromJson(part),
    ];
  }

  Future<String> putPresignedPart(String url, List<int> bytes) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    try {
      final res = await dio.put<dynamic>(
        url,
        data: bytes,
        options: Options(
          contentType: 'application/octet-stream',
          headers: {Headers.contentLengthHeader: bytes.length},
        ),
      );
      final tag = res.headers.value('etag') ?? res.headers.value('ETag') ?? '';
      if (tag.isEmpty) {
        throw ApiException(409, 'invalid_state', 'Multipart complete failed.');
      }
      return tag.replaceAll('"', '');
    } on DioException catch (e) {
      throw _toApi(e);
    }
  }

  Future<void> completePrivateUpload({
    required String trackId,
    required String generationId,
    required List<({int partNumber, String eTag})> parts,
  }) async {
    await _send(
      () => _dio.post(
        '/api/v1/tracks/$trackId/private-uploads/$generationId/complete',
        data: {
          'parts': [
            for (final part in parts) {'partNumber': part.partNumber, 'eTag': part.eTag},
          ],
        },
        options: Options(headers: {'Idempotency-Key': const Uuid().v4()}),
      ),
    );
  }

  Future<PrivateUploadStatus> privateUploadStatus({
    required String trackId,
    required String generationId,
  }) async {
    final res = await _send(
      () => _dio.get('/api/v1/tracks/$trackId/private-uploads/$generationId'),
    );
    return PrivateUploadStatus.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PlaybackSnapshot> playbackState() async {
    final res = await _send(() => _dio.get('/api/v1/playback-state'));
    return PlaybackSnapshot.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CreatePlaybackSession> createPlaybackSession({required String deviceId}) async {
    final res = await _send(
      () => _dio.post('/api/v1/playback-sessions', data: {'deviceId': deviceId}),
    );
    return CreatePlaybackSession.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PlaybackSnapshot> claimPlaybackSession(
    String sessionId, {
    required int expectedRevision,
  }) async {
    final res = await _send(
      () => _dio.post(
        '/api/v1/playback-sessions/$sessionId/claim',
        data: {'expectedRevision': expectedRevision},
      ),
    );
    return PlaybackSnapshot.fromJson(res.data as Map<String, dynamic>);
  }

  Future<PlaybackSnapshot> putPlaybackState({
    required int expectedRevision,
    required String writerSessionId,
    required String kind,
    required Map<String, dynamic> state,
  }) async {
    final res = await _send(
      () => _dio.put(
        '/api/v1/playback-state',
        data: {
          'expectedRevision': expectedRevision,
          'writerSessionId': writerSessionId,
          'kind': kind,
          'state': state,
        },
      ),
    );
    return PlaybackSnapshot.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CatalogPage<SearchItem>> search(String q, {String? cursor, int limit = 20}) async {
    final res = await _send(
      () => _dio.get('/api/v1/search', queryParameters: {
        'q': q,
        'cursor': ?cursor,
        'limit': limit,
      }),
    );
    return CatalogPage.fromJson(res.data as Map<String, dynamic>, SearchItem.fromJson);
  }

  Future<Response<dynamic>> _send(Future<Response<dynamic>> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw _toApi(e);
    }
  }

  ApiException _toApi(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return ApiException(
        0,
        'connection_failed',
        'Cannot reach API at ${_dio.options.baseUrl}',
      );
    }
    final retryAfter = _retryAfter(e.response);
    final data = e.response?.data;
    if (data is Map) {
      return ApiException(
        e.response?.statusCode ?? 0,
        data['code'] as String? ?? 'error',
        data['title'] as String? ?? e.message ?? 'Request failed',
        errors: _parseErrors(data['errors']),
        retryAfterSeconds: retryAfter,
        snapshot: _parseSnapshot(data['snapshot']),
      );
    }
    if (data is String) {
      try {
        final map = jsonDecode(data) as Map<String, dynamic>;
        return ApiException(
          e.response?.statusCode ?? 0,
          map['code'] as String? ?? 'error',
          map['title'] as String? ?? 'Request failed',
          errors: _parseErrors(map['errors']),
          retryAfterSeconds: retryAfter,
          snapshot: _parseSnapshot(map['snapshot']),
        );
      } catch (_) {}
    }
    return ApiException(
      e.response?.statusCode ?? 0,
      'error',
      e.message ?? 'Request failed',
      retryAfterSeconds: retryAfter,
    );
  }

  static PlaybackSnapshot? _parseSnapshot(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return PlaybackSnapshot.fromJson(raw);
    }
    if (raw is Map) {
      return PlaybackSnapshot.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static Map<String, List<String>> _parseErrors(Object? raw) {
    if (raw is! Map) {
      return const {};
    }
    final out = <String, List<String>>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is List) {
        out[key] = value.map((e) => '$e').where((e) => e.isNotEmpty).toList();
      } else if (value is String && value.isNotEmpty) {
        out[key] = [value];
      }
    }
    return out;
  }

  static int? _retryAfter(Response<dynamic>? response) {
    final header = response?.headers.value('retry-after');
    return header == null ? null : int.tryParse(header);
  }
}
