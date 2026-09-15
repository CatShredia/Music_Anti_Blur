import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../api/api_client.dart';
import 'override_models.dart';

class PrivateUploader {
  PrivateUploader(this.api);

  final ApiClient api;
  static const maxBytes = 104857600;

  Future<PrivateUploadStatus> uploadFile({
    required String trackId,
    required File file,
    void Function(String status)? onStatus,
  }) async {
    final size = await file.length();
    if (size <= 0 || size > maxBytes) {
      throw ApiException(400, 'file_too_large', 'File is too large.');
    }

    onStatus?.call('считаю хеш');
    final checksum = await sha256.bind(file.openRead()).first;
    final name = p.basename(file.path);
    final contentType = _contentType(name);
    onStatus?.call('загрузка');
    final initiated = await api.initiatePrivateUpload(
      trackId: trackId,
      fileName: name,
      sizeBytes: size,
      contentType: contentType,
      checksumSha256: checksum.toString(),
    );

    final etags = <({int partNumber, String eTag})>[];
    final raf = await file.open();
    try {
      for (var i = 0; i < initiated.partCount; i++) {
        final partNumber = i + 1;
        final offset = i * initiated.partSizeBytes;
        final length = min(initiated.partSizeBytes, size - offset);
        onStatus?.call('часть $partNumber/${initiated.partCount}');
        final urls = await api.privateUploadParts(
          trackId: trackId,
          generationId: initiated.generationId,
          partNumbers: [partNumber],
        );
        final part = urls.first;
        final bytes = await raf.setPosition(offset).then((_) => raf.read(length));
        final eTag = await api.putPresignedPart(part.url, bytes);
        etags.add((partNumber: partNumber, eTag: eTag));
      }
    } finally {
      await raf.close();
    }

    onStatus?.call('завершение');
    await api.completePrivateUpload(
      trackId: trackId,
      generationId: initiated.generationId,
      parts: etags,
    );

    onStatus?.call('обработка');
    while (true) {
      final status = await api.privateUploadStatus(
        trackId: trackId,
        generationId: initiated.generationId,
      );
      if (status.isReady || status.isFailed) {
        return status;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  static String _contentType(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.mp3' => 'audio/mpeg',
      '.m4a' || '.mp4' || '.aac' => 'audio/mp4',
      '.flac' => 'audio/flac',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      '.opus' => 'audio/opus',
      _ => 'application/octet-stream',
    };
  }
}
