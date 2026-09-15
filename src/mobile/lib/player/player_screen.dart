import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/catalog_screens.dart';
import '../overrides/override_models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player_controller.dart';
import 'player_queue.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.player});

  final PlayerController player;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _dragging = false;
  double _dragMs = 0;
  bool _draggingVolume = false;
  double _dragVolume = 1;

  PlayerController get player => widget.player;

  @override
  void initState() {
    super.initState();
    player.addListener(_onPlayer);
  }

  @override
  void dispose() {
    player.removeListener(_onPlayer);
    super.dispose();
  }

  void _onPlayer() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setQuality(String quality) async {
    try {
      await player.setQuality(quality);
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    }
  }

  String get _repeatTooltip => switch (player.queue.repeat) {
        'all' => 'Повтор очереди',
        'one' => 'Повтор трека',
        _ => 'Повтор выключен',
      };

  @override
  Widget build(BuildContext context) {
    final track = player.track;
    final maxMs = player.duration.inMilliseconds.toDouble();
    final valueMs = _dragging
        ? _dragMs
        : player.position.inMilliseconds.clamp(0, maxMs.isNaN ? 0 : maxMs.toInt()).toDouble();
    final qualities = track?.availableQualities ?? const [];
    final volume = _draggingVolume ? _dragVolume : player.volume;

    return VizeScaffold(
      showMiniPlayer: false,
      header: VizeHeader(
        title: track?.title ?? 'Плеер',
        showBack: true,
        onBack: () => popOrGo(context, '/home'),
      ),
      body: track == null && !player.hasQueue
          ? const Center(
              child: Text(
                'Ничего не играет',
                style: TextStyle(color: VizeColors.accentMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                CatalogCover(coverObjectKey: player.coverObjectKey),
                const SizedBox(height: 16),
                Text(track?.title ?? 'Трек', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(track?.artist.name ?? '', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(track?.album.title ?? '', style: Theme.of(context).textTheme.bodySmall),
                if (player.resolvedSource != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    sourceLabel(player.resolvedSource!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 24),
                Slider(
                  min: 0,
                  max: maxMs <= 0 ? 1 : maxMs,
                  value: maxMs <= 0 ? 0 : valueMs.clamp(0, maxMs),
                  onChanged: maxMs <= 0 || player.followingRemote
                      ? null
                      : (value) => setState(() {
                            _dragging = true;
                            _dragMs = value;
                          }),
                  onChangeEnd: maxMs <= 0 || player.followingRemote
                      ? null
                      : (value) async {
                          setState(() => _dragging = false);
                          await player.seek(Duration(milliseconds: value.round()));
                        },
                ),
                Row(
                  children: [
                    Text(
                      formatClock(player.position),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text(
                      formatClock(player.duration),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      volume <= 0 ? Icons.volume_off : Icons.volume_up,
                      color: VizeColors.accentMuted,
                      size: 22,
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 1,
                        value: volume.clamp(0, 1),
                        onChanged: (value) {
                          setState(() {
                            _draggingVolume = true;
                            _dragVolume = value;
                          });
                          unawaited(player.setVolume(value));
                        },
                        onChangeEnd: (value) async {
                          setState(() => _draggingVolume = false);
                          await player.setVolume(value);
                        },
                      ),
                    ),
                    Text(
                      '${(volume * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Предыдущий',
                      onPressed: player.canSkipPrevious ? () => _run(player.previous) : null,
                      icon: Icon(
                        Icons.skip_previous,
                        color: player.canSkipPrevious ? VizeColors.accent : VizeColors.accentDim,
                        size: 36,
                      ),
                    ),
                    IconButton(
                      iconSize: 56,
                      color: VizeColors.accent,
                      onPressed: () => _run(player.togglePlay),
                      icon: Icon(player.playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    ),
                    IconButton(
                      tooltip: 'Следующий',
                      onPressed: player.canSkipNext ? () => _run(player.next) : null,
                      icon: Icon(
                        Icons.skip_next,
                        color: player.canSkipNext ? VizeColors.accent : VizeColors.accentDim,
                        size: 36,
                      ),
                    ),
                  ],
                ),
                if (player.followingRemote) ...[
                  const SizedBox(height: 12),
                  Text(
                    player.playing ? 'Играет на другом устройстве' : 'На другом устройстве на паузе',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  VizePrimaryButton(
                    label: 'Играть здесь',
                    onPressed: () => _run(player.playHere),
                  ),
                ],
                if (player.devices.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Устройства', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final device in player.devices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        device.deviceId == player.myDeviceId ? 'Это устройство' : 'Другое устройство',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: _repeatTooltip,
                      onPressed: () => player.cycleRepeat(),
                      icon: Icon(
                        player.queue.repeat == 'one' ? Icons.repeat_one : Icons.repeat,
                        color: player.queue.repeat == 'off' ? VizeColors.accentMuted : VizeColors.accent,
                      ),
                    ),
                    IconButton(
                      tooltip: player.queue.shuffle ? 'Перемешивание включено' : 'Перемешать',
                      onPressed: () => _run(player.toggleShuffle),
                      style: IconButton.styleFrom(
                        backgroundColor: player.queue.shuffle ? VizeColors.surface : Colors.transparent,
                      ),
                      icon: Icon(
                        Icons.shuffle,
                        color: player.queue.shuffle ? VizeColors.accent : VizeColors.accentDim,
                      ),
                    ),
                  ],
                ),
                if (player.loading && !player.playing) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ],
                const SizedBox(height: 24),
                Text('Качество', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    VizeChip(
                      label: PlayerController.qualityLabel('auto'),
                      selected: player.followsSettings,
                      onTap: qualities.isEmpty ? () {} : () => _setQuality('auto'),
                    ),
                    for (final quality in qualities)
                      VizeChip(
                        label: quality.label,
                        selected: !player.followsSettings && player.requestedQuality == quality.code,
                        onTap: () => _setQuality(quality.code),
                      ),
                  ],
                ),
                if (qualities.length == 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Доступно одно качество.',
                      style: TextStyle(color: VizeColors.accentMuted, fontSize: 14),
                    ),
                  ),
                const SizedBox(height: 28),
                Text(
                  'Очередь · ${player.queue.items.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (player.queue.items.isEmpty)
                  const Text(
                    'Очередь пуста.',
                    style: TextStyle(color: VizeColors.accentMuted, fontSize: 14),
                  )
                else
                  for (final item in player.queue.items) _QueueTile(player: player, item: item, onTap: _run),
              ],
            ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.player,
    required this.item,
    required this.onTap,
  });

  final PlayerController player;
  final QueueItem item;
  final Future<void> Function(Future<void> Function() action) onTap;

  @override
  Widget build(BuildContext context) {
    final current = item.itemId == player.queue.currentItemId;
    final label = player.labelFor(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: current ? VizeColors.surface : VizeColors.bgElevated,
        borderRadius: BorderRadius.circular(VizeRadii.card),
        child: InkWell(
          onTap: current ? null : () => onTap(() => player.playQueueItem(item.itemId)),
          borderRadius: BorderRadius.circular(VizeRadii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  current && player.playing ? Icons.volume_up : Icons.audiotrack_outlined,
                  color: current ? VizeColors.accent : VizeColors.accentMuted,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: VizeColors.text,
                          fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (label.subtitle.isNotEmpty) label.subtitle,
                          sourceLabel(current && player.resolvedSource != null
                              ? player.resolvedSource!
                              : item.sourcePreference),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatClock(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
