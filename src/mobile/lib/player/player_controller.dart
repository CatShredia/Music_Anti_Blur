import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_client.dart';
import '../catalog/catalog_models.dart';
import '../overrides/local_binding_store.dart';
import '../overrides/override_models.dart';
import 'audio_handler.dart';
import 'playback_hub.dart';
import 'playback_models.dart';
import 'playback_sync.dart';
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
  PlayerController(this.api, {required this.handler, LocalBindingStore? bindings})
      : bindings = bindings ?? LocalBindingStore();

  final ApiClient api;
  final MusicAudioHandler handler;
  final LocalBindingStore bindings;

  PlayerQueue queue = PlayerQueue.empty;
  TrackDetail? track;
  String? requestedQuality;
  String? resolvedQuality;
  String? resolvedSource;
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
  String? myDeviceId;
  List<DevicePresenceItem> devices = const [];
  RenditionReady? lastRenditionReady;
  int renditionEpoch = 0;

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
  Timer? _followTimer;
  Future<void> _writes = Future.value();
  Future<void>? _expanding;
  List<QueueItem>? _orderBeforeShuffle;
  DateTime? _lastStateWrite;
  DateTime? _remoteUpdatedAt;
  int _remotePositionMs = 0;
  PlaybackHubClient? _hub;
  bool _followingRemote = false;
  bool _remoteLocalFallbackNotice = false;
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
      if (_followingRemote) {
        return;
      }
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
      if (_followingRemote) {
        return;
      }
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
    if (!await api.hasSession()) {
      return;
    }
    unawaited(_connectHub());
    if (_restored) {
      return;
    }
    _restored = true;
    final gen = _playGen;
    try {
      final snapshot = await api.playbackState();
      if (gen != _playGen || _starting) {
        return;
      }
      final myDevice = await api.deviceId();
      final otherDevice = snapshot.deviceId != null && snapshot.deviceId != myDevice;
      if (otherDevice) {
        await _applyRemoteSnapshot(snapshot);
        return;
      }
      if (playing) {
        return;
      }
      await _applySnapshot(snapshot, autoplay: false);
    } catch (e) {
      debugPrint('playback restore failed: $e');
    }
  }

  Future<void> playTrack(
    String trackId, {
    String source = 'auto',
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

  Future<void> setItemSource(String sourcePreference) async {
    if (_followingRemote) {
      return;
    }
    final current = queue.current;
    if (current == null) {
      return;
    }
    queue = queue.withItemSource(current.itemId, sourcePreference);
    notifyListeners();
    await _playAndPersist(resumeIfSame: true);
  }

  Future<void> setQuality(String quality) async {
    if (_followingRemote || queue.current == null) {
      return;
    }
    requestedQuality = quality;
    await _playAndPersist(resumeIfSame: true);
  }

  Future<void> togglePlay() async {
    if (_followingRemote) {
      await playHere();
      return;
    }
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

  Future<void> playHere() async {
    if (queue.current == null) {
      return;
    }
    _remoteLocalFallbackNotice = resolvedSource == 'local';
    _stopFollowing();
    _starting = true;
    try {
      await _playCurrent(resumeIfSame: false, autoplay: true, seekTo: position);
    } catch (_) {
      unawaited(_persistCommand(playing: false));
      rethrow;
    } finally {
      _starting = false;
    }
    await _persistCommand(playing: true);
  }

  Future<void> seek(Duration value) async {
    if (_followingRemote) {
      return;
    }
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
    if (_followingRemote) {
      return;
    }
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
    if (_followingRemote) {
      return;
    }
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
    if (_followingRemote) {
      return;
    }
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
    if (_followingRemote) {
      return;
    }
    queue = queue.cycleRepeat();
    notifyListeners();
    await _persistCommand(playing: playing);
  }

  Future<void> toggleShuffle() async {
    if (_followingRemote) {
      return;
    }
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
    await _hub?.stop();
    _hub = null;
    _stopFollowing();
    _sessionId = null;
    _revision = 0;
    _restored = false;
    _progressTimer?.cancel();
    queue = PlayerQueue.empty;
    track = null;
    coverObjectKey = null;
    queueLabels.clear();
    _orderBeforeShuffle = null;
    devices = const [];
    lastRenditionReady = null;
    renditionEpoch = 0;
    await stop();
  }

  bool get followsSettings => requestedQuality == null || requestedQuality == 'auto';

  bool get hasQueue => queue.current != null;

  bool get hasLastTrack => track != null || hasQueue;

  bool get followingRemote => _followingRemote;

  bool get canSkipNext => !_followingRemote && queue.hasNext;

  bool get canSkipPrevious => !_followingRemote && (queue.hasPrevious || position > Duration.zero);

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
    _remoteLocalFallbackNotice = false;
    _stopFollowing();
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
      final local = await bindings.get(item.trackId);
      final localOk = local != null;
      final remoteLocalOnly = _remoteLocalFallbackNotice && !localOk;
      _remoteLocalFallbackNotice = false;
      final wantsLocal = item.sourcePreference == 'auto' || item.sourcePreference == 'local';
      TrackDetail? detail = track?.id == item.trackId ? track : null;
      try {
        detail = await api.track(item.trackId);
      } catch (e) {
        if (!localOk || !wantsLocal) {
          rethrow;
        }
      }
      if (gen != _playGen) {
        return;
      }

      Duration? loaded;
      var durationMs = detail?.durationMs ?? local?.durationMs;
      if (wantsLocal && local != null) {
        final media = _mediaItem(detail, item, local, durationMs);
        loaded = await handler.setFilePath(local.copiedPath, item: media);
        resolvedSource = 'local';
        resolvedQuality = null;
        _expiresAt = null;
        _refreshUsed = true;
      } else {
        var preference = requestedQuality ?? 'auto';
        try {
          preference = requestedQuality ?? (await api.settings()).preferredQuality;
        } catch (_) {}
        final url = await api.playbackUrl(
          trackId: item.trackId,
          sourcePreference: item.sourcePreference,
          qualityPreference: preference,
          localAvailable: localOk,
        );
        if (gen != _playGen) {
          return;
        }
        resolvedSource = url.resolvedSource;
        resolvedQuality = url.resolvedQuality;
        qualityFallbackFrom = url.qualityFallbackFrom;
        durationMs = url.durationMs ?? durationMs;
        _expiresAt = url.expiresAt?.toUtc();
        _refreshUsed = url.isLocal;
        if (url.isLocal) {
          if (local == null) {
            throw ApiException(422, 'source_unavailable', 'No playable source.');
          }
          loaded = await handler.setFilePath(
            local.copiedPath,
            item: _mediaItem(detail, item, local, durationMs),
          );
        } else {
          final remote = url.url;
          if (remote == null || remote.isEmpty) {
            throw ApiException(422, 'source_unavailable', 'No playable source.');
          }
          loaded = await handler.setUrl(
            remote,
            item: _mediaItem(detail, item, local, durationMs),
          );
        }
        final fallback = fallbackNotice(url.fallbackReason);
        if (fallback.isNotEmpty) {
          _emitNotice(fallback);
        } else if (remoteLocalOnly && resolvedSource != 'local') {
          _emitNotice('Локальный файл на другом устройстве');
        }
      }

      if (gen != _playGen) {
        return;
      }
      track = detail ??
          TrackDetail(
            id: item.trackId,
            title: local?.displayName ?? labelFor(item).title,
            trackNumber: 1,
            artist: ArtistRef(id: '', name: ''),
            album: AlbumRef(id: '', title: ''),
            availableQualities: const [],
            durationMs: durationMs,
          );
      queueLabels[track!.id] = QueueTrackLabel(title: track!.title, subtitle: track!.artist.name);
      if (loaded != null && loaded > Duration.zero) {
        duration = loaded;
      } else if (durationMs != null && durationMs > 0) {
        duration = Duration(milliseconds: durationMs);
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
      if (qualityFallbackFrom != null) {
        _emitNotice('Включено ${resolvedQuality ?? qualityFallbackFrom}');
      }
    } on ApiException catch (e) {
      if (e.code == 'source_unavailable' || e.code == 'quality_unavailable' || e.code == 'connection_failed') {
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

  MediaItem _mediaItem(TrackDetail? detail, QueueItem item, LocalTrackBinding? local, int? durationMs) {
    return MediaItem(
      id: detail?.id ?? item.trackId,
      title: detail?.title ?? local?.displayName ?? 'Трек',
      album: detail?.album.title,
      artist: detail?.artist.name,
      duration: durationMs != null && durationMs > 0 ? Duration(milliseconds: durationMs) : null,
    );
  }

  Future<void> _onCompleted() async {
    if (_followingRemote || _completing) {
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
    if (_starting || playing || _followingRemote) {
      return;
    }
    _revision = snapshot.revision;
    queue = snapshot.queue;
    requestedQuality = snapshot.qualityCode;
    resolvedSource = snapshot.source;
    position = Duration(milliseconds: snapshot.positionMs);
    _adoptSnapshotTrack(snapshot);
    notifyListeners();
    if (snapshot.trackId == null || queue.current == null) {
      return;
    }
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

  Future<void> _connectHub() async {
    if (!await api.hasSession()) {
      return;
    }
    final deviceId = await api.deviceId();
    myDeviceId = deviceId;
    _hub ??= PlaybackHubClient(
      url: api.hubUrl,
      deviceId: deviceId,
      tokenFactory: _hubToken,
      onSnapshot: (snapshot) => unawaited(_onHubSnapshot(snapshot)),
      onPresence: _onPresence,
      onRenditionReady: _onRenditionReady,
      onReconnecting: () async {
        await api.refresh();
      },
      onReconnected: () async {
        try {
          await _onHubSnapshot(await api.playbackState());
        } catch (e) {
          debugPrint('playback hub resync failed: $e');
        }
      },
    );
    try {
      await _hub!.start();
    } catch (e) {
      debugPrint('playback hub connect failed: $e');
    }
  }

  Future<String> _hubToken() async {
    var token = await api.accessToken();
    if (token != null && token.isNotEmpty) {
      return token;
    }
    await api.refresh();
    return await api.accessToken() ?? '';
  }

  Future<void> _onHubSnapshot(PlaybackSnapshot snapshot) async {
    final myDevice = await api.deviceId();
    if (shouldIgnoreRemoteSnapshot(
      localRevision: _revision,
      incomingRevision: snapshot.revision,
      localDeviceId: myDevice,
      incomingDeviceId: snapshot.deviceId,
    )) {
      if (snapshot.revision > _revision) {
        _revision = snapshot.revision;
      }
      return;
    }
    await _applyRemoteSnapshot(snapshot);
  }

  void _onPresence(DevicePresence presence) {
    devices = presence.devices;
    notifyListeners();
  }

  void _onRenditionReady(RenditionReady ready) {
    lastRenditionReady = ready;
    renditionEpoch++;
    notifyListeners();
    if (ready.scope == 'private') {
      _emitNotice('Private-копия готова');
    }
  }

  Future<void> _applyRemoteSnapshot(PlaybackSnapshot snapshot) async {
    _playGen++;
    _starting = false;
    _progressTimer?.cancel();
    _sessionId = null;
    _followingRemote = true;
    _revision = snapshot.revision;
    _remoteUpdatedAt = snapshot.updatedAt ?? DateTime.now().toUtc();
    _remotePositionMs = snapshot.positionMs;
    queue = snapshot.queue;
    requestedQuality = snapshot.qualityCode;
    resolvedSource = snapshot.source;
    resolvedQuality = snapshot.qualityCode;
    playing = snapshot.isPlaying;
    loading = false;
    position = Duration(
      milliseconds: interpolatePositionMs(
        positionMs: snapshot.positionMs,
        isPlaying: snapshot.isPlaying,
        updatedAt: _remoteUpdatedAt!,
        now: DateTime.now().toUtc(),
        durationMs: duration.inMilliseconds > 0 ? duration.inMilliseconds : null,
      ),
    );
    _adoptSnapshotTrack(snapshot);
    notifyListeners();
    await _silenceLocalAudio();
    _syncFollowClock();
    unawaited(_hydrateFollowedTrack(snapshot));
  }

  void _adoptSnapshotTrack(PlaybackSnapshot snapshot) {
    final id = snapshot.trackId ?? queue.current?.trackId;
    if (id == null) {
      track = null;
      return;
    }
    if (track?.id == id) {
      return;
    }
    final item = queue.current;
    final label = item != null ? labelFor(item) : null;
    track = TrackDetail(
      id: id,
      title: label?.title ?? 'Трек',
      trackNumber: 1,
      artist: ArtistRef(id: '', name: label?.subtitle ?? ''),
      album: AlbumRef(id: '', title: ''),
      availableQualities: const [],
    );
  }

  Future<void> _silenceLocalAudio() async {
    try {
      await handler.pause();
    } catch (e) {
      debugPrint('playback interrupt pause failed: $e');
    }
    try {
      await handler.stop();
    } catch (e) {
      debugPrint('playback interrupt stop failed: $e');
    }
  }

  Future<void> _hydrateFollowedTrack(PlaybackSnapshot snapshot) async {
    final id = snapshot.trackId ?? queue.current?.trackId;
    if (id == null) {
      track = null;
      notifyListeners();
      return;
    }
    try {
      final detail = await api.track(id);
      if (!_followingRemote) {
        return;
      }
      track = detail;
      queueLabels[detail.id] = QueueTrackLabel(title: detail.title, subtitle: detail.artist.name);
      if (detail.durationMs != null && detail.durationMs! > 0) {
        duration = Duration(milliseconds: detail.durationMs!);
        _syncFollowClock();
      }
      notifyListeners();
      if (detail.album.id.isNotEmpty) {
        try {
          final album = await api.album(detail.album.id);
          if (_followingRemote) {
            _rememberAlbum(album);
            notifyListeners();
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('playback follow track failed: $e');
      if (_followingRemote && track?.id != id) {
        final item = queue.current;
        track = TrackDetail(
          id: id,
          title: item != null ? labelFor(item).title : 'Трек',
          trackNumber: 1,
          artist: ArtistRef(id: '', name: ''),
          album: AlbumRef(id: '', title: ''),
          availableQualities: const [],
        );
        notifyListeners();
      }
    }
    unawaited(_hydrateQueueLabels());
  }

  void _stopFollowing() {
    _followTimer?.cancel();
    _followTimer = null;
    _followingRemote = false;
    _remoteUpdatedAt = null;
    _remotePositionMs = 0;
  }

  void _syncFollowClock() {
    _followTimer?.cancel();
    if (!_followingRemote || !playing) {
      return;
    }
    _followTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final started = _remoteUpdatedAt;
      if (!_followingRemote || started == null) {
        return;
      }
      position = Duration(
        milliseconds: interpolatePositionMs(
          positionMs: _remotePositionMs,
          isPlaying: playing,
          updatedAt: started,
          now: DateTime.now().toUtc(),
          durationMs: duration.inMilliseconds > 0 ? duration.inMilliseconds : null,
        ),
      );
      notifyListeners();
    });
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
    if (_followingRemote) {
      return;
    }
    if (_sessionId != null) {
      return;
    }
    final created = await api.createPlaybackSession(deviceId: await api.deviceId());
    if (_followingRemote) {
      return;
    }
    _sessionId = created.writerSessionId;
    _revision = created.snapshot.revision;
    try {
      await _paceStateWrite();
      if (_followingRemote) {
        _sessionId = null;
        return;
      }
      final claimed = await api.claimPlaybackSession(_sessionId!, expectedRevision: _revision);
      _revision = claimed.revision;
    } on ApiException catch (e) {
      final snapshot = e.snapshot;
      if (snapshot != null) {
        final myDevice = await api.deviceId();
        if (snapshot.deviceId != null && snapshot.deviceId != myDevice) {
          _sessionId = null;
          await _applyRemoteSnapshot(snapshot);
          return;
        }
        _revision = snapshot.revision;
      }
      if (e.code == 'revision_conflict' && _sessionId != null && !_followingRemote) {
        await _paceStateWrite();
        final claimed = await api.claimPlaybackSession(_sessionId!, expectedRevision: _revision);
        _revision = claimed.revision;
        return;
      }
      if (e.code == 'not_writer') {
        _sessionId = null;
        if (e.snapshot != null) {
          await _applyRemoteSnapshot(e.snapshot!);
        }
        return;
      }
      rethrow;
    }
  }

  Future<void> _persistCommand({required bool playing}) async {
    _progressTimer?.cancel();
    await _enqueueWrite(() async {
      if (_followingRemote || !await api.hasSession() || queue.isEmpty && track == null) {
        return;
      }
      await _putState(
        kind: 'command',
        state: {
          'trackId': queue.current?.trackId ?? track?.id,
          'positionMs': position.inMilliseconds,
          'isPlaying': playing,
          'qualityCode': requestedQuality ?? resolvedQuality ?? 'auto',
          'source': resolvedSource ?? 'catalog',
          'queue': queue.toJson(),
        },
      );
    });
  }

  Future<void> _persistProgress() async {
    await _enqueueWrite(() async {
      if (_followingRemote || !await api.hasSession() || _sessionId == null || queue.current == null) {
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
    if (_followingRemote || _sessionId == null || !playing) {
      return;
    }
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_persistProgress());
    });
  }

  Future<void> _putState({required String kind, required Map<String, dynamic> state}) async {
    if (_followingRemote) {
      return;
    }
    try {
      await _ensureWriter();
      if (_followingRemote) {
        return;
      }
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
      if (e.code == 'not_writer') {
        _sessionId = null;
        if (e.snapshot != null) {
          await _applyRemoteSnapshot(e.snapshot!);
        }
        return;
      }
      if (e.code == 'revision_conflict') {
        final snapshot = e.snapshot;
        if (snapshot != null) {
          final myDevice = await api.deviceId();
          if (snapshot.deviceId != null && snapshot.deviceId != myDevice) {
            _sessionId = null;
            await _applyRemoteSnapshot(snapshot);
            return;
          }
          _revision = snapshot.revision;
        }
        if (kind == 'command') {
          try {
            await _ensureWriter();
            final sessionId = _sessionId;
            if (sessionId == null) {
              return;
            }
            await _paceStateWrite();
            final retried = await api.putPlaybackState(
              expectedRevision: _revision,
              writerSessionId: sessionId,
              kind: kind,
              state: state,
            );
            _revision = retried.revision;
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
    if (_refreshUsed || _refreshing || current == null || quality == null || resolvedSource == 'local') {
      return;
    }
    _refreshing = true;
    _refreshUsed = true;
    final gen = _playGen;
    final resume = handler.position;
    try {
      final url = await api.playbackUrl(
        trackId: current.id,
        sourcePreference: queue.current?.sourcePreference ?? 'auto',
        qualityPreference: quality,
        localAvailable: await bindings.isAvailable(current.id),
      );
      if (gen != _playGen) {
        return;
      }
      if (url.isLocal || url.url == null) {
        return;
      }
      _expiresAt = url.expiresAt?.toUtc();
      await handler.setUrl(url.url!);
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
    _followTimer?.cancel();
    unawaited(_hub?.stop());
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
