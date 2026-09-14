import 'package:flutter/material.dart';

import '../catalog/catalog_screens.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player_controller.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.player});

  final PlayerController player;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  int _seenNotice = 0;
  bool _dragging = false;
  double _dragMs = 0;

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
    if (!mounted) {
      return;
    }
    setState(() {});
    _showNotice();
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

  void _showNotice() {
    if (player.noticeEpoch == _seenNotice || player.notice == null) {
      return;
    }
    _seenNotice = player.noticeEpoch;
    final text = player.notice!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showVizeMessage(context, text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = player.track;
    final maxMs = player.duration.inMilliseconds.toDouble();
    final valueMs = _dragging
        ? _dragMs
        : player.position.inMilliseconds.clamp(0, maxMs.isNaN ? 0 : maxMs.toInt()).toDouble();
    final qualities = track?.availableQualities ?? const [];

    return VizeScaffold(
      header: VizeHeader(title: track?.title ?? 'Плеер'),
      body: track == null
          ? const Center(
              child: Text(
                'Ничего не играет',
                style: TextStyle(color: VizeColors.accentMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const CatalogCover(coverObjectKey: null),
                const SizedBox(height: 16),
                Text(track.title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(track.artist.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(track.album.title, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 24),
                Slider(
                  min: 0,
                  max: maxMs <= 0 ? 1 : maxMs,
                  value: maxMs <= 0 ? 0 : valueMs.clamp(0, maxMs),
                  onChanged: maxMs <= 0
                      ? null
                      : (value) => setState(() {
                            _dragging = true;
                            _dragMs = value;
                          }),
                  onChangeEnd: maxMs <= 0
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
                const SizedBox(height: 16),
                Center(
                  child: IconButton(
                    iconSize: 56,
                    color: VizeColors.accent,
                    onPressed: player.loading ? null : player.togglePlay,
                    icon: Icon(player.playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  ),
                ),
                if (player.loading) ...[
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
              ],
            ),
    );
  }
}

String formatClock(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
