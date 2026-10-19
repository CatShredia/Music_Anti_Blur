import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'gigachat_config.dart';
import 'gigachat_tls.dart';

/// Ошибка обращения к GigaChat с готовым для показа текстом.
class GigaChatException implements Exception {
  GigaChatException(this.message, {this.status});

  /// Текст, который можно показать пользователю.
  final String message;

  /// HTTP-код ответа, если он был.
  final int? status;

  @override
  String toString() => message;
}

/// Сообщение в формате GigaChat/OpenAI Chat Completions.
class GigaChatMessage {
  const GigaChatMessage(this.role, this.content);

  const GigaChatMessage.system(this.content) : role = 'system';

  const GigaChatMessage.user(this.content) : role = 'user';

  const GigaChatMessage.assistant(this.content) : role = 'assistant';

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Тонкий клиент GigaChat API: получение токена доступа и запрос генерации.
class GigaChatClient {
  GigaChatClient({Dio? http}) : _http = http ?? _defaultHttp();

  static const _uuid = Uuid();

  final Dio _http;

  String? _token;
  DateTime? _tokenExpiresAt;

  static Dio _defaultHttp() {
    final dio = Dio(
      BaseOptions(
        baseUrl: GigaChatConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );
    configureGigaChatTls(dio);
    return dio;
  }

  /// Возвращает токен доступа, запрашивая новый только когда старый истёк.
  Future<String> accessToken({bool force = false}) async {
    if (GigaChatConfig.authorizationKey.trim().isEmpty) {
      throw GigaChatException(
        'Ключ GigaChat не задан. Запусти приложение с '
        '--dart-define-from-file=gigachat.local.json или с '
        '--dart-define=GIGACHAT_AUTH_KEY=<ключ>.',
      );
    }

    final cached = _token;
    final expiresAt = _tokenExpiresAt;
    if (!force &&
        cached != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt)) {
      return cached;
    }

    final Response<dynamic> response;
    try {
      response = await _http.post<dynamic>(
        GigaChatConfig.oauthUrl,
        // Тело отправляем строкой: так кодирование формы не зависит от версии dio.
        data: 'scope=${GigaChatConfig.scope}',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Accept': 'application/json',
            'RqUID': _uuid.v4(),
            'Authorization': 'Basic ${GigaChatConfig.authorizationKey}',
          },
          validateStatus: (code) => code != null && code < 500,
        ),
      );
    } on DioException catch (error) {
      throw _friendly(error);
    }

    final data = response.data;
    final token = data is Map ? data['access_token'] : null;
    if (response.statusCode != 200 || token is! String || token.isEmpty) {
      throw _failure(data, response.statusCode);
    }

