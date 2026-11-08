import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:music_anti_blur/api/api_client.dart';

/// Поддельный сервер: `METHOD /path` (без query) -> (статус, тело). Нет маршрута: GET -> 404, прочее -> 204.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.routes);

  final Map<String, (int, Object?)> routes;
  final requested = <String>[];

  /// Клиент с этим сервером и «залогиненным» хранилищем.
  ApiClient client() {
    FlutterSecureStorage.setMockInitialValues({'access': 'a', 'refresh': 'r', 'device': 'd'});
    return ApiClient(baseUrl: 'http://fake', adapter: this);
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final key = '${options.method} ${options.path}';
    requested.add(key);
    final route = routes[key];
    if (route == null) {
      return options.method == 'GET'
          ? _json(404, {'code': 'not_found', 'title': 'Not found'})
          : ResponseBody.fromString('', 204);
    }
    return _json(route.$1, route.$2);
  }

  static ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}
