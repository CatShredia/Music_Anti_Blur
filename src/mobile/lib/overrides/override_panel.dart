import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_client.dart';
import '../player/player_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import 'local_binding_store.dart';
import 'override_models.dart';
import 'private_uploader.dart';
import 'saf_channel.dart';

class TrackOverridePanel extends StatefulWidget {
  const TrackOverridePanel({
    super.key,
    required this.api,
    required this.bindings,
    required this.trackId,
    this.catalogDurationMs,
  });

  final ApiClient api;
  final LocalBindingStore bindings;
  final String trackId;
  final int? catalogDurationMs;

  @override
  State<TrackOverridePanel> createState() => TrackOverridePanelState();
}

class TrackOverridePanelState extends State<TrackOverridePanel> {
  TrackOverride? _override;
  LocalTrackBinding? _binding;
  String _preference = 'auto';
  String? _status;
  bool _busy = false;

  bool get privateReady => _override?.privateReady ?? false;
  bool get hasLocal => _binding != null;
  String get preference => _preference;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final binding = await widget.bindings.get(widget.trackId);
    TrackOverride? row;
    try {
      row = await widget.api.trackOverride(widget.trackId);
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _binding = binding;
      _override = row;
      _preference = row?.sourcePreference ?? (binding == null ? 'auto' : 'auto');
    });
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: false);
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    final file = picked.files.first;
    var path = file.path;
    if (path == null || path.isEmpty) {
      if (mounted) {
        showVizeMessage(context, 'Не удалось открыть файл');
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final copied = await widget.bindings.copyIntoStore(
        trackId: widget.trackId,
        sourcePath: path,
        displayName: file.name,
      );
      await SafChannel.takePersistable(path);
      final durationMs = await _probeDuration(copied.path);
      final binding = await widget.bindings.put(
        LocalTrackBinding(
          trackId: widget.trackId,
          copiedPath: copied.path,
          displayName: file.name,
          sourceUri: path,
          durationMs: durationMs,
          sizeBytes: await copied.length(),
        ),
      );
      final saved = await widget.api.putTrackOverride(
        trackId: widget.trackId,
        sourcePreference: _preference == 'catalog' ? 'auto' : _preference,
        displayName: binding.displayName,
        durationMs: binding.durationMs,
        sizeBytes: binding.sizeBytes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _binding = binding;
        _override = saved;
        _preference = saved.sourcePreference;
      });
      if (durationDiffersTooMuch(binding.durationMs, widget.catalogDurationMs)) {
        showVizeMessage(context, 'Длительность файла отличается от каталога больше чем на 5%');
      }
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setPreference(String value) async {
    if (value == 'local' && _binding == null) {
      showVizeMessage(context, 'Сначала выберите файл');
      return;
    }
    if (value == 'private' && !privateReady) {
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await widget.api.putTrackOverride(
        trackId: widget.trackId,
        sourcePreference: value,
        displayName: _binding?.displayName,
        durationMs: _binding?.durationMs,
        sizeBytes: _binding?.sizeBytes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _override = saved;
        _preference = saved.sourcePreference;
      });
      final player = PlayerScope.maybeOf(context);
      if (player?.queue.current?.trackId == widget.trackId) {
        await player!.setItemSource(value);
      }
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _upload() async {
    final binding = _binding;
    if (binding == null) {
      showVizeMessage(context, 'Сначала выберите файл');
      return;
    }
    final file = File(binding.copiedPath);
    final size = await file.length();
    if (!mounted) {
      return;
    }
    if (size > PrivateUploader.maxBytes) {
      showVizeMessage(context, 'Private-копия: файл больше 100 МБ');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'загрузка';
    });
    try {
      final result = await PrivateUploader(widget.api).uploadFile(
        trackId: widget.trackId,
        file: file,
        onStatus: (text) {
          if (mounted) {
            setState(() => _status = text);
          }
        },
      );
      await _reload();
      if (!mounted) {
        return;
      }
      if (result.isFailed) {
        showVizeMessage(context, result.errorMessage ?? 'Не удалось обработать файл');
      } else {
        showVizeMessage(context, 'Private-копия готова');
      }
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _deletePrivate() async {
    setState(() => _busy = true);
    try {
      await widget.api.deletePrivateCopy(widget.trackId);
      await _reload();
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteOverride() async {
    setState(() => _busy = true);
    try {
      await widget.api.deleteTrackOverride(widget.trackId);
      await widget.bindings.remove(widget.trackId);
      await _reload();
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Источник', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_binding != null)
          Text(
            'Файл: ${_binding!.displayName}',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          const Text(
            'Локальный файл не привязан.',
            style: TextStyle(color: VizeColors.accentMuted, fontSize: 14),
          ),
        if (_override?.privateStatus != null) ...[
          const SizedBox(height: 4),
          Text(
            'Private: ${_override!.privateStatus}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in const ['auto', 'catalog', 'local', 'private'])
              VizeChip(
                label: sourceLabel(value),
                selected: _preference == value,
                onTap: value == 'private' && !privateReady
                    ? () {}
                    : () => _setPreference(value),
              ),
          ],
        ),
        const SizedBox(height: 16),
        VizePrimaryButton(
          label: 'Выбрать файл',
          busy: _busy,
          onPressed: _busy ? null : _pickFile,
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _busy || _binding == null ? null : _upload,
          child: Text(_status == null ? 'Загрузить на сервер' : 'Загрузка: $_status'),
        ),
        if (_override != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _busy || !(_override!.privateReady || _override!.privateStatus != null)
                ? null
                : _deletePrivate,
            child: const Text('Удалить private-копию'),
          ),
          TextButton(
            onPressed: _busy ? null : _deleteOverride,
            child: const Text('Снять привязку'),
          ),
        ],
      ],
    );
  }
}

Future<int?> _probeDuration(String path) async {
  final player = AudioPlayer();
  try {
    final duration = await player.setFilePath(path);
    return duration?.inMilliseconds;
  } catch (_) {
    return null;
  } finally {
    await player.dispose();
  }
}
