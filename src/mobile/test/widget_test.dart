import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/api/api_client.dart';
import 'package:music_anti_blur/main.dart';

void main() {
  testWidgets('login screen renders', (tester) async {
    await tester.pumpWidget(MusicAntiBlurApp(api: ApiClient()));
    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Vize'), findsOneWidget);
  });

  testWidgets('login screen validates empty fields', (tester) async {
    await tester.pumpWidget(MusicAntiBlurApp(api: ApiClient()));
    await tester.tap(find.text('Войти'));
    await tester.pump();
    expect(find.text('Обязательное поле'), findsWidgets);
  });
}
