import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_client.dart';
import '../catalog/catalog_models.dart';
import 'audio_handler.dart';
import 'playback_models.dart';
import 'player_queue.dart';

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
  PlayerController(this.api, {required this.handler});

  final ApiClient api;
  final MusicAudioHandler handler;

  PlayerQueue queue = PlayerQueue.empty;
  TrackDetail? track;
  String? requestedQuality;
  String? resolvedQuality;
  String? qualityFallbackFrom;
  String? notice;
  int noticeEpoch = 0;
  bool loading = false;
  bool playing = false;
  double volume = 1;
  String? coverObjectKey;
  final Map<String, QueueTrackLabel> queueLabels = {};
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  DateTime? _expiresAt;
  bool _refreshUsed = false;
  bool _refreshing = false;
  bool _completing = false;
  bool _restored = false;
  bool _starting = false;
  String? _sessionId;
  int _revision = 0;
  int _playGen = 0;
  Timer? _progressTimer;
  Future<void> _writes = Future.value();
  Future<void>? _expanding;
  List<QueueItem>? _orderBeforeShuffle;
  DateTime? _lastStateWrite;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlaybackEvent>? _eventSub;

  Future<void> prepare() async {
    await handler.configureSession();
    handler.onSkipNext = () => unawaited(next());
    handler.onSkipPrevious = () => unawaited(previous());
    handler.onCompleted = () => unawaited(_onCompleted());
    _positionSub = handler.positionStream.listen((value) {
      position = value;
      unawaited(_maybeRefreshNearExpiry());
      _scheduleProgress();
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

  Future<void> restoreIfNeeded() async {
    if (_restored || !await api.hasSession()) {
      return;
    }
    _restored = true;
    final gen = _playGen;
    try {
      final snapshot = await api.playbackState();
      if (gen != _playGen || _starting || playing) {
        return;
      }
      await _applySnapshot(snapshot, autoplay: false);
    } catch (e) {
      debugPrint('playback restore failed: $e');
    }
  }

  Future<void> playTrack(
    String trackId, {
    String source = 'catalog',
    String? quality,
  }) async {
    requestedQuality = quality;
    queue = PlayerQueue.single(trackId, source: source).copyWith(
      repeat: queue.repeat,
      shuffle: queue.shuffle,
    );
    await _playAndPersist(resumeIfSame: true);
    unawaited(_expandQueueFromAlbum());
  }

  Future<void> playAlbum(
    AlbumDetail album, {
    String? startTrackId,
    String? quality,
  }) async {
    requestedQuality = quality;
    final ordered = [...album.tracks]..sort((a, b) => a.trackNumber.compareTo(b.trackNumber));
    queue = PlayerQueue.album(
      ordered.map((item) => item.id),
      startTrackId: startTrackId,
    ).copyWith(repeat: queue.repeat, shuffle: queue.shuffle);
    _rememberAlbum(album);
    _orderBeforeShuffle = [...queue.items];
    if (queue.shuffle) {
      queue = _shuffleQueue(queue);
    }
    await _playAndPersist(resumeIfSame: false);
  }

  Future<void> setQuality(String quality) async {
    if (queue.current == null) {
      return;
    }
    requestedQuality = quality;
    await _playAndPersist(resumeIfSame: true);
  }

  Future<void> togglePlay() async {
    if (track == null && queue.current != null) {
      await _playCurrent(resumeIfSame: false, autoplay: true, seekTo: position);
      await _persistCommand(playing: true);
      return;
    }
    if (track == null) {
      return;
    }
    if (handler.playing) {
      await handler.pause();
      await _persistCommand(playing: false);
    } else {
      await handler.play();
      await _persistCommand(playing: true);
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
    await _persistProgress();
  }

  Future<void> next() async {
    final before = queue.currentItemId;
    final nextQueue = queue.skipNext();
    if (nextQueue.currentItemId == before) {
      _emitNotice(queue.repeat == 'off' ? 'Это последний трек очереди' : 'В очереди один трек');
      return;
    }
    queue = nextQueue;
    notifyListeners();
    await _playAndPersist(resumeIfSame: false);
  }

  Future<void> playQueueItem(String itemId) async {
    if (queue.currentItemId == itemId) {
      return;
    }
    if (!queue.items.any((item) => item.itemId == itemId)) {
      return;
    }
    queue = queue.copyWith(currentItemId: itemId);
    notifyListeners();
    await _playAndPersist(resumeIfSame: false);
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    await handler.setVolume(volume);
    notifyListeners();
  }

  Future<void> previous() async {
    if (position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    final before = queue.currentItemId;
    final prev = queue.skipPrevious();
    if (prev.currentItemId == before) {
      await seek(Duration.zero);
      return;
    }
    queue = prev;
    notifyListeners();
    await _playAndPersist(resumeIfSame: false);
  }

  Future<void> cycleRepeat() async {
    queue = queue.cycleRepeat();
    notifyListeners();
    await _persistCommand(playing: playing);
  }

  Future<void> toggleShuffle() async {
    if (queue.shuffle) {
      final restored = _orderBeforeShuffle;
      _orderBeforeShuffle = null;
      queue = restored == null || restored.isEmpty
          ? queue.copyWith(shuffle: false)
          : queue.withOrder(restored, shuffle: false);
      notifyListeners();
      await _persistCommand(playing: playing);
      return;
    }

    if (queue.items.length <= 1) {
      await _expandQueueFromAlbum();
    }
    if (queue.items.length <= 1) {
      _emitNotice('В очереди один трек — перемешивать нечего');
      return;
    }

    _orderBeforeShuffle = [...queue.items];
    queue = _shuffleQueue(queue);
    notifyListeners();
    _emitNotice('Очередь перемешана');
    await _persistCommand(playing: playing);
  }

  Future<void> stop() async {
    _playGen++;
    _progressTimer?.cancel();
    await handler.stop();
    playing = false;
    notifyListeners();
  }

  Future<void> resetLocal() async {
    _sessionId = null;
    _revision = 0;
    _restored = false;
    _progressTimer?.cancel();
    queue = PlayerQueue.empty;
    track = null;
    coverObjectKey = null;
    queueLabels.clear();
    _orderBeforeShuffle = null;
    await stop();
  }

  bool get followsSettings => requestedQuality == null || requestedQuality == 'auto';

  bool get hasQueue => queue.current != null;

  bool get canSkipNext => queue.hasNext;

  bool get canSkipPrevious => queue.hasPrevious || position > Duration.zero;

  QueueTrackLabel labelFor(QueueItem item) {
    final cached = queueLabels[item.trackId];
    if (cached != null) {
      return cached;
    }
    if (track?.id == item.trackId) {
      return QueueTrackLabel(title: track!.title, subtitle: track!.artist.name);
    }
    return const QueueTrackLabel(title: 'Трек', subtitle: '');
  }

  Future<void> _playAndPersist({required bool resumeIfSame}) async {
    _starting = true;
    try {
      await _playCurrent(resumeIfSame: resumeIfSame, autoplay: true);
    } catch (_) {
      unawaited(_persistCommand(playing: false));
      rethrow;
    } finally {
      _starting = false;
    }
    await _persistCommand(playing: true);
  }

  static String qualityLabel(String code) => switch (code) {
        'auto' => 'Авто',
        'aac_128' => 'aac_128',
        'aac_256' => 'Высокое',
        'src' => 'Исходник',
        _ => code,
      };

  Future<void> _playCurrent({
    required bool resumeIfSame,
    required bool autoplay,
    Duration? seekTo,
  }) async {
    final item = queue.current;
    if (item == null) {
      return;
    }
    final previousId = track?.id;
    final resume = seekTo ??
        (resumeIfSame && previousId == item.trackId ? handler.position : Duration.zero);
    loading = true;
    qualityFallbackFrom = null;
    notifyListeners();
    final gen = ++_playGen;
    try {
      final preference = requestedQuality ?? (await api.settings()).preferredQuality;
      final detail = await api.track(item.trackId);
      final url = await api.playbackUrl(
        trackId: item.trackId,
        sourcePreference: item.sourcePreference,
        qualityPreference: preference,
      );
      if (gen != _playGen) {
        return;
      }
      track = detail;
      queueLabels[detail.id] = QueueTrackLabel(title: detail.title, subtitle: detail.artist.name);
      resolvedQuality = url.resolvedQuality;
      qualityFallbackFrom = url.qualityFallbackFrom;
      _expiresAt = url.expiresAt.toUtc();
      _refreshUsed = false;
      final loaded = await handler.setUrl(
        url.url,
        item: MediaItem(
          id: detail.id,
          title: detail.title,
          album: detail.album.title,
          artist: detail.artist.name,
          duration: url.durationMs > 0 ? Duration(milliseconds: url.durationMs) : null,
        ),
      );
      if (loaded != null && loaded > Duration.zero) {
        duration = loaded;
      } else if (url.durationMs > 0) {
        duration = Duration(milliseconds: url.durationMs);
      }
      if (resume > Duration.zero) {
        await _seekPreservingSeconds(resume);
      }
      if (gen == _playGen) {
        loading = false;
        notifyListeners();
      }
      if (autoplay) {
        await handler.play();
      }
      if (url.qualityFallbackFrom != null) {
        _emitNotice('Включено ${url.resolvedQuality}');
      }
    } on ApiException catch (e) {
      if (e.code == 'source_unavailable' || e.code == 'quality_unavailable') {
        _emitNotice(e.localizedMessage);
      } else if (e.status == 401 || e.code == 'invalid_token') {
        _emitNotice('Сессия устарела. Войдите снова.');
      }
      rethrow;
    } catch (e) {
      _emitNotice('Не удалось начать воспроизведение');
      rethrow;
    } finally {
      if (gen == _playGen) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _onCompleted() async {
    if (_completing) {
      return;
    }
    _completing = true;
    try {
      final nextQueue = queue.afterCompleted();
      if (nextQueue == null) {
        await handler.seek(Duration.zero);
        position = Duration.zero;
        await _persistCommand(playing: false);
        return;
      }
      if (nextQueue.currentItemId == queue.currentItemId && queue.repeat == 'one') {
        await handler.seek(Duration.zero);
        await handler.play();
        return;
      }
      queue = nextQueue;
      notifyListeners();
      try {
        await _playCurrent(resumeIfSame: false, autoplay: true);
        await _persistCommand(playing: true);
      } on ApiException catch (e) {
        _emitNotice(e.localizedMessage);
      }
    } finally {
      _completing = false;
    }
  }

  Future<void> _applySnapshot(PlaybackSnapshot snapshot, {required bool autoplay}) async {
    if (_starting || playing) {
      return;
    }
    _revision = snapshot.revision;
    queue = snapshot.queue;
    requestedQuality = snapshot.qualityCode;
    position = Duration(milliseconds: snapshot.positionMs);
    if (snapshot.trackId == null || queue.current == null) {
      track = null;
      notifyListeners();
      return;
    }
    notifyListeners();
    unawaited(_hydrateQueueLabels());
    try {
      await _playCurrent(
        resumeIfSame: false,
        autoplay: autoplay,
        seekTo: Duration(milliseconds: snapshot.positionMs),
      );
    } on ApiException catch (e) {
      debugPrint('playback restore track failed: $e');
    }
  }

  Future<void> _expandQueueFromAlbum() {
    return _expanding ??= _expandQueueFromAlbumBody().whenComplete(() {
      _expanding = null;
    });
  }

  Future<void> _expandQueueFromAlbumBody() async {
    final current = track;
    if (current == null || queue.current == null) {
      return;
    }
    try {
      final album = await api.album(current.album.id);
      if (queue.current?.trackId != current.id) {
        return;
      }
      _rememberAlbum(album);
      if (album.tracks.length <= 1) {
        return;
      }
      final ordered = [...album.tracks]..sort((a, b) => a.trackNumber.compareTo(b.trackNumber));
      queue = queue.replacingWithAlbum(ordered.map((item) => item.id));
      _orderBeforeShuffle = [...queue.items];
      if (queue.shuffle) {
        queue = _shuffleQueue(queue);
      }
      notifyListeners();
      await _persistCommand(playing: playing);
    } catch (e) {
      debugPrint('playback album queue expand failed: $e');
    }
  }

  PlayerQueue _shuffleQueue(PlayerQueue source) => source.withShuffle(
        true,
        shuffleItems: (items) {
          if (items.length <= 1) {
            return [...items];
          }
          final copy = [...items]..shuffle();
          if (copy.length > 1 && copy.first.itemId == items.first.itemId) {
            copy.add(copy.removeAt(0));
          }
          return copy;
        },
      );

  void _rememberAlbum(AlbumDetail album) {
    coverObjectKey = album.coverObjectKey;
    for (final item in album.tracks) {
      queueLabels[item.id] = QueueTrackLabel(title: item.title, subtitle: album.artist.name);
    }
  }

  Future<void> _hydrateQueueLabels() async {
    final missing = [
      for (final item in queue.items)
        if (!queueLabels.containsKey(item.trackId)) item.trackId,
    ];
    for (final trackId in missing.take(40)) {
      try {
        final detail = await api.track(trackId);
        queueLabels[trackId] = QueueTrackLabel(title: detail.title, subtitle: detail.artist.name);
        notifyListeners();
      } catch (e) {
        debugPrint('playback queue label failed: $e');
      }
    }
  }

  Future<void> _ensureWriter() async {
    if (_sessionId != null) {
      return;
    }
    final created = await api.createPlaybackSession(deviceId: await api.deviceId());
    _sessionId = created.writerSessionId;
    _revision = created.snapshot.revision;
    try {
      await _paceStateWrite();
      final claimed = await api.claimPlaybackSession(_sessionId!, expectedRevision: _revision);
      _revision = claimed.revision;
    } on ApiException catch (e) {
      final snapshot = e.snapshot;
      if (snapshot != null) {
        _revision = snapshot.revision;
      }
      if (e.code == 'revision_conflict' && _sessionId != null) {
        await _paceStateWrite();
        final claimed = await api.claimPlaybackSession(_sessionId!, expectedRevision: _revision);
        _revision = claimed.revision;
        return;
      }
      if (e.code == 'not_writer') {
        _sessionId = null;
        rethrow;
      }
      rethrow;
    }
  }

  Future<void> _persistCommand({required bool playing}) async {
    _progressTimer?.cancel();
    await _enqueueWrite(() async {
      if (!await api.hasSession() || queue.isEmpty && track == null) {
        return;
      }
      await _putState(
        kind: 'command',
        state: {
          'trackId': queue.current?.trackId ?? track?.id,
          'positionMs': position.inMilliseconds,
          'isPlaying': playing,
          'qualityCode': requestedQuality ?? resolvedQuality ?? 'auto',
          'source': queue.current?.sourcePreference ?? 'catalog',
          'queue': queue.toJson(),
        },
      );
    });
  }

  Future<void> _persistProgress() async {
    await _enqueueWrite(() async {
      if (!await api.hasSession() || _sessionId == null || queue.current == null) {
        return;
      }
      await _putState(
        kind: 'progress',
        state: {
          'positionMs': position.inMilliseconds,
          'currentItemId': queue.currentItemId,
        },
      );
    });
  }

  void _scheduleProgress() {
    if (_sessionId == null || !playing) {
      return;
    }
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(seconds: 8), () {
      unawaited(_persistProgress());
    });
  }

  Future<void> _putState({required String kind, required Map<String, dynamic> state}) async {
    try {
      await _ensureWriter();
      final sessionId = _sessionId;
      if (sessionId == null) {
        return;
      }
      await _paceStateWrite();
      final snapshot = await api.putPlaybackState(
        expectedRevision: _revision,
        writerSessionId: sessionId,
        kind: kind,
        state: state,
      );
      _revision = snapshot.revision;
    } on ApiException catch (e) {
      if (e.code == 'revision_conflict' || e.code == 'not_writer') {
        _sessionId = null;
        if (e.snapshot != null) {
          _revision = e.snapshot!.revision;
        }
        if (kind == 'command') {
          try {
            await _ensureWriter();
            final sessionId = _sessionId;
            if (sessionId == null) {
              return;
            }
            await _paceStateWrite();
            final snapshot = await api.putPlaybackState(
              expectedRevision: _revision,
              writerSessionId: sessionId,
              kind: kind,
              state: state,
            );
            _revision = snapshot.revision;
          } catch (retryError) {
            debugPrint('playback persist retry failed: $retryError');
          }
        }
        return;
      }
      if (e.code != 'dependency_unavailable' && e.code != 'rate_limited') {
        debugPrint('playback persist failed: $e');
      }
    }
  }

  Future<void> _paceStateWrite() async {
    final last = _lastStateWrite;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      const minInterval = Duration(milliseconds: 550);
      if (elapsed < minInterval) {
        await Future<void>.delayed(minInterval - elapsed);
      }
    }
    _lastStateWrite = DateTime.now();
  }

  Future<void> _enqueueWrite(Future<void> Function() op) {
    _writes = _writes.then((_) => op()).catchError((Object e) {
      debugPrint('playback write failed: $e');
    });
    return _writes;
  }

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
      _emitNotice('Воспроизведение прервалось');
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
        sourcePreference: queue.current?.sourcePreference ?? 'catalog',
        qualityPreference: quality,
      );
      if (gen != _playGen) {
        return;
      }
      _expiresAt = url.expiresAt.toUtc();
      await handler.setUrl(url.url);
      try {
        await _seekPreservingSeconds(resume);
        unawaited(handler.play());
      } catch (e) {
        debugPrint('playback re-resolve seek failed, restarting at 0: $e');
        await handler.seek(Duration.zero);
        unawaited(handler.play());
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
    _progressTimer?.cancel();
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_eventSub?.cancel());
    unawaited(handler.release());
    super.dispose();
  }
}

class QueueTrackLabel {
  const QueueTrackLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}
