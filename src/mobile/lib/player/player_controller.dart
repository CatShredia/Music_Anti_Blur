import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_client.dart';
import '../catalog/catalog_models.dart';
import 'audio_handler.dart';

class PlayerScope extends InheritedNotifier<PlayerController> {
  const PlayerScope({
    super.key,
    required PlayerController super.notifier,
    required super.child,
  });

  static PlayerController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerScope>()?.notifier;
}

class PlayerController extends ChangeNotifier {
  PlayerController(this.api, {MusicAudioHandler? handler})
      : handler = handler ?? MusicAudioHandler();

  final ApiClient api;
  final MusicAudioHandler handler;

  TrackDetail? track;
  String? requestedQuality;
  String? resolvedQuality;
  String? qualityFallbackFrom;
  String? notice;
  int noticeEpoch = 0;
  bool loading = false;
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  DateTime? _expiresAt;
  bool _refreshUsed = false;
  bool _refreshing = false;
  int _playGen = 0;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlaybackEvent>? _eventSub;

  Future<void> prepare() async {
    await handler.prepare();
    _positionSub = handler.positionStream.listen((value) {
      position = value;
      unawaited(_maybeRefreshNearExpiry());
      notifyListeners();
    });
    _durationSub = handler.durationStream.listen((value) {
      if (value != null && value > Duration.zero) {
        duration = value;
        notifyListeners();
      }
    });
    _stateSub = handler.playerStateStream.listen((state) {
      playing = state.playing;
      notifyListeners();
    });
    _eventSub = handler.playbackEventStream.listen((event) {
      if (event.errorCode != null || event.errorMessage != null) {
        unawaited(_onPlayerError(event.errorCode, event.errorMessage));
      }
    });
  }

  Future<void> playTrack(
    String trackId, {
    String source = 'catalog',
    String? quality,
  }) async {
    final previousId = track?.id;
    final resume = previousId == trackId ? handler.position : Duration.zero;
    requestedQuality = quality;
    loading = true;
    qualityFallbackFrom = null;
    notifyListeners();
    final gen = ++_playGen;
    try {
      final preference = quality ?? (await api.settings()).preferredQuality;
      final detail = await api.track(trackId);
      final url = await api.playbackUrl(
        trackId: trackId,
        sourcePreference: source,
        qualityPreference: preference,
      );
      if (gen != _playGen) {
        return;
      }
      track = detail;
      resolvedQuality = url.resolvedQuality;
      qualityFallbackFrom = url.qualityFallbackFrom;
      _expiresAt = url.expiresAt.toUtc();
      _refreshUsed = false;
      if (url.durationMs > 0) {
        duration = Duration(milliseconds: url.durationMs);
      }
      await handler.setUrl(url.url);
      if (resume > Duration.zero) {
        await _seekPreservingSeconds(resume);
      }
      await handler.play();
      if (url.qualityFallbackFrom != null) {
        _emitNotice('Включено ${url.resolvedQuality}');
      }
    } finally {
      if (gen == _playGen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setQuality(String quality) {
    final id = track?.id;
    if (id == null) {
      return Future.value();
    }
    return playTrack(id, quality: quality);
  }

  Future<void> togglePlay() async {
    if (track == null) {
      return;
    }
    if (handler.playing) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> seek(Duration value) async {
    var target = value;
    if (target.isNegative) {
      target = Duration.zero;
    }
    final max = handler.duration ?? duration;
    if (max > Duration.zero && target > max) {
      target = max;
    }
    await handler.seek(target);
    position = target;
    notifyListeners();
  }

  Future<void> stop() async {
    _playGen++;
    await handler.stop();
    playing = false;
    notifyListeners();
  }

  bool get followsSettings => requestedQuality == null || requestedQuality == 'auto';

  static String qualityLabel(String code) => switch (code) {
        'auto' => 'Авто',
        'aac_128' => 'aac_128',
        'aac_256' => 'Высокое',
        'src' => 'Исходник',
        _ => code,
      };

  Future<void> _maybeRefreshNearExpiry() async {
    final expires = _expiresAt;
    if (expires == null || _refreshUsed || _refreshing || track == null) {
      return;
    }
    if (expires.difference(DateTime.now().toUtc()) > const Duration(seconds: 45)) {
      return;
    }
    await _reresolve();
  }

  Future<void> _onPlayerError(int? code, String? message) async {
    if (_isAuthFailure(code, message)) {
      await _reresolve();
      return;
    }
    if (message != null && message.isNotEmpty) {
      debugPrint('playback error $code $message');
    }
  }

  Future<void> _reresolve() async {
    final current = track;
    final quality = resolvedQuality;
    if (_refreshUsed || _refreshing || current == null || quality == null) {
      return;
    }
    _refreshing = true;
    _refreshUsed = true;
    final gen = _playGen;
    final resume = handler.position;
    try {
      final url = await api.playbackUrl(
        trackId: current.id,
        sourcePreference: 'catalog',
        qualityPreference: quality,
      );
      if (gen != _playGen) {
        return;
      }
      _expiresAt = url.expiresAt.toUtc();
      await handler.setUrl(url.url);
      try {
        await _seekPreservingSeconds(resume);
        await handler.play();
      } catch (e) {
        debugPrint('playback re-resolve seek failed, restarting at 0: $e');
        await handler.seek(Duration.zero);
        await handler.play();
      }
    } catch (e) {
      debugPrint('playback re-resolve failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _seekPreservingSeconds(Duration resume) async {
    final max = handler.duration ?? duration;
    var target = Duration(seconds: resume.inSeconds);
    if (max > Duration.zero && target > max) {
      target = max;
    }
    await handler.seek(target);
  }

  bool _isAuthFailure(int? code, String? message) {
    final text = '${code ?? ''} ${message ?? ''}'.toLowerCase();
    return text.contains('401') ||
        text.contains('403') ||
        text.contains('unauthorized') ||
        text.contains('forbidden');
  }

  void _emitNotice(String text) {
    notice = text;
    noticeEpoch++;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_eventSub?.cancel());
    unawaited(handler.dispose());
    super.dispose();
  }
}
