/// Разбор ссылок на трек, альбом и плейлист.
///
/// Поддерживаются:
/// - `musicantiblur://app/{type}/{id}` (основная схема приложения, путь доходит до `go_router`);
/// - `musicantiblur://{type}/{id}`;
/// - `https://{host}/s/{type}/{id}` (страница превью API);
/// - путь без схемы: `/{type}/{id}` и `/s/{type}/{id}`.
const shareTypes = {'track', 'album', 'playlist'};

final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Маршрут приложения (`/playlist/{id}`) или `null`, если ссылка не наша.
String? routeForLink(Uri uri) {
  final segments = [...uri.pathSegments.where((s) => s.isNotEmpty)];
  final isApp = uri.scheme == 'musicantiblur';
  if (isApp && uri.host.isNotEmpty && uri.host != 'app') {
    segments.insert(0, uri.host);
  }
  if (segments.isNotEmpty && segments.first == 's') {
    segments.removeAt(0);
  }
  if (segments.length != 2) {
    return null;
  }
  final type = segments[0];
  final id = segments[1];
  if (!shareTypes.contains(type) || !_uuid.hasMatch(id)) {
    return null;
  }
  return '/$type/${id.toLowerCase()}';
}

/// Ссылка (текст из буфера, поле ввода) → маршрут. Нечитаемое → `null`.
String? routeForText(String text) {
  final uri = Uri.tryParse(text.trim());
  return uri == null ? null : routeForLink(uri);
}

/// Почему ссылка не подошла (текст для пользователя) или `null`, если она корректна.
String? describeLinkProblem(String text) {
  final value = text.trim();
  if (value.isEmpty) {
    return 'Вставьте ссылку';
  }
  final uri = Uri.tryParse(value);
  if (uri == null || (!uri.hasScheme && !value.startsWith('/'))) {
    return 'Это не ссылка. Пример: https://…/s/playlist/…';
  }
  if (routeForLink(uri) != null) {
    return null;
  }
  final segments = [...uri.pathSegments.where((s) => s.isNotEmpty)];
  if (uri.scheme == 'musicantiblur' && uri.host.isNotEmpty && uri.host != 'app') {
    segments.insert(0, uri.host);
  }
  if (segments.isNotEmpty && segments.first == 's') {
    segments.removeAt(0);
  }
  if (segments.length == 2 && shareTypes.contains(segments[0])) {
    return 'В ссылке неверный идентификатор';
  }
  if (segments.isNotEmpty && shareTypes.contains(segments[0])) {
    return 'Ссылка неполная: не хватает идентификатора';
  }
  return 'Ссылка должна вести на трек, альбом или плейлист';
}

/// Нужен ли вход для маршрута: ссылки на контент открываются только авторизованным.
bool isContentRoute(String path) =>
    path.startsWith('/track/') || path.startsWith('/album/') || path.startsWith('/playlist/') || path.startsWith('/s/');

/// Ссылка, открытая до входа: запоминается и открывается после авторизации.
class PendingLink {
  PendingLink._();

  static String? _value;

  static void set(String route) => _value = route;

  /// Возвращает отложенный маршрут один раз, затем очищает.
  static String? take() {
    final value = _value;
    _value = null;
    return value;
  }
}
