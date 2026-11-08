import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../api/api_client.dart';
import '../overrides/override_models.dart';
import 'admin_api.dart';
import 'folder_parser.dart';

typedef PartRange = ({int number, int offset, int length});

/// Делит файл на части multipart-загрузки (последняя может быть короче).
List<PartRange> planParts(int size, int partSize) {
  final out = <PartRange>[];
  var number = 1;
  for (var offset = 0; offset < size; offset += partSize) {
    out.add((number: number++, offset: offset, length: min(partSize, size - offset)));
  }
  return out;
}

String audioContentType(String fileName) => switch (extensionOf(fileName)) {
      'mp3' => 'audio/mpeg',
      'm4a' || 'mp4' || 'aac' => 'audio/mp4',
      'flac' => 'audio/flac',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'opus' => 'audio/opus',
      _ => 'application/octet-stream',
    };

class UploadCancelled implements Exception {}

/// Загрузка исходника трека в каталог из браузера: файл целиком в памяти (до 100 МБ), части по presigned URL.
class SourceUploader {
  SourceUploader(this.api, {this.concurrency = 3, this.partRetries = 3, this.pollInterval = const Duration(seconds: 2)});

  final ApiClient api;
  final int concurrency;
  final int partRetries;
  final Duration pollInterval;
  static const maxBytes = 104857600;

  Future<PrivateUploadStatus> upload({
    required String trackId,
    required String fileName,
    required Uint8List bytes,
    void Function(String status, double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ApiException(400, 'file_too_large', 'File is too large.');
    }

    onProgress?.call('хеш', 0);
    final checksum = sha256.convert(bytes).toString();
    final initiated = await api.adminInitiateUpload(
      trackId: trackId,
      fileName: fileName,
      sizeBytes: bytes.length,
      contentType: audioContentType(fileName),
      checksumSha256: checksum,
    );

    final plan = planParts(bytes.length, initiated.partSizeBytes);
    final etags = <int, String>{};
    var cursor = 0;
    Object? failure;

    Future<void> worker() async {
      while (failure == null) {
        if (isCancelled?.call() ?? false) {
          failure = UploadCancelled();
          return;
        }
        if (cursor >= plan.length) {
          return;
        }
        final part = plan[cursor++];
        try {
          etags[part.number] = await _putPart(trackId, initiated.generationId, part, bytes);
          onProgress?.call('загрузка', etags.length / plan.length);
        } catch (e) {
          failure ??= e;
          return;
        }
      }
    }

    await Future.wait([for (var i = 0; i < min(concurrency, plan.length); i++) worker()]);

    if (failure != null) {
      try {
        await api.adminCancelUpload(trackId: trackId, generationId: initiated.generationId);
      } catch (_) {}
      throw failure!;
    }

    onProgress?.call('завершение', 1);
    await api.adminCompleteUpload(
      trackId: trackId,
      generationId: initiated.generationId,
      parts: [for (final p in plan) (partNumber: p.number, eTag: etags[p.number]!)],
    );

    onProgress?.call('обработка', 1);
    while (true) {
      final status = await api.adminUploadStatus(trackId: trackId, generationId: initiated.generationId);
      if (status.isReady || status.isFailed) {
        return status;
      }
      if (isCancelled?.call() ?? false) {
        throw UploadCancelled();
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<String> _putPart(String trackId, String generationId, PartRange part, Uint8List bytes) async {
    Object? last;
    for (var attempt = 0; attempt < partRetries; attempt++) {
      try {
        // Presigned URL короткоживущий: на повторе запрашиваем новый.
        final urls = await api.adminUploadParts(
          trackId: trackId,
          generationId: generationId,
          partNumbers: [part.number],
        );
        return await api.putPresignedPart(
          urls.first.url,
          Uint8List.sublistView(bytes, part.offset, part.offset + part.length),
        );
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw last!;
  }
}
