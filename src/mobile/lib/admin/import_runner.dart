import 'dart:async';
import 'dart:math';

import '../api/api_client.dart';
import 'admin_api.dart';
import 'folder_parser.dart';
import 'source_uploader.dart';

enum ImportState { waiting, creating, uploading, processing, done, failed }

class ImportItem {
  ImportItem({required this.album, required this.track});

  final ParsedAlbum album;
  final ParsedTrack track;
  ImportState state = ImportState.waiting;
  double progress = 0;
  String? error;
  String? trackId;
}

String describeError(Object e) {
  if (e is ApiException) {
    final fields = e.fieldCodes.entries.map((f) => '${f.key}: ${f.value}').join(', ');
    return fields.isEmpty ? '${e.status} ${e.code}' : '${e.status} ${e.code} ($fields)';
  }
  return '$e';
}

/// Массовый импорт: исполнитель → альбом → обложка → треки → исходники.
/// Ошибка одного трека не останавливает остальные; [run] можно вызвать повторно для неудачных.
class ImportRunner {
  ImportRunner(this.api, {SourceUploader? uploader, this.trackConcurrency = 2})
      : uploader = uploader ?? SourceUploader(api);

  final ApiClient api;
  final SourceUploader uploader;
  final int trackConcurrency;
  bool cancelled = false;

  final _artistIds = <String, String>{};
  final _albumIds = <ParsedAlbum, String>{};

  List<ImportItem> plan(List<ParsedAlbum> albums) => [
        for (final album in albums)
          for (final track in album.tracks) ImportItem(album: album, track: track),
      ];

  Future<void> run(List<ImportItem> items, void Function() onUpdate) async {
    cancelled = false;
    await _loadArtists();
    final pending = items.where((i) => i.state != ImportState.done).toList();

    // Альбомы создаём последовательно, чтобы не плодить дубли, треки грузим параллельно.
    final albumsDone = <ParsedAlbum>{};
    for (final item in pending) {
      if (cancelled) {
        break;
      }
      if (albumsDone.add(item.album)) {
        try {
          await _ensureAlbum(item.album);
        } catch (e) {
          for (final i in pending.where((i) => i.album == item.album)) {
            i.state = ImportState.failed;
            i.error = describeError(e);
          }
          onUpdate();
        }
      }
    }

    var cursor = 0;
    Future<void> worker() async {
      while (!cancelled) {
        if (cursor >= pending.length) {
          return;
        }
        final item = pending[cursor++];
        if (item.state == ImportState.failed && !_albumIds.containsKey(item.album)) {
          continue;
        }
        await _runItem(item, onUpdate);
      }
    }

    await Future.wait([for (var i = 0; i < min(trackConcurrency, max(1, pending.length)); i++) worker()]);
  }

  Future<void> _loadArtists() async {
    if (_artistIds.isNotEmpty) {
      return;
    }
    String? cursor;
    do {
      final page = await api.listArtists(cursor: cursor, limit: 100);
      for (final a in page.items) {
        _artistIds.putIfAbsent(a.name.toLowerCase(), () => a.id);
      }
      cursor = page.nextCursor;
    } while (cursor != null);
  }

  Future<String> _ensureArtist(String name) async {
    final key = name.trim().toLowerCase();
    final known = _artistIds[key];
    if (known != null) {
      return known;
    }
    final id = await api.adminCreateArtistId(name.trim());
    _artistIds[key] = id;
    return id;
  }

  Future<void> _ensureAlbum(ParsedAlbum album) async {
    if (_albumIds.containsKey(album)) {
      return;
    }
    final artistId = await _ensureArtist(album.artist ?? 'Неизвестный исполнитель');
    final albumId = await api.adminCreateAlbum(artistId: artistId, title: album.title.trim());
    _albumIds[album] = albumId;
    final cover = album.cover;
    if (cover != null) {
      try {
        await api.adminUploadCover(
          albumId: albumId,
          bytes: await cover.read(),
          fileName: cover.name,
          contentType: extensionOf(cover.name) == 'png' ? 'image/png' : 'image/jpeg',
        );
      } catch (_) {
        // Обложку можно загрузить позже; треки это не блокирует.
      }
    }
  }

  Future<void> _runItem(ImportItem item, void Function() onUpdate) async {
    item.error = null;
    try {
      final albumId = _albumIds[item.album]!;
      final artistId = _artistIds[(item.album.artist ?? 'Неизвестный исполнитель').trim().toLowerCase()]!;
      if (item.trackId == null) {
        item.state = ImportState.creating;
        onUpdate();
        item.trackId = await api.adminCreateTrack(
          albumId: albumId,
          artistId: artistId,
          title: item.track.title,
          trackNumber: item.track.number,
        );
      }
      item.state = ImportState.uploading;
      onUpdate();
      final bytes = await item.track.file.read();
      final status = await uploader.upload(
        trackId: item.trackId!,
        fileName: item.track.file.name,
        bytes: bytes,
        isCancelled: () => cancelled,
        onProgress: (stage, progress) {
          item.state = stage == 'обработка' ? ImportState.processing : ImportState.uploading;
          item.progress = progress;
          onUpdate();
        },
      );
      if (status.isReady) {
        item.state = ImportState.done;
        item.progress = 1;
      } else {
        item.state = ImportState.failed;
        item.error = status.errorMessage ?? status.status;
      }
    } on UploadCancelled {
      item.state = ImportState.failed;
      item.error = 'отменено';
    } catch (e) {
      item.state = ImportState.failed;
      item.error = describeError(e);
    }
    onUpdate();
  }
}
