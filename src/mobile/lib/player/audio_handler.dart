import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Единственное место, где вызывается [AudioPlayer.setUrl] / [AudioPlayer.setFilePath].
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _player.playbackEventStream.listen(_broadcast);
    _player.processingStateStream.listen((state) {
      if (_replacingSource) {
        return;
      }
      if (state == ProcessingState.completed) {
        onCompleted?.call();
      }
    });
  }

  final AudioPlayer _player;
  void Function()? onSkipNext;
  void Function()? onSkipPrevious;
  void Function()? onCompleted;
  bool _replacingSource = false;
  String? _tempPath;

  Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) => pause());
    session.interruptionEventStream.listen((event) {
      if (event.begin && event.type == AudioInterruptionType.pause) {
        pause();
      }
    });
  }

  Future<Duration?> setUrl(String url, {MediaItem? item}) async {
    if (item != null) {
      mediaItem.add(item);
    }
    _replacingSource = true;
    try {
      if (_player.playing) {
        await _player.pause();
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final path = await _downloadToTemp(url);
        return _player.setFilePath(path);
      }
      return _player.setUrl(url);
    } finally {
      _replacingSource = false;
    }
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

  Future<String> _downloadToTemp(String url) async {
    final previous = _tempPath;
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Audio HTTP ${response.statusCode}', uri: request.uri);
      }
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}mab-play-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await response.pipe(File(path).openWrite());
      _tempPath = path;
      unawaited(_deleteQuietly(previous));
      return path;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> release() async {
    final previous = _tempPath;
    _tempPath = null;
    await _player.dispose();
    await _deleteQuietly(previous);
  }

  Future<void> _deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      await File(path).delete();
    } catch (_) {}
  }
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
