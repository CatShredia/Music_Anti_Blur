import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// GigaChat API использует сертификаты НУЦ Минцифры: их нет в стандартном
/// хранилище доверенных корней Android/iOS, поэтому обычный HTTPS-запрос
/// падает с `HandshakeException: CERTIFICATE_VERIFY_FAILED`.
///
/// Здесь проверка цепочки ослабляется только для доменов Sber — остальной
/// трафик приложения по-прежнему идёт через системные настройки TLS.
/// Правильное решение для продакшена — добавить корневой сертификат НУЦ
/// Минцифры в приложение (`setTrustedCertificatesBytes`) и убрать этот файл.
void configureGigaChatTls(Dio dio) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20)
        ..idleTimeout = const Duration(seconds: 5);
      client.badCertificateCallback =
          (X509Certificate certificate, String host, int port) => _isSberHost(host);
      return client;
    },
  );
}

bool _isSberHost(String host) {
  final value = host.toLowerCase();
  return value == 'giga.chat' ||
      value.endsWith('.giga.chat') ||
      value == 'sberbank.ru' ||
      value.endsWith('.sberbank.ru');
}
