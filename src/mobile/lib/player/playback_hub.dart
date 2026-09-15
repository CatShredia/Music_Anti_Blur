import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/ihub_protocol.dart';
import 'package:signalr_netcore/iretry_policy.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'playback_models.dart';
import 'playback_sync.dart';

class PlaybackHubClient {
  PlaybackHubClient({
    required this.url,
    required this.deviceId,
    required this.tokenFactory,
    required this.onSnapshot,
    this.onPresence,
    this.onRenditionReady,
    this.onReconnected,
    this.onReconnecting,
  });

  final String url;
  final String deviceId;
  final Future<String> Function() tokenFactory;
  final void Function(PlaybackSnapshot snapshot) onSnapshot;
  final void Function(DevicePresence presence)? onPresence;
  final void Function(RenditionReady ready)? onRenditionReady;
  final Future<void> Function()? onReconnected;
  final Future<void> Function()? onReconnecting;

  HubConnection? _connection;
  Timer? _heartbeat;
  var _stopped = true;
  var _starting = false;

  String get _connectUrl {
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}deviceId=${Uri.encodeComponent(deviceId)}';
  }

  Future<void> start() async {
    _stopped = false;
    if (_starting || _connection?.state == HubConnectionState.Connected) {
      _startHeartbeat();
      return;
    }
    _starting = true;
    try {
      await _ensureConnection();
      var attempt = 0;
      while (!_stopped) {
        try {
          if (_connection?.state == HubConnectionState.Connected) {
            _startHeartbeat();
            return;
          }
          await _connection!.start();
          _startHeartbeat();
          return;
        } catch (e) {
          debugPrint('playback hub start failed: $e');
          await _safe(onReconnecting);
          attempt++;
          await Future<void>.delayed(_backoff(attempt));
          if (_stopped) {
            return;
          }
          await _ensureConnection(rebuild: true);
        }
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    final connection = _connection;
    _connection = null;
    if (connection == null) {
      return;
    }
    try {
      await connection.stop();
    } catch (e) {
      debugPrint('playback hub stop failed: $e');
    }
  }

  Future<void> _ensureConnection({bool rebuild = false}) async {
    if (_connection != null && !rebuild) {
      return;
    }
    if (_connection != null) {
      try {
        await _connection!.stop();
      } catch (_) {}
      _connection = null;
    }

    final headers = MessageHeaders()..setHeaderValue('X-Device-Id', deviceId);
    final connection = HubConnectionBuilder()
        .withUrl(
          _connectUrl,
          options: HttpConnectionOptions(
            accessTokenFactory: tokenFactory,
            transport: HttpTransportType.WebSockets,
            skipNegotiation: false,
            requestTimeout: 20000,
            headers: headers,
          ),
        )
        .withAutomaticReconnect(reconnectPolicy: _ExpBackoffJitterPolicy())
        .build();
    connection.on('PlaybackSnapshot', _onSnapshotArgs);
    connection.on('DevicePresence', _onPresenceArgs);
    connection.on('RenditionReady', _onRenditionArgs);
    connection.onreconnecting(({error}) {
      unawaited(_safe(onReconnecting));
    });
    connection.onreconnected(({connectionId}) {
      unawaited(_safe(onReconnected));
      _startHeartbeat();
    });
    _connection = connection;
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_beat());
    });
    unawaited(_beat());
  }

  Future<void> _beat() async {
    final connection = _connection;
    if (_stopped || connection == null || connection.state != HubConnectionState.Connected) {
      return;
    }
    try {
      await connection.invoke('Heartbeat');
    } catch (e) {
      debugPrint('playback hub heartbeat failed: $e');
    }
  }

  void _onSnapshotArgs(List<Object?>? args) {
    final snapshot = snapshotFromHubArgs(args);
    if (snapshot != null) {
      onSnapshot(snapshot);
    }
  }

  void _onPresenceArgs(List<Object?>? args) {
    final presence = presenceFromHubArgs(args);
    if (presence != null) {
      onPresence?.call(presence);
    }
  }

  void _onRenditionArgs(List<Object?>? args) {
    final ready = renditionReadyFromHubArgs(args);
    if (ready != null) {
      onRenditionReady?.call(ready);
    }
  }

  static Future<void> _safe(Future<void> Function()? fn) async {
    if (fn == null) {
      return;
    }
    try {
      await fn();
    } catch (e) {
      debugPrint('playback hub callback failed: $e');
    }
  }

  static Duration _backoff(int attempt) {
    final exp = min(attempt, 6);
    final baseMs = min(400 * (1 << exp), 30000);
    final jitter = Random().nextInt(300);
    return Duration(milliseconds: baseMs + jitter);
  }
}

class _ExpBackoffJitterPolicy implements IRetryPolicy {
  final _random = Random();

  @override
  int? nextRetryDelayInMilliseconds(RetryContext retryContext) {
    final exp = min(retryContext.previousRetryCount, 6);
    final base = min(400 * (1 << exp), 30000);
    return base + _random.nextInt(300);
  }
}
