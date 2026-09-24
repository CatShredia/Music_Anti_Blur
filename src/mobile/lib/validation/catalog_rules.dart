import 'auth_rules.dart';

/// Правила поиска и полей каталога совпадают с API (`CatalogValidation`).
class CatalogRules {
  static const queryMin = 2;
  static const queryMax = 100;

  static const required = AuthRules.required;
  static const searchQuery = 'search_query';
  static const yearRange = 'year_range';
  static const trackNumber = 'track_number';
  static const duration = 'duration';
  static const nameLength = 'name_length';
  static const titleLength = 'title_length';
  static const coverKey = 'cover_object_key';
  static const coverType = 'cover_type';
  static const fileTooLarge = 'file_too_large';
  static const isrcFormat = 'isrc_format';
  static const limitRange = 'limit_range';

  static String? queryCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return required;
    }
    if (trimmed.length < queryMin || trimmed.length > queryMax) {
      return searchQuery;
    }
    return null;
  }

  static Map<String, String> search(String q) {
    final code = queryCode(q);
    return code == null ? const {} : {'q': code};
  }
}
