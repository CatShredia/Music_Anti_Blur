import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/account/security_models.dart';

void main() {
  test('login response with twoFactorRequired is a challenge', () {
    final json = {
      'twoFactorRequired': true,
      'challengeId': '6f1b0a52-0000-0000-0000-000000000001',
      'methods': ['totp', 'recovery'],
      'expiresAt': '2026-11-03T12:05:00Z',
    };
    expect(TwoFactorChallenge.isChallenge(json), isTrue);
    final challenge = TwoFactorChallenge.fromJson(json);
    expect(challenge.methods, ['totp', 'recovery']);
    expect(TwoFactorChallenge.isChallenge({'accessToken': 'x'}), isFalse);
  });

  test('totp secret is grouped by four', () {
    final setup = TotpSetup(secret: 'ABCDEFGHIJ', otpauthUri: 'otpauth://totp/x');
    expect(setup.groupedSecret, 'ABCD EFGH IJ');
  });

  test('quota fits checks bytes and files', () {
    final q = StorageQuota(usedBytes: 900, maxBytes: 1000, usedFiles: 4, maxFiles: 5);
    expect(q.fits(100), isTrue);
    expect(q.fits(101), isFalse);
    final full = StorageQuota(usedBytes: 0, maxBytes: 1000, usedFiles: 5, maxFiles: 5);
    expect(full.fits(1), isFalse);
    expect(full.filesRatio, 1);
  });

  test('bytes are formatted', () {
    expect(StorageQuota.formatBytes(512), '512 Б');
    expect(StorageQuota.formatBytes(1536), '1.5 КБ');
    expect(StorageQuota.formatBytes(2 * 1024 * 1024 * 1024), '2.0 ГБ');
  });

  test('login event labels', () {
    final e = LoginEvent.fromJson({
      'id': 'a',
      'at': '2026-11-03T12:00:00Z',
      'ip': '10.0.0.1',
      'result': '2fa_failed',
      'method': 'totp',
      'currentDevice': false,
    });
    expect(e.succeeded, isFalse);
    expect(e.resultLabel, 'Неверный код второго фактора');
    expect(e.methodLabel, 'код из приложения');
  });
}
