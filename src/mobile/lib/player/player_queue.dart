import 'package:uuid/uuid.dart';

class QueueItem {
  const QueueItem({
    required this.itemId,
    required this.trackId,
    this.sourcePreference = 'catalog',
  });

  final String itemId;
  final String trackId;
  final String sourcePreference;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'trackId': trackId,
        'sourcePreference': sourcePreference,
      };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
        itemId: json['itemId'] as String,
        trackId: json['trackId'] as String,
        sourcePreference: json['sourcePreference'] as String? ?? 'catalog',
      );
}

class PlayerQueue {
  const PlayerQueue({
    this.repeat = 'off',
    this.shuffle = false,
    this.currentItemId,
    this.items = const [],
  });

  static const empty = PlayerQueue();

  final String repeat;
  final bool shuffle;
  final String? currentItemId;
  final List<QueueItem> items;

  int get currentIndex => items.indexWhere((item) => item.itemId == currentItemId);

  QueueItem? get current {
    final index = currentIndex;
    return index < 0 ? null : items[index];
  }

  bool get isEmpty => items.isEmpty;

  static PlayerQueue single(String trackId, {String source = 'catalog', String? itemId}) {
    final id = itemId ?? const Uuid().v4();
    return PlayerQueue(
      currentItemId: id,
      items: [QueueItem(itemId: id, trackId: trackId, sourcePreference: source)],
    );
  }

  static PlayerQueue album(
    Iterable<String> trackIds, {
    String? startTrackId,
    String source = 'catalog',
    String Function()? newId,
  }) {
    final idOf = newId ?? const Uuid().v4;
    final items = [
      for (final trackId in trackIds)
        QueueItem(itemId: idOf(), trackId: trackId, sourcePreference: source),
    ];
    if (items.isEmpty) {
      return empty;
    }
    var start = items.first;
    if (startTrackId != null) {
      for (final item in items) {
        if (item.trackId == startTrackId) {
          start = item;
          break;
        }
      }
    }
    return PlayerQueue(currentItemId: start.itemId, items: items);
  }

  PlayerQueue copyWith({
    String? repeat,
    bool? shuffle,
    String? currentItemId,
    List<QueueItem>? items,
    bool clearCurrent = false,
  }) =>
      PlayerQueue(
        repeat: repeat ?? this.repeat,
        shuffle: shuffle ?? this.shuffle,
        currentItemId: clearCurrent ? null : (currentItemId ?? this.currentItemId),
        items: items ?? this.items,
      );

  PlayerQueue skipNext() {
    if (items.isEmpty) {
      return this;
    }
    final index = currentIndex;
    if (index < 0) {
      return copyWith(currentItemId: items.first.itemId);
    }
    if (index < items.length - 1) {
      return copyWith(currentItemId: items[index + 1].itemId);
    }
    if (repeat == 'all') {
      return copyWith(currentItemId: items.first.itemId);
    }
    return this;
  }

  PlayerQueue skipPrevious() {
    if (items.isEmpty) {
      return this;
    }
    final index = currentIndex;
    if (index < 0) {
      return copyWith(currentItemId: items.first.itemId);
    }
    if (index > 0) {
      return copyWith(currentItemId: items[index - 1].itemId);
    }
    if (repeat == 'all' && items.length > 1) {
      return copyWith(currentItemId: items.last.itemId);
    }
    return this;
  }

  /// `null` — остановиться (конец очереди, repeat off).
  PlayerQueue? afterCompleted() {
    if (items.isEmpty) {
      return null;
    }
    if (repeat == 'one') {
      return this;
    }
    if (repeat == 'off' && currentIndex >= items.length - 1) {
      return null;
    }
    return skipNext();
  }

  PlayerQueue cycleRepeat() => copyWith(
        repeat: switch (repeat) {
          'off' => 'all',
          'all' => 'one',
          _ => 'off',
        },
      );

  PlayerQueue withShuffle(bool enabled, {required List<QueueItem> Function(List<QueueItem>) shuffleItems}) {
    if (!enabled) {
      return copyWith(shuffle: false);
    }
    if (items.length <= 1) {
      return copyWith(shuffle: true);
    }
    final currentItem = current;
    final rest = items.where((item) => item.itemId != currentItemId).toList();
    final shuffled = shuffleItems(rest);
    return copyWith(
      shuffle: true,
      items: [?currentItem, ...shuffled],
      currentItemId: currentItem?.itemId,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'repeat': repeat,
        'shuffle': shuffle,
        'currentItemId': currentItemId,
        'items': [for (final item in items) item.toJson()],
      };

  factory PlayerQueue.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return PlayerQueue(
      repeat: json['repeat'] as String? ?? 'off',
      shuffle: json['shuffle'] as bool? ?? false,
      currentItemId: json['currentItemId'] as String?,
      items: [
        for (final item in rawItems)
          if (item is Map<String, dynamic>) QueueItem.fromJson(item),
      ],
    );
  }
}
