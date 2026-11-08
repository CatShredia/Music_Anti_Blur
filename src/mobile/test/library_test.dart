import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:music_anti_blur/api/api_client.dart';
import 'package:music_anti_blur/catalog/catalog_models.dart';
import 'package:music_anti_blur/library/deep_link.dart';
import 'package:music_anti_blur/library/library_api.dart';
import 'package:music_anti_blur/library/library_models.dart';
import 'package:music_anti_blur/library/library_screens.dart';
import 'package:music_anti_blur/theme.dart';

const _id = '3f2b8c1e-aaaa-4bbb-8ccc-0123456789ab';

void main() {
  group('routeForLink', () {
    test('app scheme with host app', () {
      expect(routeForLink(Uri.parse('musicantiblur://app/playlist/$_id')), '/playlist/$_id');
      expect(routeForLink(Uri.parse('musicantiblur://app/album/$_id')), '/album/$_id');
      expect(routeForLink(Uri.parse('musicantiblur://app/track/$_id')), '/track/$_id');
    });

    test('app scheme with type as host', () {
      expect(routeForLink(Uri.parse('musicantiblur://playlist/$_id')), '/playlist/$_id');
    });

    test('https preview link', () {
      expect(routeForLink(Uri.parse('https://api.example.com/s/playlist/$_id')), '/playlist/$_id');
    });

    test('plain path forms', () {
      expect(routeForLink(Uri.parse('/album/$_id')), '/album/$_id');
      expect(routeForLink(Uri.parse('/s/track/$_id')), '/track/$_id');
    });

    test('id is lowercased', () {
      expect(routeForLink(Uri.parse('musicantiblur://app/track/${_id.toUpperCase()}')), '/track/$_id');
    });

    test('rejects foreign, malformed and unknown links', () {
      expect(routeForLink(Uri.parse('musicantiblur://auth/verify')), isNull);
      expect(routeForLink(Uri.parse('musicantiblur://app/artist/$_id')), isNull);
      expect(routeForLink(Uri.parse('musicantiblur://app/playlist/not-a-guid')), isNull);
      expect(routeForLink(Uri.parse('https://example.com/')), isNull);
      expect(routeForLink(Uri.parse('/home')), isNull);
    });

    test('text input is trimmed; garbage returns null', () {
      expect(routeForText('  https://x/s/album/$_id \n'), '/album/$_id');
      expect(routeForText('hello world'), isNull);
    });

    test('describeLinkProblem is null for valid links', () {
      expect(describeLinkProblem('https://api/s/playlist/$_id'), isNull);
      expect(describeLinkProblem('  musicantiblur://app/album/$_id '), isNull);
    });

    test('describeLinkProblem explains what is wrong', () {
      expect(describeLinkProblem('   '), 'Вставьте ссылку');
      expect(describeLinkProblem('hello'), startsWith('Это не ссылка'));
      expect(describeLinkProblem('https://api/s/album/1234'), 'В ссылке неверный идентификатор');
      expect(describeLinkProblem('musicantiblur://app/track'), startsWith('Ссылка неполная'));
      expect(describeLinkProblem('https://api/s/artist/$_id'), startsWith('Ссылка должна вести'));
    });

    test('content routes need a session', () {
      expect(isContentRoute('/playlist/$_id'), isTrue);
      expect(isContentRoute('/home'), isFalse);
    });
  });

  group('PendingLink', () {
    test('is returned once', () {
      PendingLink.set('/playlist/$_id');

      expect(PendingLink.take(), '/playlist/$_id');
      expect(PendingLink.take(), isNull);
    });
  });

  group('library models', () {
    LibraryItem item(Map<String, dynamic> extra) => LibraryItem.fromJson({
          'type': 'playlist',
          'id': _id,
          'title': 'T',
          'kind': 'user',
          'isOwn': true,
          'trackCount': 3,
          'coverUrls': <String>[],
          ...extra,
        });

    test('route depends on type and kind', () {
      expect(item({}).route, '/playlist/$_id');
      expect(item({'kind': 'saved', 'isOwn': false}).route, '/playlist/$_id');
      expect(item({'kind': 'liked'}).route, '/liked');
      expect(item({'type': 'album', 'kind': 'album'}).route, '/album/$_id');
    });

    test('caption shows owner only for saved playlists', () {
      expect(item({'kind': 'saved', 'ownerName': 'bob'}).caption, 'Плейлист · bob · 3');
      expect(item({}).caption, 'Плейлист · 3');
      expect(item({'kind': 'liked'}).caption, 'Лайкнутые треки · 3');
      expect(item({'type': 'album', 'kind': 'album', 'subtitle': 'Linkin Park · 2003'}).caption, 'Linkin Park · 2003');
    });

    test('page parses items and cursor', () {
      final page = LibraryPage.fromJson({
        'items': [
          {'type': 'album', 'id': _id, 'title': 'A', 'kind': 'album', 'isOwn': false, 'trackCount': 1, 'coverUrls': ['u']},
        ],
        'nextCursor': 'abc',
      });

      expect(page.items.single.isAlbum, isTrue);
      expect(page.nextCursor, 'abc');
    });

    test('playlist detail keeps old fields and reads new ones', () {
      final detail = PlaylistDetail.fromJson({
        'id': _id,
        'title': 'Road',
        'kind': 'user',
        'trackCount': 1,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-02T00:00:00Z',
        'tracks': [
          {
            'id': _id,
            'title': 'Song',
            'trackNumber': 1,
            'artistId': _id,
            'artistName': 'A',
            'albumId': _id,
            'albumTitle': 'B',
            'addedAt': '2026-01-03T00:00:00Z',
            'likedAt': '2026-01-03T00:00:00Z',
          },
        ],
        'description': 'd',
        'isPublic': true,
        'isOwner': false,
        'ownerName': 'bob',
        'inLibrary': true,
        'coverUrls': ['a', 'b'],
      });

      expect(detail.isPublic, isTrue);
      expect(detail.isOwner, isFalse);
      expect(detail.ownerName, 'bob');
      expect(detail.inLibrary, isTrue);
      expect(detail.coverUrls, ['a', 'b']);
      expect(detail.tracks.single.likedAt, DateTime.utc(2026, 1, 3));
    });

    test('liked detail from old server (no new fields) still parses', () {
      final detail = PlaylistDetail.fromJson({
        'id': _id,
        'title': 'Мне нравится',
        'kind': 'liked',
        'trackCount': 0,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
        'tracks': <dynamic>[],
      });

      expect(detail.isOwner, isTrue);
      expect(detail.isPublic, isFalse);
      expect(detail.coverUrls, isEmpty);
    });
  });

  group('collage and ordering', () {
    test('collageUrls drops blanks and duplicates and caps at four', () {
      expect(collageUrls(['a', null, '', 'a', 'b', 'c', 'd', 'e']), ['a', 'b', 'c', 'd']);
      expect(collageUrls(const <String?>[]), isEmpty);
    });

    test('reorderList moves an item with onReorderItem semantics', () {
      expect(reorderList([1, 2, 3, 4], 0, 2), [2, 3, 1, 4]);
      expect(reorderList([1, 2, 3, 4], 3, 0), [4, 1, 2, 3]);
      expect(reorderList([1, 2, 3], 1, 1), [1, 2, 3]);
    });

    test('orderForPicker hides liked and puts the last used playlist first', () {
      PlaylistListItem p(String id, String kind) => PlaylistListItem(
            id: id,
            title: id,
            kind: kind,
            trackCount: 0,
            updatedAt: DateTime.utc(2026),
          );
      final result = orderForPicker([p('liked', 'liked'), p('a', 'user'), p('b', 'user')], 'b');

      expect(result.map((e) => e.id), ['b', 'a']);
    });
  });

  group('validation', () {
    test('title', () {
      expect(validatePlaylistTitle('  '), isNotNull);
      expect(validatePlaylistTitle('Road'), isNull);
      expect(validatePlaylistTitle('x' * 201), isNotNull);
    });

    test('description', () {
      expect(validatePlaylistDescription(''), isNull);
      expect(validatePlaylistDescription('x' * 501), isNotNull);
    });

    test('share url joins base without double slash', () {
      expect(joinShareUrl('http://h:5080/', 'album', _id), 'http://h:5080/s/album/$_id');
    });
  });

  group('PlaylistCollage', () {
    Future<void> pump(WidgetTester t, List<String> urls) => t.pumpWidget(
          MaterialApp(theme: VizeTheme.data(), home: Scaffold(body: PlaylistCollage(urls: urls))),
        );

    testWidgets('shows an icon without covers', (t) async {
      await pump(t, const []);

      expect(find.byIcon(Icons.queue_music), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('one cover fills the tile, several make a 2x2 grid', (t) async {
      await pump(t, const ['http://x/a.png']);
      expect(find.byType(Image), findsOneWidget);

      await pump(t, const ['http://x/a.png', 'http://x/b.png']);
      expect(find.byType(Image), findsNWidgets(4));
    });
  });

  group('LibraryScreen link dialog', () {
    testWidgets('cancel closes the dialog without exceptions', (t) async {
      final router = GoRouter(
        initialLocation: '/library',
        routes: [GoRoute(path: '/library', builder: (_, _) => LibraryScreen(api: ApiClient()))],
      );
      await t.pumpWidget(MaterialApp.router(theme: VizeTheme.data(), routerConfig: router));
      await t.pump();

      await t.tap(find.byTooltip('Открыть по ссылке'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Открыть по ссылке'), findsWidgets);

      await t.tap(find.text('Отмена'));
      await t.pump(const Duration(milliseconds: 600));

      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
