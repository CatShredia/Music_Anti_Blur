import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:music_anti_blur/api/api_client.dart';
import 'package:music_anti_blur/library/library_screens.dart';
import 'package:music_anti_blur/theme.dart';

const _id = '112a94b8-e32e-478f-b922-0b076999abef';

/// Поддельный сервер: путь -> (статус, тело). Неизвестный путь -> 404.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.routes);

  final Map<String, (int, Object?)> routes;
  final requested = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requested.add(options.path);
    final (status, body) = routes[options.path] ?? (404, {'code': 'not_found'});
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeApi extends ApiClient {
  _FakeApi(Map<String, (int, Object?)> routes)
      : adapter = _FakeAdapter(routes),
        super(baseUrl: 'http://fake');

  final _FakeAdapter adapter;

  late final Dio _fake = Dio(BaseOptions(baseUrl: 'http://fake', headers: {'Content-Type': 'application/json'}))
    ..httpClientAdapter = adapter;

  @override
  Future<Response<dynamic>> send(Future<Response<dynamic>> Function(Dio dio) run) async {
    try {
      return await run(_fake);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      final code = data is Map && data['code'] is String ? data['code'] as String : 'request_failed';
      throw ApiException(status, code, code);
    }
  }
}

Map<String, dynamic> _playlist({bool isOwner = false}) => {
      'id': _id,
      'title': 'Public from smoke',
      'kind': 'user',
      'trackCount': 2,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-02T00:00:00Z',
      'description': 'hello',
      'isPublic': true,
      'isOwner': isOwner,
      'ownerName': 'smoke_user',
      'inLibrary': false,
      'coverUrls': ['http://fake/a.jpg', 'http://fake/b.jpg'],
      'tracks': [
        for (var i = 1; i <= 2; i++)
          {
            'id': '00000000-0000-4000-8000-00000000000$i',
            'title': 'Song $i',
            'trackNumber': i,
            'artistId': _id,
            'artistName': 'Artist',
            'albumId': _id,
            'albumTitle': 'Album',
            'addedAt': '2026-01-03T00:00:00Z',
          },
      ],
    };

Map<String, (int, Object?)> _routes(Map<String, (int, Object?)> extra) => {
      '/api/v1/me/library': (200, {'items': <dynamic>[], 'nextCursor': null}),
      ...extra,
    };

Future<void> _openLink(WidgetTester t, _FakeApi api, String link) async {
  final router = GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(path: '/library', builder: (_, _) => LibraryScreen(api: api)),
      GoRoute(
        path: '/playlist/:id',
        builder: (_, state) => PlaylistScreen(api: api, id: state.pathParameters['id']!),
      ),
      GoRoute(path: '/album/:id', builder: (_, _) => const Scaffold(body: Text('album screen'))),
    ],
  );
  await t.pumpWidget(MaterialApp.router(theme: VizeTheme.data(), routerConfig: router));
  await t.pump(const Duration(milliseconds: 300));

  await t.tap(find.byTooltip('Открыть по ссылке'));
  await t.pump(const Duration(milliseconds: 600));
  await t.enterText(find.byType(TextField), link);
  await t.tap(find.text('Открыть'));
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 600));
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('public playlist of another user opens from a link', (t) async {
    final api = _FakeApi(_routes({
      '/api/v1/playlists/$_id': (200, _playlist()),
    }));

    await _openLink(t, api, 'http://127.0.0.1:5080/s/playlist/$_id');

    expect(t.takeException(), isNull);
    expect(find.text('Public from smoke'), findsWidgets);
    expect(find.text('Song 1'), findsOneWidget);
    expect(api.adapter.requested, contains('/api/v1/playlists/$_id'));
  });

  testWidgets('own playlist with covers renders', (t) async {
    final api = _FakeApi(_routes({
      '/api/v1/me/playlists/$_id': (200, _playlist(isOwner: true)),
    }));

    await _openLink(t, api, 'musicantiblur://app/playlist/$_id');

    expect(t.takeException(), isNull);
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('missing playlist shows a clear message', (t) async {
    final api = _FakeApi(_routes({}));

    await _openLink(t, api, 'musicantiblur://app/playlist/$_id');

    expect(t.takeException(), isNull);
    expect(find.text('Плейлист не найден или стал приватным'), findsOneWidget);
    expect(find.text('К библиотеке'), findsOneWidget);
  });

  testWidgets('server error is shown with a retry button', (t) async {
    final api = _FakeApi(_routes({
      '/api/v1/me/playlists/$_id': (500, {'code': 'server_error'}),
    }));

    await _openLink(t, api, 'musicantiblur://app/playlist/$_id');

    expect(t.takeException(), isNull);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.text('Плейлист не найден или стал приватным'), findsNothing);
  });

  for (final (link, message) in [
    ('', 'Вставьте ссылку'),
    ('привет', 'Это не ссылка. Пример: https://…/s/playlist/…'),
    ('https://x/s/playlist/not-a-guid', 'В ссылке неверный идентификатор'),
    ('https://x/s/playlist', 'Ссылка неполная: не хватает идентификатора'),
    ('https://example.com/page', 'Ссылка должна вести на трек, альбом или плейлист'),
    ('musicantiblur://auth/verify', 'Ссылка должна вести на трек, альбом или плейлист'),
  ]) {
    testWidgets('bad link "$link" keeps the dialog open with a message', (t) async {
      final api = _FakeApi(_routes({}));

      await _openLink(t, api, link);

      expect(t.takeException(), isNull);
      expect(find.text(message), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(api.adapter.requested, isNot(contains('/api/v1/playlists/$_id')));
    });
  }
}
