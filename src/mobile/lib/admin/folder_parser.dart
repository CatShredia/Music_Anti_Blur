import 'dart:typed_data';

/// Файл, выбранный в браузере. [path] — относительный путь с `/` (для папки: `Артист/Альбом/01 - Трек.mp3`).
class PickedFile {
  PickedFile({required this.path, required this.size, required this.read});

  final String path;
  final int size;
  final Future<Uint8List> Function() read;

  String get name => path.split('/').last;

  String get dir {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }
}

class ParsedTrack {
  ParsedTrack({required this.file, required this.number, required this.title});

  final PickedFile file;
  int number;
  String title;
}

class ParsedAlbum {
  ParsedAlbum({
    required this.folder,
    required this.title,
    required this.tracks,
    this.artist,
    this.cover,
  });

  final String folder;
  String title;
  String? artist;
  PickedFile? cover;
  final List<ParsedTrack> tracks;
}

const audioExtensions = {'mp3', 'm4a', 'mp4', 'flac', 'wav', 'ogg', 'aac', 'opus'};
const coverBaseNames = {'cover', 'folder', 'front', 'album', 'artwork'};
const coverExtensions = {'jpg', 'jpeg', 'png'};

String extensionOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

String baseNameOf(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? name : name.substring(0, i);
}

final _numberPrefix = RegExp(r'^\s*(\d{1,3})\s*[-._)\s]+\s*(.*)$');

/// Достаёт номер и название трека из имени файла: `01 - Intro.mp3`, `2. Song.flac`, `Song.mp3`.
({int? number, String title}) parseTrackName(String fileName) {
  final base = baseNameOf(fileName).replaceAll('_', ' ').trim();
  final match = _numberPrefix.firstMatch(base);
  if (match == null) {
    return (number: null, title: base);
  }
  final title = match.group(2)!.trim();
  return (number: int.parse(match.group(1)!), title: title.isEmpty ? base : title);
}

/// Группирует выбранные файлы по папкам: одна папка с аудио = один альбом.
/// Номера уникальны внутри альбома, порядок по номеру, затем по имени.
List<ParsedAlbum> parseAlbums(List<PickedFile> files) {
  final byDir = <String, List<PickedFile>>{};
  for (final file in files) {
    byDir.putIfAbsent(file.dir, () => []).add(file);
  }

  final albums = <ParsedAlbum>[];
  final dirs = byDir.keys.toList()..sort();
  for (final dir in dirs) {
    final group = byDir[dir]!;
    final audio = group.where((f) => audioExtensions.contains(extensionOf(f.name))).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (audio.isEmpty) {
      continue;
    }

    PickedFile? cover;
    for (final f in group) {
      if (coverExtensions.contains(extensionOf(f.name)) &&
          coverBaseNames.contains(baseNameOf(f.name).toLowerCase())) {
        cover = f;
        break;
      }
    }

    final parsed = [for (final f in audio) (file: f, name: parseTrackName(f.name))];
    final taken = <int>{};
    var next = 1;
    final tracks = <ParsedTrack>[];
    // Сначала файлы с номером, затем без номера (получают свободные номера по порядку имён).
    for (final p in parsed.where((p) => p.name.number != null && p.name.number! > 0)) {
      var n = p.name.number!;
      while (taken.contains(n)) {
        n++;
      }
      taken.add(n);
      tracks.add(ParsedTrack(file: p.file, number: n, title: p.name.title));
    }
    for (final p in parsed.where((p) => p.name.number == null || p.name.number! <= 0)) {
      while (taken.contains(next)) {
        next++;
      }
      taken.add(next);
      tracks.add(ParsedTrack(file: p.file, number: next, title: p.name.title));
    }
    tracks.sort((a, b) => a.number.compareTo(b.number));

    final parts = dir.isEmpty ? <String>[] : dir.split('/');
    albums.add(
      ParsedAlbum(
        folder: dir,
        title: parts.isEmpty ? 'Без названия' : parts.last,
        artist: parts.length >= 2 ? parts[parts.length - 2] : null,
        cover: cover,
        tracks: tracks,
      ),
    );
  }
  return albums;
}
