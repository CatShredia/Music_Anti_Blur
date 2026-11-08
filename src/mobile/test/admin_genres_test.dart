import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:music_anti_blur/admin/admin_models.dart';
import 'package:music_anti_blur/admin/admin_screens.dart';
import 'package:music_anti_blur/catalog/catalog_models.dart';
import 'package:music_anti_blur/theme.dart';

import 'support/fake_server.dart';

const _albumId = '22222222-2222-4222-8222-222222222222';
const _artistId = '11111111-1111-4111-8111-111111111111';
const _rock = '33333333-3333-4333-8333-333333333331';
const _pop = '33333333-3333-4333-8333-333333333332';

final _genres = [
  {'id': _rock, 'name': 'Rock', 'albumCount': 2, 'trackCount': 7},
  {'id': _pop, 'name': 'Pop', 'albumCount': 0, 'trackCount': 0},
];

Future<void> _pump(WidgetTester t, FakeServer server, String location) async {
  t.view.physicalSize = const Size(1200, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final api = server.client();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/admin', builder: (_, _) => AdminArtistsScreen(api: api)),
      GoRoute(path: '/admin/genres', builder: (_, _) => AdminGenresScreen(api: api)),
      GoRoute(path: '/admin/album/:id', builder: (_, s) => AdminAlbumScreen(api: api, id: s.pathParameters['id']!)),
      GoRoute(path: '/admin/artist/:id', builder: (_, _) => const Scaffold(body: Text('artist screen'))),
      GoRoute(path: '/admin/trash', builder: (_, _) => const Scaffold(body: Text('trash screen'))),
    ],
  );
  // Scaffold нужен для SnackBar (в приложении его даёт оболочка админки).
  await t.pumpWidget(
    MaterialApp.router(
      theme: VizeTheme.data(),
      routerConfig: router,
      builder: (_, child) => Scaffold(body: child),
    ),
  );
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
  test('AdminGenre and SearchItem parse the new server fields', () {
    final genre = AdminGenre.fromJson({'id': _rock, 'name': 'Rock', 'albumCount': 2, 'trackCount': 7});
    final hit = SearchItem.fromJson({'type': 'track', 'id': _rock, 'title': 'x', 'rank': 0.2, 'deleted': true});
    final plain = SearchItem.fromJson({'type': 'track', 'id': _rock, 'title': 'x', 'rank': 0.2});

    expect(genre.trackCount, 7);
    expect(hit.deleted, isTrue);
    expect(plain.deleted, isFalse);
  });

  group('AdminGenresScreen', () {
    testWidgets('lists genres with counts', (t) async {
      final server = FakeServer({'GET /api/v1/admin/genres': (200, _genres)});

      await _pump(t, server, '/admin/genres');

      expect(t.takeException(), isNull);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('Треков: 7 · альбомов: 2'), findsOneWidget);
      expect(find.text('Pop'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('empty dictionary explains where genres come from', (t) async {
      final server = FakeServer({'GET /api/v1/admin/genres': (200, <dynamic>[])});

      await _pump(t, server, '/admin/genres');

      expect(t.takeException(), isNull);
      expect(find.textContaining('Жанров пока нет'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('deleting a used genre warns about affected tracks and albums', (t) async {
      final server = FakeServer({
        'GET /api/v1/admin/genres': (200, _genres),
        'DELETE /api/v1/admin/genres/$_rock': (200, {'tracks': 7, 'albums': 2}),
      });
      await _pump(t, server, '/admin/genres');

      await t.tap(find.byTooltip('Удалить').first);
      await _settle(t);
      expect(find.textContaining('Он будет снят у треков: 7, альбомов: 2'), findsOneWidget);

      await t.tap(find.text('Да'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, contains('DELETE /api/v1/admin/genres/$_rock'));
      await _teardown(t);
    });

    testWidgets('cancelling the delete dialog keeps the genre', (t) async {
      final server = FakeServer({'GET /api/v1/admin/genres': (200, _genres)});
      await _pump(t, server, '/admin/genres');

      await t.tap(find.byTooltip('Удалить').first);
      await _settle(t);
      await t.tap(find.text('Отмена'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested.where((r) => r.startsWith('DELETE')), isEmpty);
      await _teardown(t);
    });

    testWidgets('rename sends the new name', (t) async {
      final server = FakeServer({
        'GET /api/v1/admin/genres': (200, _genres),
        'PUT /api/v1/admin/genres/$_pop': (200, {'id': _pop, 'name': 'Pop Rock'}),
      });
      await _pump(t, server, '/admin/genres');

      await t.tap(find.byTooltip('Переименовать').last);
      await _settle(t);
      await t.enterText(find.byType(TextField).last, 'Pop Rock');
      await t.tap(find.text('Сохранить'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, contains('PUT /api/v1/admin/genres/$_pop'));
      await _teardown(t);
    });

    testWidgets('a duplicate name from the server is reported without crashing', (t) async {
      final server = FakeServer({
        'GET /api/v1/admin/genres': (200, _genres),
        'POST /api/v1/admin/genres': (409, {'code': 'genre_exists', 'title': 'exists'}),
      });
      await _pump(t, server, '/admin/genres');

      await t.tap(find.text('Жанр'));
      await _settle(t);
      await t.enterText(find.byType(TextField).last, 'rock');
      await t.tap(find.text('Сохранить'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(find.byType(SnackBar), findsOneWidget);
      await _teardown(t);
    });
  });

  group('admin search', () {
    Map<String, (int, Object?)> routes() => {
          'GET /api/v1/artists': (200, {'items': <dynamic>[], 'nextCursor': null}),
          'GET /api/v1/admin/search': (200, {
            'items': [
              {'type': 'track', 'id': _rock, 'title': 'Old Song', 'subtitle': 'Band · Record', 'rank': 0.9, 'deleted': true},
              {'type': 'artist', 'id': _artistId, 'title': 'Band', 'subtitle': null, 'rank': 0.8, 'deleted': false},
              {'type': 'genre', 'id': _pop, 'title': 'Pop', 'subtitle': 'Жанр', 'rank': 0.3, 'deleted': false},
            ],
            'nextCursor': null,
          }),
        };

    testWidgets('shows deleted tracks flagged and other types labelled', (t) async {
      final server = FakeServer(routes());
      await _pump(t, server, '/admin');

      await t.enterText(find.byType(TextField), 'song');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, contains('GET /api/v1/admin/search'));
      expect(find.text('Old Song'), findsOneWidget);
      expect(find.text('удалён'), findsOneWidget);
      expect(find.text('Трек · Band · Record'), findsOneWidget);
      expect(find.text('Исполнитель'), findsWidgets);
      expect(find.text('Жанр'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('a deleted track opens the trash', (t) async {
      final server = FakeServer(routes());
      await _pump(t, server, '/admin');

      await t.enterText(find.byType(TextField), 'song');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await _settle(t);
      await t.tap(find.text('Old Song'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(find.text('trash screen'), findsOneWidget);
      await _teardown(t);
    });

    testWidgets('a one-letter query does not call the server', (t) async {
      final server = FakeServer(routes());
      await _pump(t, server, '/admin');

      await t.enterText(find.byType(TextField), 'a');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, isNot(contains('GET /api/v1/admin/search')));
      await _teardown(t);
    });

    testWidgets('reset returns to the artist list', (t) async {
      final server = FakeServer(routes());
      await _pump(t, server, '/admin');

      await t.enterText(find.byType(TextField), 'song');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await _settle(t);
      await t.tap(find.byTooltip('Сбросить'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(find.text('Old Song'), findsNothing);
      await _teardown(t);
    });
  });

  group('album genres', () {
    Map<String, (int, Object?)> routes({List<Map<String, String>> genres = const []}) => {
          'GET /api/v1/albums/$_albumId': (200, {
            'id': _albumId,
            'title': 'Record',
            'year': 2003,
            'coverObjectKey': null,
            'coverUrl': null,
            'artist': {'id': _artistId, 'name': 'Band'},
            'tracks': <dynamic>[],
            'genres': genres,
          }),
          'GET /api/v1/admin/albums/$_albumId/tracks': (200, <dynamic>[]),
          'GET /api/v1/admin/genres': (200, _genres),
          'PUT /api/v1/admin/albums/$_albumId/genres': (200, <dynamic>[]),
        };

    testWidgets('the button shows current genres and the picker saves a new set', (t) async {
      final server = FakeServer(routes(genres: [
        {'id': _rock, 'name': 'Rock'},
      ]));
      await _pump(t, server, '/admin/album/$_albumId');

      expect(find.text('Жанры: Rock'), findsOneWidget);
      await t.tap(find.text('Жанры: Rock'));
      await _settle(t);
      expect(find.text('Жанры (1/10)'), findsOneWidget);

      await t.tap(find.text('Pop'));
      await _settle(t);
      expect(find.text('Жанры (2/10)'), findsOneWidget);
      await t.tap(find.text('Сохранить'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested, contains('PUT /api/v1/admin/albums/$_albumId/genres'));
      await _teardown(t);
    });

    testWidgets('cancelling the picker changes nothing', (t) async {
      final server = FakeServer(routes());
      await _pump(t, server, '/admin/album/$_albumId');

      await t.tap(find.text('Жанры'));
      await _settle(t);
      await t.tap(find.text('Отмена'));
      await _settle(t);

      expect(t.takeException(), isNull);
      expect(server.requested.where((r) => r.startsWith('PUT')), isEmpty);
      await _teardown(t);
    });
  });
}
