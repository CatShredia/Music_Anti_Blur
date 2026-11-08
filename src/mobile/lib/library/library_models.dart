/// Плитка библиотеки: плейлист (свой, «Мне нравится», сохранённый чужой) или альбом.
class LibraryItem {
  LibraryItem({
    required this.type,
    required this.id,
    required this.title,
    required this.kind,
    required this.isOwn,
    required this.trackCount,
    required this.coverUrls,
    this.subtitle,
    this.ownerName,
  });

  final String type;
  final String id;
  final String title;
  final String? subtitle;
  final String kind;
  final bool isOwn;
  final String? ownerName;
  final int trackCount;
  final List<String> coverUrls;

  bool get isAlbum => type == 'album';
  bool get isLiked => kind == 'liked';
  bool get isSaved => kind == 'saved';

  /// Маршрут экрана, который открывает плитка.
  String get route => isAlbum ? '/album/$id' : (isLiked ? '/liked' : '/playlist/$id');

  /// Вторая строка плитки.
  String get caption {
    if (isAlbum) {
      return subtitle ?? 'Альбом';
    }
    if (isLiked) {
      return 'Лайкнутые треки · $trackCount';
    }
    final owner = ownerName;
    return isSaved && owner != null ? 'Плейлист · $owner · $trackCount' : 'Плейлист · $trackCount';
  }

  factory LibraryItem.fromJson(Map<String, dynamic> json) => LibraryItem(
        type: json['type'] as String,
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        kind: json['kind'] as String,
        isOwn: json['isOwn'] as bool? ?? false,
        ownerName: json['ownerName'] as String?,
        trackCount: json['trackCount'] as int? ?? 0,
        coverUrls: (json['coverUrls'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      );
}

class LibraryPage {
  LibraryPage({required this.items, this.nextCursor});

  final List<LibraryItem> items;
  final String? nextCursor;

  factory LibraryPage.fromJson(Map<String, dynamic> json) => LibraryPage(
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LibraryItem.fromJson)
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

/// Ответ добавления треков в плейлист.
class AddedTracks {
  AddedTracks({required this.added, required this.trackCount});

  final int added;
  final int trackCount;

  factory AddedTracks.fromJson(Map<String, dynamic> json) => AddedTracks(
        added: json['added'] as int? ?? 0,
        trackCount: json['trackCount'] as int? ?? 0,
      );
}

/// Какие обложки брать для коллажа плейлиста: до [max] уникальных непустых адресов.
List<String> collageUrls(Iterable<String?> urls, {int max = 4}) {
  final seen = <String>{};
  final out = <String>[];
  for (final url in urls) {
    if (url == null || url.isEmpty || !seen.add(url)) {
      continue;
    }
    out.add(url);
    if (out.length == max) {
      break;
    }
  }
  return out;
}

/// Новый порядок после перетаскивания (семантика `onReorderItem`: [newIndex] уже
/// учитывает удаление элемента с [oldIndex]).
List<T> reorderList<T>(List<T> items, int oldIndex, int newIndex) {
  final list = [...items];
  final moved = list.removeAt(oldIndex);
  list.insert(newIndex, moved);
  return list;
}
