import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/validation/catalog_rules.dart';

void main() {
  group('CatalogRules.search', () {
    test('rejects empty and one character', () {
      expect(CatalogRules.search(''), {'q': CatalogRules.required});
      expect(CatalogRules.search(' '), {'q': CatalogRules.required});
      expect(CatalogRules.search('n'), {'q': CatalogRules.searchQuery});
    });

    test('rejects over 100 characters', () {
      expect(CatalogRules.search('n' * 101), {'q': CatalogRules.searchQuery});
    });

    test('accepts two characters after trim', () {
      expect(CatalogRules.search('  ne  '), isEmpty);
    });
  });
}
