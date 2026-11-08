import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/admin/admin_models.dart';
import 'package:music_anti_blur/admin/admin_screens.dart';
import 'package:music_anti_blur/admin/folder_parser.dart';
import 'package:music_anti_blur/admin/source_uploader.dart';

PickedFile f(String path) => PickedFile(path: path, size: 1, read: () async => Uint8List(0));

void main() {
  group('parseTrackName', () {
    test('number prefixes', () {
      expect(parseTrackName('01 - Intro.mp3'), (number: 1, title: 'Intro'));
      expect(parseTrackName('2. Song_Two.flac'), (number: 2, title: 'Song Two'));
      expect(parseTrackName('03_Name.m4a'), (number: 3, title: 'Name'));
    });

    test('no number or only number', () {
      expect(parseTrackName('Song.mp3'), (number: null, title: 'Song'));
      expect(parseTrackName('07.mp3').title, '07');
    });
  });

  group('parseAlbums', () {
    test('groups by folder, finds artist, cover and ignores non-audio', () {
      final albums = parseAlbums([
        f('Band/Album One/02 - B.mp3'),
        f('Band/Album One/01 - A.mp3'),
        f('Band/Album One/Cover.JPG'),
        f('Band/Album One/notes.txt'),
        f('Band/Album Two/x.flac'),
      ]);
      expect(albums.map((a) => a.title), ['Album One', 'Album Two']);
      expect(albums.first.artist, 'Band');
      expect(albums.first.cover?.name, 'Cover.JPG');
      expect(albums.first.tracks.map((t) => t.title), ['A', 'B']);
      expect(albums.last.cover, isNull);
    });

    test('numbers are unique and unnumbered files get free numbers', () {
      final album = parseAlbums([
        f('A/01 - x.mp3'),
        f('A/01 - y.mp3'),
        f('A/plain.mp3'),
      ]).single;
      final numbers = album.tracks.map((t) => t.number).toList();
      expect(numbers.toSet().length, 3);
      expect(numbers, [1, 2, 3]);
    });

    test('skips folders without audio', () {
      expect(parseAlbums([f('A/cover.jpg')]), isEmpty);
    });

    test('flat files get default title and no artist', () {
      final album = parseAlbums([f('song.mp3')]).single;
      expect(album.title, 'Без названия');
      expect(album.artist, isNull);
    });
  });

  group('planParts', () {
    test('last part is shorter', () {
      final plan = planParts(12, 5);
      expect(plan.map((p) => p.length), [5, 5, 2]);
      expect(plan.map((p) => p.offset), [0, 5, 10]);
      expect(plan.map((p) => p.number), [1, 2, 3]);
    });

    test('exact multiple and single part', () {
      expect(planParts(10, 5).length, 2);
      expect(planParts(3, 5).length, 1);
    });
  });

  test('audioContentType by extension', () {
    expect(audioContentType('a.MP3'), 'audio/mpeg');
    expect(audioContentType('a.flac'), 'audio/flac');
    expect(audioContentType('a.bin'), 'application/octet-stream');
  });

  test('only role admin passes the gate', () {
    expect(isAdminRole('admin'), isTrue);
    expect(isAdminRole('user'), isFalse);
  });

  test('rendition helpers and status labels', () {
    final r = AdminRendition.fromJson({
      'generationId': 'g',
      'code': 'aac_256',
      'status': 'failed',
      'isActive': false,
      'errorMessage': 'ffmpeg',
    });
    expect(r.isFailed, isTrue);
    expect(r.isBusy, isFalse);
    expect(statusLabel('processing'), 'В работе');
    expect(statusLabel('none'), 'Нет файла');
  });
}
