import '../api/api_client.dart';
import 'catalog_models.dart';

/// Запись истории поиска (на сервере, до 50 штук).
class SearchHistoryItem {
  SearchHistoryItem({required this.id, required this.query});

  final String id;
  final String query;

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) =>
      SearchHistoryItem(id: json['id'] as String, query: json['query'] as String);
}

/// Страница жанра: альбомы и популярные треки.
class GenreDetail {
  GenreDetail({required this.id, required this.name, required this.albums, required this.popular});

  final String id;
  final String name;
  final List<AlbumListItem> albums;
  final List<PopularTrack> popular;

  factory GenreDetail.fromJson(Map<String, dynamic> json) => GenreDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        albums: (json['albums'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AlbumListItem.fromJson)
            .toList(),
        popular: PopularTrack.listFrom(json['popularTracks']),
      );
}

/// Ключ повтора запроса: без регистра и лишних пробелов (как на сервере).
String normalizeQuery(String query) =>
    query.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).join(' ').toLowerCase();

/// История после записи [query]: запись поднимается наверх без дубля, хранится не больше [max].
List<SearchHistoryItem> bumpHistory(List<SearchHistoryItem> items, SearchHistoryItem entry, {int max = 50}) {
  final key = normalizeQuery(entry.query);
  final rest = items.where((e) => normalizeQuery(e.query) != key);
  return [entry, ...rest].take(max).toList();
}

extension DiscoveryApi on ApiClient {
  Future<List<PopularTrack>> artistPopular(String artistId, {int limit = 10}) async {
    final res = await send((d) => d.get('/api/v1/artists/$artistId/popular', queryParameters: {'limit': limit}));
    return PopularTrack.listFrom((res.data as Map<String, dynamic>)['items']);
  }

  Future<GenreDetail> genre(String id) async {
    final res = await send((d) => d.get('/api/v1/genres/$id'));
    return GenreDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<SearchHistoryItem>> searchHistory({int limit = 50}) async {
    final res = await send((d) => d.get('/api/v1/me/search-history', queryParameters: {'limit': limit}));
    return [
      for (final row in res.data as List<dynamic>)
        if (row is Map<String, dynamic>) SearchHistoryItem.fromJson(row),
    ];
  }

  Future<SearchHistoryItem> addSearchHistory(String query) async {
    final res = await send((d) => d.post('/api/v1/me/search-history', data: {'query': query}));
    return SearchHistoryItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> removeSearchHistory(String id) => send((d) => d.delete('/api/v1/me/search-history/$id'));

  Future<void> clearSearchHistory() => send((d) => d.delete('/api/v1/me/search-history'));
}
