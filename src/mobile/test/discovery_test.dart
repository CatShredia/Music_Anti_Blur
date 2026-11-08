import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:music_anti_blur/api/api_client.dart';
import 'package:music_anti_blur/catalog/catalog_models.dart';
import 'package:music_anti_blur/catalog/catalog_screens.dart';
import 'package:music_anti_blur/catalog/discovery_api.dart';
import 'package:music_anti_blur/catalog/discovery_screens.dart';
import 'package:music_anti_blur/theme.dart';

import 'support/fake_server.dart';

const _artistId = '11111111-1111-4111-8111-111111111111';
const _albumId = '22222222-2222-4222-8222-222222222222';
const _genreId = '33333333-3333-4333-8333-333333333333';

Map<String, dynamic> _popular(int n) => {
      'id': '44444444-4444-4444-8444-44444444444$n',
      'title': 'Hit $n',
      'trackNumber': n,
      'durationMs': 180000,
      'artistId': _artistId,
      'artistName': 'Band',
      'albumId': _albumId,
      'albumTitle': 'Record',
      'coverUrl': null,
      'coverUrlExpiresAt': null,
    };

Map<String, dynamic> _artist({List<Map<String, dynamic>>? popular}) => {
      'id': _artistId,
      'name': 'Band',
      'coverUrl': null,
      'albums': [
        {'id': _albumId, 'title': 'Record', 'year': 2003, 'coverObjectKey': null, 'coverUrl': null},
      ],
      'popular': popular ?? [for (var i = 1; i <= 5; i++) _popular(i)],
      'genres': [
        {'id': _genreId, 'name': 'Hard Rock'},
      ],
    };

