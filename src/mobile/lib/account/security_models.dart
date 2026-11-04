/// Second step of sign-in: the password was right, a second factor is required.
class TwoFactorChallenge {
  TwoFactorChallenge({required this.challengeId, required this.methods, required this.expiresAt});

  final String challengeId;

  /// Subset of `totp`, `email`, `recovery` in the server's order.
  final List<String> methods;
  final DateTime expiresAt;

  factory TwoFactorChallenge.fromJson(Map<String, dynamic> json) => TwoFactorChallenge(
        challengeId: json['challengeId'] as String,
        methods: (json['methods'] as List<dynamic>).cast<String>(),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );

  static bool isChallenge(Map<String, dynamic> json) => json['twoFactorRequired'] == true;
}

class TwoFactorStatus {
  TwoFactorStatus({required this.totp, required this.email, required this.recoveryCodesLeft});

  final bool totp;
  final bool email;
  final int recoveryCodesLeft;

  bool get enabled => totp || email;

  factory TwoFactorStatus.fromJson(Map<String, dynamic> json) => TwoFactorStatus(
        totp: json['totp'] as bool? ?? false,
        email: json['email'] as bool? ?? false,
        recoveryCodesLeft: json['recoveryCodesLeft'] as int? ?? 0,
      );
}

class TotpSetup {
  TotpSetup({required this.secret, required this.otpauthUri});

  final String secret;
  final String otpauthUri;

  /// Secret split into groups of four for manual entry.
  String get groupedSecret {
    final out = StringBuffer();
    for (var i = 0; i < secret.length; i += 4) {
      if (i > 0) {
        out.write(' ');
      }
      out.write(secret.substring(i, i + 4 > secret.length ? secret.length : i + 4));
    }
    return out.toString();
  }

  factory TotpSetup.fromJson(Map<String, dynamic> json) => TotpSetup(
        secret: json['secret'] as String,
        otpauthUri: json['otpauthUri'] as String,
      );
}

class LoginEvent {
  LoginEvent({
    required this.id,
    required this.at,
    required this.ip,
    this.userAgent,
    required this.result,
    required this.method,
    this.deviceId,
    required this.currentDevice,
    this.notMeAt,
  });

  final String id;
  final DateTime at;
  final String ip;
  final String? userAgent;
  final String result;
  final String method;
  final String? deviceId;
  final bool currentDevice;
  final DateTime? notMeAt;

  bool get succeeded => result == 'success';

  String get resultLabel => switch (result) {
        'success' => 'Вход выполнен',
        'bad_password' => 'Неверный пароль',
        '2fa_required' => 'Пароль верный, ждали второй фактор',
        '2fa_failed' => 'Неверный код второго фактора',
        'refresh_reuse' => 'Повторное использование токена — сессия закрыта',
        _ => result,
      };

  String get methodLabel => switch (method) {
        'password' => 'пароль',
        'totp' => 'код из приложения',
        'email' => 'код из письма',
        'recovery' => 'резервный код',
        'refresh' => 'обновление сессии',
        _ => method,
      };

  factory LoginEvent.fromJson(Map<String, dynamic> json) => LoginEvent(
        id: json['id'] as String,
        at: DateTime.parse(json['at'] as String),
        ip: json['ip'] as String? ?? '',
        userAgent: json['userAgent'] as String?,
        result: json['result'] as String,
        method: json['method'] as String,
        deviceId: json['deviceId'] as String?,
        currentDevice: json['currentDevice'] as bool? ?? false,
        notMeAt: json['notMeAt'] == null ? null : DateTime.parse(json['notMeAt'] as String),
      );
}

class StorageQuota {
  StorageQuota({required this.usedBytes, required this.maxBytes, required this.usedFiles, required this.maxFiles});

  final int usedBytes;
  final int maxBytes;
  final int usedFiles;
  final int maxFiles;

  double get bytesRatio => maxBytes <= 0 ? 1 : (usedBytes / maxBytes).clamp(0, 1).toDouble();
  double get filesRatio => maxFiles <= 0 ? 1 : (usedFiles / maxFiles).clamp(0, 1).toDouble();

  bool fits(int sizeBytes) => usedFiles + 1 <= maxFiles && usedBytes + sizeBytes <= maxBytes;

  factory StorageQuota.fromJson(Map<String, dynamic> json) => StorageQuota(
        usedBytes: (json['usedBytes'] as num).toInt(),
        maxBytes: (json['maxBytes'] as num).toInt(),
        usedFiles: (json['usedFiles'] as num).toInt(),
        maxFiles: (json['maxFiles'] as num).toInt(),
      );

  static String formatBytes(int bytes) {
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final text = unit == 0 || value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }
}
