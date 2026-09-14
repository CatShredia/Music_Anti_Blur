import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'player_controller.dart';

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
        if (track == null && !player.hasQueue) {
          return const SizedBox.shrink();
        }
        final title = track?.title ?? 'Трек';
        return Material(
          color: VizeColors.bgElevated,
          child: InkWell(
            onTap: () => context.push('/player'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: VizeColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: VizeColors.stroke),
                    ),
                    child: const Icon(Icons.album_outlined, color: VizeColors.accentMuted, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: VizeColors.text, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: player.playing ? 'Пауза' : 'Play',
                    onPressed: player.loading ? null : () => player.togglePlay(),
                    icon: Icon(
                      player.playing ? Icons.pause : Icons.play_arrow,
                      color: VizeColors.accent,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Следующий',
                    onPressed: player.loading ? null : () => _next(context, player),
                    icon: const Icon(Icons.skip_next, color: VizeColors.accent),
                  ),
                ],
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
