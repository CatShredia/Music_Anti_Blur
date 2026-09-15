import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalTrackBinding {
  const LocalTrackBinding({
    required this.trackId,
    required this.copiedPath,
    required this.displayName,
    this.sourceUri,
    this.durationMs,
    this.sizeBytes,
  });

  final String trackId;
  final String copiedPath;
  final String displayName;
  final String? sourceUri;
  final int? durationMs;
  final int? sizeBytes;

  bool get fileExists {
    if (kIsWeb) {
      return true;
    }
    try {
      return File(copiedPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'copiedPath': copiedPath,
        'displayName': displayName,
        'sourceUri': sourceUri,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
      };

  factory LocalTrackBinding.fromJson(Map<String, dynamic> json) => LocalTrackBinding(
        trackId: json['trackId'] as String,
        copiedPath: json['copiedPath'] as String,
        displayName: json['displayName'] as String? ?? 'Файл',
        sourceUri: json['sourceUri'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt(),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      );
}

/// On-device map trackId → local file. URIs are never sent to the API.
class LocalBindingStore {
  LocalBindingStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;
  final Map<String, LocalTrackBinding> _cache = {};
  bool _loaded = false;

  Future<Directory> _root() async {
    final injected = _directory;
    if (injected != null) {
      return injected;
    }
    if (kIsWeb) {
      throw UnsupportedError('Local files are not stored in the browser.');
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'overrides'));
  }

  Future<File> _indexFile() async {
    final root = await _root();
    await root.create(recursive: true);
    return File(p.join(root.path, 'index.json'));
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    if (kIsWeb && _directory == null) {
      return;
    }
    try {
      final file = await _indexFile();
      if (!await file.exists()) {
        return;
      }
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final entry in map.entries) {
        if (entry.value is Map<String, dynamic>) {
          _cache[entry.key] = LocalTrackBinding.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    } catch (_) {
      _cache.clear();
    }
  }

  Future<void> _flush() async {
    if (kIsWeb && _directory == null) {
      return;
    }
    try {
      final file = await _indexFile();
      await file.writeAsString(
        jsonEncode({for (final e in _cache.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {}
  }

  Future<LocalTrackBinding?> get(String trackId) async {
    await _ensureLoaded();
    final row = _cache[trackId];
    if (row == null) {
      return null;
    }
    if (kIsWeb && _directory == null) {
      return row;
    }
    if (!row.fileExists) {
      return null;
    }
    return row;
  }

  Future<bool> isAvailable(String trackId) async {
    final row = await get(trackId);
    return row != null;
  }

  Future<LocalTrackBinding> put(LocalTrackBinding binding) async {
    await _ensureLoaded();
    _cache[binding.trackId] = binding;
    await _flush();
    return binding;
  }

  Future<void> remove(String trackId, {bool deleteFile = true}) async {
    await _ensureLoaded();
    final previous = _cache.remove(trackId);
    await _flush();
    if (deleteFile && previous != null) {
      try {
        final file = File(previous.copiedPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  Future<File> copyIntoStore({
    required String trackId,
    required String sourcePath,
    required String displayName,
  }) async {
    if (kIsWeb && _directory == null) {
      throw UnsupportedError('Local files are not stored in the browser.');
    }
    final root = await _root();
    final destDir = Directory(p.join(root.path, trackId));
    await destDir.create(recursive: true);
    final dest = File(p.join(destDir.path, p.basename(sourcePath)));
    return File(sourcePath).copy(dest.path);
  }
}

bool durationDiffersTooMuch(int? localMs, int? catalogMs) {
  if (localMs == null || catalogMs == null || catalogMs <= 0) {
    return false;
  }
  return (localMs - catalogMs).abs() / catalogMs > 0.05;
}