Future<void> _pump(WidgetTester t, FakeServer server, String location) async {
  // Высокое окно: ListView строит только видимое, а проверять нужно весь экран.
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final api = server.client();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/search', builder: (_, _) => SearchScreen(api: api)),
      GoRoute(path: '/artist/:id', builder: (_, s) => ArtistScreen(api: api, id: s.pathParameters['id']!)),
      GoRoute(path: '/genre/:id', builder: (_, s) => GenreScreen(api: api, id: s.pathParameters['id']!)),
      GoRoute(path: '/album/:id', builder: (_, _) => const Scaffold(body: Text('album screen'))),
      GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('home screen'))),
    ],
  );
  await t.pumpWidget(MaterialApp.router(theme: VizeTheme.data(), routerConfig: router));
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _teardown(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  group('models', () {
    test('artist detail reads popular tracks and genres', () {
      final artist = ArtistDetail.fromJson(_artist());

      expect(artist.popular, hasLength(5));
      expect(artist.popular.first.title, 'Hit 1');
      expect(artist.genres.single.name, 'Hard Rock');
    });

    test('old server answer without new fields still parses', () {
      final artist = ArtistDetail.fromJson({'id': _artistId, 'name': 'Band', 'albums': <dynamic>[]});

      expect(artist.popular, isEmpty);
      expect(artist.genres, isEmpty);
    });

    test('search item knows the genre type', () {
      final item = SearchItem.fromJson({'type': 'genre', 'id': _genreId, 'title': 'Rock', 'subtitle': 'Жанр', 'rank': 0.5});

      expect(item.isGenre, isTrue);
    });

    test('genre detail parses albums and popular tracks', () {
      final genre = GenreDetail.fromJson({
        'id': _genreId,
        'name': 'Hard Rock',
        'albums': [
          {
            'id': _albumId,
            'title': 'Record',
            'year': 2003,
            'coverObjectKey': null,
            'coverUrl': null,
            'artist': {'id': _artistId, 'name': 'Band'},
          },
        ],
        'popularTracks': [_popular(1)],
      });

      expect(genre.albums.single.title, 'Record');
      expect(genre.popular.single.title, 'Hit 1');
    });
  });

  group('search history helpers', () {
    SearchHistoryItem item(String id, String query) => SearchHistoryItem(id: id, query: query);

    test('normalizeQuery ignores case and spaces', () {
      expect(normalizeQuery('  Linkin   PARK '), 'linkin park');
    });

    test('bumpHistory moves a repeat to the top without a duplicate', () {
      final items = [item('1', 'a b'), item('2', 'linkin park'), item('3', 'meteora')];

      final result = bumpHistory(items, item('4', 'Linkin Park'));

      expect(result.map((e) => e.id), ['4', '1', '3']);
    });

    test('bumpHistory keeps at most 50 entries, dropping the oldest', () {
      final items = [for (var i = 0; i < 50; i++) item('$i', 'query $i')];

      final result = bumpHistory(items, item('new', 'brand new'));

      expect(result, hasLength(50));
      expect(result.first.id, 'new');
      expect(result.last.id, '48');
    });
  });

  group('ArtistScreen', () {
    testWidgets('shows popular tracks, genres and discography', (t) async {
      final server = FakeServer({'GET /api/v1/artists/$_artistId': (200, _artist())});

      await _pump(t, server, '/artist/$_artistId');

      expect(t.takeException(), isNull);
      expect(find.text('Популярное'), findsOneWidget);
      expect(find.text('Hit 1'), findsOneWidget);
      expect(find.text('Hard Rock'), findsOneWidget);
      expect(find.text('Дискография'), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
      // Числа прослушиваний нигде не показываются.
      expect(find.textContaining('прослуш'), findsNothing);
      await _teardown(t);
    });

    testWidgets('without plays the popular block is hidden', (t) async {
      final server = FakeServer({'GET /api/v1/artists/$_artistId': (200, _artist(popular: []))});

      await _pump(t, server, '/artist/$_artistId');

      expect(t.takeException(), isNull);
      expect(find.text('Популярное'), findsNothing);
      expect(find.text('Дискография'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('"Показать все" loads the full popular list', (t) async {
      final server = FakeServer({
        'GET /api/v1/artists/$_artistId': (200, _artist()),
        'GET /api/v1/artists/$_artistId/popular': (200, {
          'items': [for (var i = 1; i <= 8; i++) _popular(i)],
        }),
      });

      await _pump(t, server, '/artist/$_artistId');
      await t.ensureVisible(find.text('Показать все'));
      await t.tap(find.text('Показать все'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, contains('GET /api/v1/artists/$_artistId/popular'));
      expect(find.text('Показать все'), findsNothing);
      await _teardown(t);
    });

    testWidgets('missing artist shows a message and a way back', (t) async {
      await _pump(t, FakeServer({}), '/artist/$_artistId');

      expect(t.takeException(), isNull);
      expect(find.text('Исполнитель не найден'), findsOneWidget);
      expect(find.text('Назад'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('server error offers a retry', (t) async {
      final server = FakeServer({'GET /api/v1/artists/$_artistId': (500, {'code': 'server_error'})});

      await _pump(t, server, '/artist/$_artistId');

      expect(t.takeException(), isNull);
      expect(find.text('Повторить'), findsOneWidget);
      await _teardown(t);
    });
  });

  group('GenreScreen', () {
    testWidgets('shows albums and popular tracks', (t) async {
      final server = FakeServer({
        'GET /api/v1/genres/$_genreId': (200, {
          'id': _genreId,
          'name': 'Hard Rock',
          'albums': [
            {
              'id': _albumId,
              'title': 'Record',
              'year': 2003,
              'coverObjectKey': null,
              'coverUrl': null,
              'artist': {'id': _artistId, 'name': 'Band'},
            },
          ],
          'popularTracks': [_popular(1)],
        }),
      });

      await _pump(t, server, '/genre/$_genreId');

      expect(t.takeException(), isNull);
      expect(find.text('Hard Rock'), findsWidgets);
      expect(find.text('Record'), findsOneWidget);
      expect(find.text('Hit 1'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('missing genre shows a message and a way back', (t) async {
      await _pump(t, FakeServer({}), '/genre/$_genreId');

      expect(t.takeException(), isNull);
      expect(find.text('Жанр не найден'), findsOneWidget);
      expect(find.text('Назад'), findsOneWidget);
      await _teardown(t);
    });
  });

  group('SearchScreen history', () {
    Map<String, (int, Object?)> routes({List<Map<String, String>>? history}) => {
          'GET /api/v1/me/search-history': (
            200,
            history ??
                [
                  {'id': 'h1', 'query': 'linkin park'},
                  {'id': 'h2', 'query': 'meteora'},
                ],
          ),
          'GET /api/v1/search': (200, {
            'items': [
              {'type': 'genre', 'id': _genreId, 'title': 'Hard Rock', 'subtitle': 'Жанр', 'rank': 0.4},
              {'type': 'artist', 'id': _artistId, 'title': 'Band', 'subtitle': null, 'rank': 0.9},
            ],
            'nextCursor': null,
          }),
          'POST /api/v1/me/search-history': (200, {'id': 'h3', 'query': 'rock'}),
        };

    testWidgets('shows saved queries when the field is empty', (t) async {
      await _pump(t, FakeServer(routes()), '/search');

      expect(t.takeException(), isNull);
      expect(find.text('Очистить'), findsOneWidget);
      expect(find.text('linkin park'), findsOneWidget);
      expect(find.text('meteora'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('removing an entry calls the server and hides it', (t) async {
      final server = FakeServer(routes());
      await _pump(t, server, '/search');

      await t.tap(find.byTooltip('Убрать из истории').first);
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, contains('DELETE /api/v1/me/search-history/h1'));
      expect(find.text('linkin park'), findsNothing);
      expect(find.text('meteora'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('"Очистить" wipes the whole history', (t) async {
      final server = FakeServer(routes());
      await _pump(t, server, '/search');

      await t.tap(find.text('Очистить'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, contains('DELETE /api/v1/me/search-history'));
      expect(find.text('Очистить'), findsNothing);
      expect(find.text('linkin park'), findsNothing);
      await _teardown(t);
    });

    testWidgets('tapping an entry searches and shows a genre result', (t) async {
      final server = FakeServer(routes());
      await _pump(t, server, '/search');

      await t.tap(find.text('meteora'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, contains('GET /api/v1/search'));
      expect(find.text('Hard Rock'), findsOneWidget);
      expect(find.text('Жанр'), findsOneWidget);
      // Успешный поиск с результатами записывается в историю.
      expect(server.requested, contains('POST /api/v1/me/search-history'));
      await _teardown(t);
    });

    testWidgets('a failed history load does not break search', (t) async {
      final server = FakeServer({
        'GET /api/v1/me/search-history': (500, {'code': 'server_error'}),
      });

      await _pump(t, server, '/search');

      expect(t.takeException(), isNull);
      expect(find.text('Очистить'), findsNothing);
      expect(find.text('Найти'), findsOneWidget);
      await _teardown(t);
    });
  });

  test('ApiException keeps the status for 404 detection', () {
    expect(ApiException(404, 'not_found', 'x').status, 404);
  });
}
