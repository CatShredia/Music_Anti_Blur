import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/iretry_policy.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'playback_models.dart';
import 'playback_sync.dart';

class PlaybackHubClient {
  PlaybackHubClient({
    required this.url,
    required this.tokenFactory,
    required this.onSnapshot,
    this.onReconnected,
    this.onReconnecting,
  });

  final String url;
  final Future<String> Function() tokenFactory;
  final void Function(PlaybackSnapshot snapshot) onSnapshot;
  final Future<void> Function()? onReconnected;
  final Future<void> Function()? onReconnecting;

  HubConnection? _connection;
  var _stopped = true;
  var _starting = false;

  Future<void> start() async {
    _stopped = false;
    if (_starting || _connection?.state == HubConnectionState.Connected) {
      return;
    }
    _starting = true;
    try {
      await _ensureConnection();
      var attempt = 0;
      while (!_stopped) {
        try {
          if (_connection?.state == HubConnectionState.Connected) {
            return;
          }
          await _connection!.start();
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

    final connection = HubConnectionBuilder()
        .withUrl(
          url,
          options: HttpConnectionOptions(
            accessTokenFactory: tokenFactory,
            transport: HttpTransportType.WebSockets,
            skipNegotiation: false,
            requestTimeout: 20000,
          ),
        )
        .withAutomaticReconnect(reconnectPolicy: _ExpBackoffJitterPolicy())
        .build();
    connection.on('PlaybackSnapshot', _onHubArgs);
    connection.onreconnecting(({error}) {
      unawaited(_safe(onReconnecting));
    });
    connection.onreconnected(({connectionId}) {
      unawaited(_safe(onReconnected));
    });
    _connection = connection;
  }

  void _onHubArgs(List<Object?>? args) {
    final snapshot = snapshotFromHubArgs(args);
    if (snapshot != null) {
      onSnapshot(snapshot);
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