    _token = token;
    _tokenExpiresAt = _expiryFrom(data is Map ? data['expires_at'] : null);
    return token;
  }

  /// Отправляет историю диалога в GigaChat и возвращает текст ответа.
  Future<String> complete(List<GigaChatMessage> messages) async {
    if (messages.isEmpty) {
      throw GigaChatException('Пустой запрос к GigaChat.');
    }

    final payload = <GigaChatMessage>[
      const GigaChatMessage.system(GigaChatConfig.systemPrompt),
      ...messages,
    ];

    var token = await accessToken();

    for (var attempt = 0; attempt < 2; attempt++) {
      final Response<dynamic> response;
      try {
        response = await _http.post<dynamic>(
          GigaChatConfig.chatPath,
          data: {
            'model': GigaChatConfig.model,
            'messages': [for (final message in payload) message.toJson()],
            'temperature': GigaChatConfig.temperature,
            'max_tokens': GigaChatConfig.maxTokens,
            'stream': false,
          },
          options: Options(
            contentType: 'application/json; charset=utf-8',
            headers: {'Authorization': 'Bearer $token'},
            validateStatus: (code) => code != null && code < 500,
          ),
        );
      } on DioException catch (error) {
        throw _friendly(error);
      }

      // Токен мог истечь между запросами — обновляем и пробуем ещё раз.
      if (response.statusCode == 401 && attempt == 0) {
        token = await accessToken(force: true);
        continue;
      }

      final data = response.data;
      if (response.statusCode != 200 || data is! Map) {
        throw _failure(data, response.statusCode);
      }

      final content = _contentOf(data);
      if (content == null || content.trim().isEmpty) {
        throw GigaChatException(
          'GigaChat вернул пустой ответ. Попробуй написать иначе.',
          status: response.statusCode,
        );
      }
      return content.trim();
    }

    throw GigaChatException(
      'GigaChat не принял токен доступа. Проверь ключ API.',
      status: 401,
    );
  }

  /// Сбрасывает закэшированный токен (например, после ошибки авторизации).
  void resetToken() {
    _token = null;
    _tokenExpiresAt = null;
  }

  static String? _contentOf(Map<dynamic, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }
    final first = choices.first;
    if (first is! Map) {
      return null;
    }
    final message = first['message'];
    if (message is! Map) {
      return null;
    }
    final content = message['content'];
    return content is String ? content : null;
  }

  /// `expires_at` приходит в миллисекундах Unix-времени; на всякий случай
  /// поддерживаем и секунды, а при странном значении берём запас в 25 минут.
  static DateTime _expiryFrom(Object? raw) {
    final now = DateTime.now();
    if (raw is num && raw > 0) {
      final value = raw.toInt();
      final date = value > 100000000000
          ? DateTime.fromMillisecondsSinceEpoch(value)
          : DateTime.fromMillisecondsSinceEpoch(value * 1000);
      final safe = date.subtract(const Duration(seconds: 60));
      if (safe.isAfter(now)) {
        return safe;
      }
    }
    return now.add(const Duration(minutes: 25));
  }

  static GigaChatException _failure(Object? data, int? status) {
    final raw = _serviceMessage(data);
    final friendly = _statusMessage(status);
    if (friendly == null) {
      return GigaChatException(
        raw == null ? 'GigaChat вернул ошибку ${status ?? ''}'.trim() : raw,
        status: status,
      );
    }
    return GigaChatException(friendly, status: status);
  }

  static String? _serviceMessage(Object? data) {
    if (data is String) {
      final trimmed = data.trim();
      return trimmed.isEmpty || trimmed.length > 200 ? null : trimmed;
    }
    if (data is! Map) {
      return null;
    }
    final message = data['message'] ?? data['error_description'];
    if (message is String && message.isNotEmpty) {
      return message.length > 200 ? '${message.substring(0, 200)}…' : message;
    }
    final error = data['error'];
    if (error is String && error.isNotEmpty) {
      return error;
    }
    if (error is Map && error['message'] is String) {
      final value = error['message'] as String;
      return value.length > 200 ? '${value.substring(0, 200)}…' : value;
    }
    return null;
  }

  static String? _statusMessage(int? status) {
    switch (status) {
      case 400:
        return 'GigaChat не понял запрос. Попробуй переформулировать.';
      case 401:
        return 'GigaChat отклонил токен доступа. Проверь ключ API.';
      case 403:
        return 'У ключа нет доступа к GigaChat API (проверь scope).';
      case 404:
        return 'Выбранная модель недоступна для этого ключа.';
      case 413:
      case 422:
        return 'Запрос слишком длинный. Сократи список исполнителей.';
      case 429:
        return 'Слишком много запросов к GigaChat. Подожди пару секунд.';
      default:
        if (status != null && status >= 500) {
          return 'Сервис GigaChat временно недоступен. Попробуй позже.';
        }
        return null;
    }
  }

  static GigaChatException _friendly(DioException error) {
    final status = error.response?.statusCode;
    if (status != null) {
      return _failure(error.response?.data, status);
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return GigaChatException('GigaChat не ответил вовремя. Попробуй ещё раз.');
      case DioExceptionType.badCertificate:
        return GigaChatException(
          'Не удалось проверить сертификат GigaChat. Проверь системное время.',
        );
      case DioExceptionType.cancel:
        return GigaChatException('Запрос к GigaChat отменён.');
      case DioExceptionType.connectionError:
        return GigaChatException('Нет связи с GigaChat. Проверь интернет.');
      default:
        return GigaChatException(
          'Не удалось связаться с GigaChat${error.message == null ? '.' : ': ${error.message}'}',
        );
    }
  }
}
