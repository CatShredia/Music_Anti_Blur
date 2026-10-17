import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/catalog_screens.dart';
import '../overrides/override_models.dart';
import '../theme.dart';
import 'player_controller.dart';
import 'player_nav.dart';

class PlayerNoticeHost extends StatefulWidget {
  const PlayerNoticeHost({
    super.key,
    required this.player,
    required this.messengerKey,
    required this.child,
  });

  final PlayerController player;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  @override
  State<PlayerNoticeHost> createState() => _PlayerNoticeHostState();
}

class _PlayerNoticeHostState extends State<PlayerNoticeHost> {
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_onPlayer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.player.restoreIfNeeded());
    });
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayer);
    super.dispose();
  }

  void _onPlayer() {
    final player = widget.player;
    if (player.noticeEpoch == _seen || player.notice == null) {
      return;
    }
    _seen = player.noticeEpoch;
    final text = player.notice!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.messengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.maybeOf(context);
    if (player == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.track;
        final idle = !player.hasLastTrack;
        final title = idle
            ? 'Ничего не играет'
            : (track?.title ?? player.labelFor(player.queue.current!).title);
        final subtitle = idle
            ? 'Синхронизируется между устройствами'
            : player.followingRemote
                ? (player.playing ? 'Играет на другом устройстве' : 'На другом устройстве')
                : sourceLabel(player.resolvedSource ?? player.queue.current?.sourcePreference ?? 'auto');
        return Material(
          color: VizeColors.bgElevated,
          child: InkWell(
            onTap: () => openPlayer(context),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: VizeColors.stroke)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                children: [
                  CatalogCover(
                    coverUrl: idle ? null : player.coverUrl,
                    height: 40,
                    width: 40,
                    icon: idle ? Icons.music_note_outlined : Icons.album_outlined,
                    iconSize: 22,
                    radius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: idle ? VizeColors.accentMuted : VizeColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: VizeColors.accentMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: idle
                        ? 'Нет трека'
                        : player.followingRemote
                            ? 'Управляется на другом устройстве'
                            : (player.playing ? 'Пауза' : 'Play'),
                    onPressed: player.canTogglePlay ? () => player.togglePlay() : null,
                    icon: Icon(
                      player.playing ? Icons.pause : Icons.play_arrow,
                      color: player.canTogglePlay ? VizeColors.accent : VizeColors.accentDim,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Следующий',
                    onPressed: idle || !player.canSkipNext ? null : () => _next(context, player),
                    icon: Icon(
                      Icons.skip_next,
                      color: !idle && player.canSkipNext ? VizeColors.accent : VizeColors.accentDim,
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _next(BuildContext context, PlayerController player) async {
    try {
      await player.next();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
