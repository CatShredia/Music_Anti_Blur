import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/catalog/catalog_screens.dart';
import 'package:music_anti_blur/theme.dart';
import 'package:music_anti_blur/widgets.dart';

void main() {
  testWidgets('track action row lays out inside a list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VizeTheme.data(),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Choke'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    const CatalogCover(),
                    const Text('Artist'),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: VizePrimaryButton(label: 'Play', onPressed: () {}),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                            onPressed: () {},
                            icon: const Icon(Icons.favorite_border),
                            label: const Text('Нравится', overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('Нравится'), findsOneWidget);
  });
}
