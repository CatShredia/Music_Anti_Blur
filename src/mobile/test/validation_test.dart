import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/validation/auth_rules.dart';

void main() {
  group('AuthRules.login', () {
    test('rejects empty fields', () {
      final codes = AuthRules.login(identifierType: 'login', identifier: '', password: '');
      expect(codes['identifier'], AuthRules.required);
      expect(codes['password'], AuthRules.required);
    });

    test('rejects short login', () {
      final codes = AuthRules.login(identifierType: 'login', identifier: 'ab', password: 'x');
      expect(codes['identifier'], AuthRules.loginFormat);
      expect(codes.containsKey('password'), isFalse);
    });

    test('accepts valid login without checking password strength', () {
      final codes = AuthRules.login(
        identifierType: 'login',
        identifier: 'user_1',
        password: 'short',
      );
      expect(codes, isEmpty);
    });
  });

  group('AuthRules.register', () {
    test('collects all field errors', () {
      final codes = AuthRules.register(login: 'ab', email: 'nope', password: '123');
      expect(codes['login'], AuthRules.loginFormat);
      expect(codes['email'], AuthRules.emailFormat);
      expect(codes['password'], AuthRules.passwordLength);
    });

    test('rejects common password', () {
      final codes = AuthRules.register(
        login: 'valid_user',
        email: 'user@example.com',
        password: 'password1234',
      );
      expect(codes['password'], AuthRules.passwordCommon);
    });

    test('accepts valid payload', () {
      final codes = AuthRules.register(
        login: 'valid_user',
        email: '  User@Example.COM ',
        password: 'unique-pass-phrase',
      );
      expect(codes, isEmpty);
    });
  });

  group('AuthRules.code', () {
    test('requires six digits', () {
      expect(AuthRules.codeCode('12a456'), AuthRules.codeFormat);
      expect(AuthRules.codeCode('123456'), isNull);
    });
  });
}
