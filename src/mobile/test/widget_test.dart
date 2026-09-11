import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/api/api_client.dart';
import 'package:music_anti_blur/main.dart';

void main() {
  testWidgets('login screen renders', (tester) async {
    await tester.pumpWidget(MusicAntiBlurApp(api: ApiClient()));
    expect(find.widgetWithText(AppBar, 'Sign in'), findsOneWidget);
  });
}
