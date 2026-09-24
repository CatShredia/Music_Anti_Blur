/// Правила auth совпадают с API (`AuthValidation`) и CHECK в Postgres.
library;

class AuthRules {
  static const loginMin = 3;
  static const loginMax = 32;
  static const passwordMin = 12;
  static const passwordMax = 128;
  static const emailMin = 3;
  static const emailMax = 254;
  static const codeLength = 6;

  static const required = 'required';
  static const loginFormat = 'login_format';
  static const emailFormat = 'email_format';
  static const passwordLength = 'password_length';
  static const passwordCommon = 'password_common';
  static const codeFormat = 'code_format';
  static const identifierType = 'identifier_type';
  static const preferredQuality = 'preferred_quality';
  static const identifierTaken = 'identifier_taken';

  static const qualities = {'auto', 'aac_128', 'aac_256', 'src'};

  static final loginPattern = RegExp(r'^[a-zA-Z0-9_.-]{3,32}$');

  /// Тот же список, что `AuthValidation` в API.
  static const commonPasswords = {
    'password',
    'password123',
    'password1234',
    '123456789012',
    '1234567890123',
    'qwertyuiopas',
    'letmein12345',
    'adminpassword',
    'changeme1234',
    'iloveyou1234',
    'welcome12345',
    'monkey123456',
    'dragon123456',
    'master123456',
    'login1234567',
    'abc123456789',
    'passw0rd1234',
    'admin1234567',
    'rootpassword1',
  };

  static String? loginCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return required;
    }
    if (!loginPattern.hasMatch(trimmed)) {
      return loginFormat;
    }
    return null;
  }

  static String? emailCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return required;
    }
    final normalized = trimmed.toLowerCase();
    if (normalized.length < emailMin ||
        normalized.length > emailMax ||
        !_emailPattern.hasMatch(normalized)) {
      return emailFormat;
    }
    return null;
  }

  static String? passwordCode(String? value) {
    if (value == null || value.isEmpty) {
      return required;
    }
    final runes = value.runes.length;
    if (runes < passwordMin || runes > passwordMax) {
      return passwordLength;
    }
    if (commonPasswords.contains(value.toLowerCase()) ||
        commonPasswords.contains(value.trim().toLowerCase())) {
      return passwordCommon;
    }
    return null;
  }

  static String? codeCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return required;
    }
    if (trimmed.length != codeLength || !_digits.hasMatch(trimmed)) {
      return codeFormat;
    }
    return null;
  }

  static String? qualityCode(String? value) {
    if (value == null || value.isEmpty) {
      return required;
    }
    if (!qualities.contains(value)) {
      return preferredQuality;
    }
    return null;
  }

  static Map<String, String> register({
    required String login,
    required String email,
    required String password,
  }) {
    return _codes({
      'login': loginCode(login),
      'email': emailCode(email),
      'password': passwordCode(password),
    });
  }

  static Map<String, String> login({
    required String identifierType,
    required String identifier,
    required String password,
  }) {
    final identifierError = identifierType == 'email' ? emailCode(identifier) : loginCode(identifier);
    return _codes({
      if (identifierType != 'email' && identifierType != 'login') 'identifierType': identifierType,
      'identifier': identifierError,
      if (password.isEmpty) 'password': required,
    });
  }

  static Map<String, String> forgot(String email) => _codes({'email': emailCode(email)});

  static Map<String, String> reset({required String code, required String newPassword}) {
    return _codes({
      'code': codeCode(code),
      'newPassword': passwordCode(newPassword),
    });
  }

  static Map<String, String> verify(String code) => _codes({'code': codeCode(code)});

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _digits = RegExp(r'^\d+$');

  static Map<String, String> _codes(Map<String, String?> raw) {
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final code = entry.value;
      if (code != null) {
        out[entry.key] = code;
      }
    }
    return out;
  }
}

class AuthMessages {
  static String field(String code) => switch (code) {
        AuthRules.required => 'Обязательное поле',
        AuthRules.loginFormat => '3–32 символа: латиница, цифры, _ . -',
        AuthRules.emailFormat => 'Введите корректный email',
        AuthRules.passwordLength => 'Пароль: 12–128 символов, без скрытой обрезки',
        AuthRules.passwordCommon => 'Пароль слишком простой, выберите другой',
        AuthRules.codeFormat => 'Код — 6 цифр из письма',
        AuthRules.identifierType => 'Выберите вход по email или логину',
        AuthRules.preferredQuality => 'Недопустимое качество',
        AuthRules.identifierTaken => 'Уже занято',
        'invalid_token' => 'Код недействителен или истёк',
        'search_query' => 'Введите от 2 до 100 символов',
        'year_range' => 'Год: 1000–9999',
        'track_number' => 'Номер трека должен быть ≥ 1',
        'duration' => 'Длительность должна быть больше нуля',
        'name_length' => 'Имя: 1–200 символов',
        'title_length' => 'Название: 1–200 символов',
        'cover_object_key' => 'Слишком длинный ключ обложки',
        'cover_type' => 'Обложка: только JPEG или PNG',
        'isrc_format' => 'ISRC: до 32 латинских букв и цифр',
        'limit_range' => 'Некорректный размер страницы',
        'file_too_large' => 'Файл слишком большой',
        'too_large' => 'Файл слишком большой',
        'unsupported_audio' => 'Этот формат аудио не поддерживается',
        _ => 'Проверьте поле',
      };

  static String problem(String code, {int? retryAfterSeconds}) => switch (code) {
        'validation_failed' => 'Проверьте поля формы',
        'invalid_credentials' => 'Неверный логин или пароль',
        'invalid_token' => 'Код недействителен или истёк',
        'email_not_verified' => 'Сначала подтвердите email. Вход по логину уже доступен.',
        'identifier_taken' => 'Логин или email уже заняты',
        'rate_limited' => retryAfterSeconds == null
            ? 'Слишком много попыток. Подождите немного.'
            : 'Слишком много попыток. Повторите через $retryAfterSeconds с.',
        'connection_failed' => 'Нет связи с сервером',
        'dependency_unavailable' => 'Сервис временно недоступен. Попробуйте позже.',
        'admin_required' => 'Недостаточно прав',
        'not_found' => 'Не найдено',
        'source_unavailable' => 'Трек пока нельзя воспроизвести',
        'quality_unavailable' => 'Это качество недоступно',
        'file_too_large' => 'Файл больше 100 МБ',
        'checksum_mismatch' => 'Файл повреждён при загрузке',
        _ => 'Не удалось выполнить запрос',
      };

  static Map<String, String> localizeFields(Map<String, String> codes) {
    return {for (final e in codes.entries) e.key: field(e.value)};
  }
}
