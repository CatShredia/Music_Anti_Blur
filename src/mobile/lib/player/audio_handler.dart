import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Единственное место, где вызывается [AudioPlayer.setUrl].
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _player.playbackEventStream.listen(_broadcast);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        onCompleted?.call();
      }
    });
  }

  final AudioPlayer _player;
  void Function()? onSkipNext;
  void Function()? onSkipPrevious;
  void Function()? onCompleted;

  Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) => pause());
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        pause();
      }
    });
  }

  Future<Duration?> setUrl(String url, {MediaItem? item}) async {
    if (item != null) {
      mediaItem.add(item);
    }
    return _player.setUrl(url);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> skipToNext() async => onSkipNext?.call();

  @override
  Future<void> skipToPrevious() async => onSkipPrevious?.call();

  bool get playing => _player.playing;

  Duration get position => _player.position;

  Duration? get duration => _player.duration;

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<PlaybackEvent> get playbackEventStream => _player.playbackEventStream;

  void _broadcast(PlaybackEvent event) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0,
      ),
    );
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'setUrl') {
      final url = extras?['url'] as String?;
      if (url != null) {
        await setUrl(url);
      }
      return;
    }
    await super.customAction(name, extras);
  }

  Future<void> release() => _player.dispose();
}

Future<MusicAudioHandler> createMusicAudioHandler() async {
  final mobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (mobile) {
    try {
      return await AudioService.init(
        builder: MusicAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.musicantiblur.music_anti_blur.playback',
          androidNotificationChannelName: 'Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('AudioService.init failed: $e');
    }
  }
  return MusicAudioHandler();
}
