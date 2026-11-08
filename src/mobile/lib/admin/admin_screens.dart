import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../catalog/catalog_models.dart';
import 'admin_api.dart';
import 'admin_models.dart';
import 'folder_parser.dart';
import 'folder_picker.dart';
import 'import_runner.dart';
import 'source_uploader.dart';

/// Пускает внутрь только роль `admin`: без сессии отправляет на вход, обычному пользователю показывает 403.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key, required this.api, required this.child});

  final ApiClient api;
  final Widget child;

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  late final Future<UserDto?> _me = _load();

  Future<UserDto?> _load() async {
    if (!await widget.api.hasSession()) {
      return null;
    }
    try {
      return await widget.api.me();
    } on ApiException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserDto?>(
      future: _me,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go('/login');
            }
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        if (!isAdminRole(user.role)) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('403 · нужна роль admin', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await widget.api.logout();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    child: const Text('Выйти'),
                  ),
                ],
              ),
            ),
          );
        }
        return widget.child;
      },
    );
  }
}

bool isAdminRole(String role) => role == 'admin';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.api, required this.location, required this.child});

  final ApiClient api;
  final String location;
  final Widget child;

  int get _index {
    if (location.startsWith('/admin/trash')) return 1;
    if (location.startsWith('/admin/import')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => context.go(['/admin', '/admin/trash', '/admin/import'][i]),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.library_music), label: Text('Каталог')),
              NavigationRailDestination(icon: Icon(Icons.delete_outline), label: Text('Корзина')),
              NavigationRailDestination(icon: Icon(Icons.drive_folder_upload), label: Text('Импорт')),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    tooltip: 'Выйти',
                    icon: const Icon(Icons.logout),
                    onPressed: () async {
                      await api.logout();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- helpers

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> _guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) {
      _toast(context, describeError(e));
    }
    return false;
  }
}

Future<bool> _confirm(BuildContext context, String text) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да')),
      ],
    ),
  );
  return ok ?? false;
}

Future<Map<String, String>?> _form(
  BuildContext context, {
  required String title,
  required Map<String, String> fields,
}) {
  final controllers = {for (final e in fields.entries) e.key: TextEditingController(text: e.value)};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in controllers.entries)
              TextField(controller: e.value, decoration: InputDecoration(labelText: e.key)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, {for (final e in controllers.entries) e.key: e.value.text.trim()}),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

Color _statusColor(String status) => switch (status) {
      'ready' => Colors.green,
      'failed' => Colors.red,
      'processing' || 'pending' => Colors.orange,
      _ => Colors.grey,
    };

String statusLabel(String status) => switch (status) {
      'ready' => 'Ready',
      'failed' => 'Failed',
      'processing' || 'pending' => 'В работе',
      _ => 'Нет файла',
    };

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(statusLabel(status)),
        side: BorderSide(color: _statusColor(status)),
        visualDensity: VisualDensity.compact,
      );
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child, this.actions = const []});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
            ],
            const SizedBox(height: 16),
            Expanded(child: child),
          ],
        ),
      );
}

Future<void> pickAndUploadSource(BuildContext context, ApiClient api, String trackId) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: audioExtensions.toList(),
    withData: true,
  );
  final file = picked?.files.firstOrNull;
  if (file == null || file.bytes == null || !context.mounted) {
    return;
  }
  if (file.size > SourceUploader.maxBytes) {
    _toast(context, 'Файл больше 100 МБ');
    return;
  }
  final stage = ValueNotifier<(String, double)>(('старт', 0));
  var cancelled = false;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(file.name),
        content: ValueListenableBuilder<(String, double)>(
          valueListenable: stage,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text(v.$1), const SizedBox(height: 8), LinearProgressIndicator(value: v.$2)],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => cancelled = true,
            child: const Text('Отменить'),
          ),
        ],
      ),
    ),
  );
  String result;
  try {
    final status = await SourceUploader(api).upload(
      trackId: trackId,
      fileName: file.name,
      bytes: file.bytes!,
      isCancelled: () => cancelled,
      onProgress: (s, p) => stage.value = (s, p),
    );
    result = status.isReady ? 'Готово' : 'Ошибка: ${status.errorMessage ?? status.status}';
  } on UploadCancelled {
    result = 'Отменено';
  } catch (e) {
    result = describeError(e);
  }
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
    _toast(context, result);
  }
}

// ---------------------------------------------------------------- artists

class AdminArtistsScreen extends StatefulWidget {
  const AdminArtistsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<AdminArtistsScreen> createState() => _AdminArtistsScreenState();
}

class _AdminArtistsScreenState extends State<AdminArtistsScreen> {
  final _items = <ArtistListItem>[];
  String? _cursor;
  bool _loading = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _items.clear();
    _cursor = null;
    _loaded = false;
    await _more();
  }

  Future<void> _more() async {
    if (_loading) return;
    setState(() => _loading = true);
    await _guard(context, () async {
      final page = await widget.api.listArtists(cursor: _cursor, limit: 50);
      _items.addAll(page.items);
      _cursor = page.nextCursor;
    });
    if (mounted) {
      setState(() {
        _loading = false;
        _loaded = true;
      });
    }
  }

  Future<void> _create() async {
    final v = await _form(context, title: 'Новый исполнитель', fields: {'Имя': ''});
    if (v == null || v['Имя']!.isEmpty || !mounted) return;
    if (await _guard(context, () => widget.api.adminCreateArtist(v['Имя']!))) {
      await _reload();
    }
  }

  Future<void> _rename(ArtistListItem a) async {
    final v = await _form(context, title: 'Исполнитель', fields: {'Имя': a.name});
    if (v == null || v['Имя']!.isEmpty || !mounted) return;
    if (await _guard(context, () => widget.api.adminUpdateArtist(a.id, v['Имя']!))) {
      await _reload();
    }
  }

  Future<void> _delete(ArtistListItem a) async {
    if (!await _confirm(context, 'Удалить исполнителя «${a.name}»?') || !mounted) return;
    if (await _guard(context, () => widget.api.adminDeleteArtist(a.id))) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Исполнители',
      actions: [FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Исполнитель'))],
      child: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final a in _items)
                  ListTile(
                    title: Text(a.name),
                    onTap: () => context.go('/admin/artist/${a.id}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => _rename(a)),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(a)),
                      ],
                    ),
                  ),
                if (_cursor != null)
                  TextButton(onPressed: _more, child: const Text('Загрузить ещё')),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- albums of an artist

class AdminArtistScreen extends StatefulWidget {
  const AdminArtistScreen({super.key, required this.api, required this.id});

  final ApiClient api;
  final String id;

  @override
  State<AdminArtistScreen> createState() => _AdminArtistScreenState();
}

class _AdminArtistScreenState extends State<AdminArtistScreen> {
  ArtistDetail? _artist;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _guard(context, () async => _artist = await widget.api.artist(widget.id));
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final v = await _form(context, title: 'Новый альбом', fields: {'Название': '', 'Год': ''});
    if (v == null || v['Название']!.isEmpty || !mounted) return;
    var id = '';
    if (await _guard(context, () async {
      id = await widget.api.adminCreateAlbum(
        artistId: widget.id,
        title: v['Название']!,
        year: int.tryParse(v['Год']!),
      );
    }) && mounted) {
      context.go('/admin/album/$id');
    }
  }

  Future<void> _delete(ArtistAlbumItem a) async {
    if (!await _confirm(context, 'Удалить альбом «${a.title}»?') || !mounted) return;
    if (await _guard(context, () => widget.api.adminDeleteAlbum(a.id))) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final artist = _artist;
    return _Page(
      title: artist?.name ?? 'Исполнитель',
      actions: [
        TextButton(onPressed: () => context.go('/admin'), child: const Text('← Исполнители')),
        FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Альбом')),
      ],
      child: artist == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final a in artist.albums)
                  ListTile(
                    leading: a.coverUrl == null
                        ? const Icon(Icons.album)
                        : Image.network(a.coverUrl!, width: 48, height: 48, fit: BoxFit.cover),
                    title: Text(a.title),
                    subtitle: Text('${a.year ?? ''}'),
                    onTap: () => context.go('/admin/album/${a.id}'),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(a)),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- album: tracks and statuses

class AdminAlbumScreen extends StatefulWidget {
  const AdminAlbumScreen({super.key, required this.api, required this.id});

  final ApiClient api;
  final String id;

  @override
  State<AdminAlbumScreen> createState() => _AdminAlbumScreenState();
}

class _AdminAlbumScreenState extends State<AdminAlbumScreen> {
  AlbumDetail? _album;
  List<AdminTrackRow>? _tracks;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await _guard(context, () async {
      _album = await widget.api.album(widget.id);
      _tracks = await widget.api.adminAlbumTracks(widget.id);
    });
    if (!mounted) return;
    setState(() {});
    _poll?.cancel();
    if (_tracks?.any((t) => t.status == 'processing') ?? false) {
      _poll = Timer(const Duration(seconds: 3), _refreshTracks);
    }
  }

  Future<void> _refreshTracks() async {
    try {
      _tracks = await widget.api.adminAlbumTracks(widget.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    _poll?.cancel();
    if (_tracks?.any((t) => t.status == 'processing') ?? false) {
      _poll = Timer(const Duration(seconds: 3), _refreshTracks);
    }
  }

  Future<void> _editAlbum() async {
    final album = _album!;
    final v = await _form(
      context,
      title: 'Альбом',
      fields: {'Название': album.title, 'Год': '${album.year ?? ''}'},
    );
    if (v == null || v['Название']!.isEmpty || !mounted) return;
    if (await _guard(context, () => widget.api.adminUpdateAlbum(
          id: album.id,
          artistId: album.artist.id,
          title: v['Название']!,
          year: int.tryParse(v['Год']!),
          coverObjectKey: album.coverObjectKey,
        ))) {
      await _load();
    }
  }

  Future<void> _cover() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    if (file!.size > 5 * 1024 * 1024) {
      _toast(context, 'Обложка больше 5 МБ');
      return;
    }
    if (await _guard(context, () => widget.api.adminUploadCover(
          albumId: widget.id,
          bytes: file.bytes!,
          fileName: file.name,
          contentType: extensionOf(file.name) == 'png' ? 'image/png' : 'image/jpeg',
        ))) {
      await _load();
    }
  }

  Future<void> _addTrack() async {
    final album = _album!;
    final next = (_tracks?.map((t) => t.trackNumber).fold<int>(0, (a, b) => a > b ? a : b) ?? 0) + 1;
    final v = await _form(context, title: 'Новый трек', fields: {'Название': '', 'Номер': '$next', 'ISRC': ''});
    if (v == null || v['Название']!.isEmpty || !mounted) return;
    if (await _guard(context, () => widget.api.adminCreateTrack(
          albumId: album.id,
          artistId: album.artist.id,
          title: v['Название']!,
          trackNumber: int.tryParse(v['Номер']!) ?? next,
          isrc: v['ISRC']!.isEmpty ? null : v['ISRC'],
        ))) {
      await _load();
    }
  }

  Future<void> _editTrack(AdminTrackRow t) async {
    final album = _album!;
    final v = await _form(
      context,
      title: 'Трек',
      fields: {'Название': t.title, 'Номер': '${t.trackNumber}', 'ISRC': t.isrc ?? ''},
    );
    if (v == null || v['Название']!.isEmpty || !mounted) return;
    if (await _guard(context, () => widget.api.adminUpdateTrack(
          id: t.id,
          albumId: album.id,
          artistId: album.artist.id,
          title: v['Название']!,
          trackNumber: int.tryParse(v['Номер']!) ?? t.trackNumber,
          durationMs: t.durationMs,
          isrc: v['ISRC']!.isEmpty ? null : v['ISRC'],
        ))) {
      await _load();
    }
  }

  Future<void> _deleteTrack(AdminTrackRow t) async {
    if (!await _confirm(context, 'Переместить «${t.title}» в корзину? Хранится 6 месяцев.') || !mounted) return;
    if (await _guard(context, () => widget.api.adminDeleteTrack(t.id))) {
      await _load();
    }
  }

  Future<void> _upload(AdminTrackRow t) async {
    await pickAndUploadSource(context, widget.api, t.id);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final album = _album;
    final tracks = _tracks;
    return _Page(
      title: album?.title ?? 'Альбом',
      actions: [
        if (album != null)
          TextButton(onPressed: () => context.go('/admin/artist/${album.artist.id}'), child: Text('← ${album.artist.name}')),
        if (album != null) IconButton(tooltip: 'Изменить', icon: const Icon(Icons.edit), onPressed: _editAlbum),
        if (album != null) OutlinedButton(onPressed: _cover, child: const Text('Обложка')),
        const SizedBox(width: 8),
        if (album != null) FilledButton.icon(onPressed: _addTrack, icon: const Icon(Icons.add), label: const Text('Трек')),
      ],
      child: album == null || tracks == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (album.coverUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Image.network(album.coverUrl!, width: 160, height: 160, fit: BoxFit.cover),
                  ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final t in tracks)
                        ListTile(
                          leading: Text('${t.trackNumber}'),
                          title: Text(t.title),
                          subtitle: t.totalRenditions == 0 ? null : Text('${t.readyRenditions}/${t.totalRenditions} качеств'),
                          onTap: () => context.go('/admin/track/${t.id}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StatusBadge(t.status),
                              IconButton(tooltip: 'Загрузить файл', icon: const Icon(Icons.upload_file), onPressed: () => _upload(t)),
                              IconButton(icon: const Icon(Icons.edit), onPressed: () => _editTrack(t)),
                              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteTrack(t)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- track: renditions

class AdminTrackScreen extends StatefulWidget {
  const AdminTrackScreen({super.key, required this.api, required this.id});

  final ApiClient api;
  final String id;

  @override
  State<AdminTrackScreen> createState() => _AdminTrackScreenState();
}

class _AdminTrackScreenState extends State<AdminTrackScreen> {
  TrackDetail? _track;
  List<AdminRendition>? _renditions;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    try {
      if (first) _track = await widget.api.track(widget.id);
      _renditions = await widget.api.adminRenditions(widget.id);
    } catch (e) {
      if (mounted && first) _toast(context, describeError(e));
    }
    if (!mounted) return;
    setState(() {});
    _poll?.cancel();
    if (_renditions?.any((r) => r.isBusy) ?? false) {
      _poll = Timer(const Duration(seconds: 3), _load);
    }
  }

  Future<void> _retry({String? generationId}) async {
    if (await _guard(context, () => widget.api.adminRetranscode(widget.id, generationId: generationId))) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    final rows = _renditions;
    final hasFailed = rows?.any((r) => r.isFailed) ?? false;
    return _Page(
      title: track?.title ?? 'Трек',
      actions: [
        if (track != null)
          TextButton(onPressed: () => context.go('/admin/album/${track.album.id}'), child: Text('← ${track.album.title}')),
        OutlinedButton.icon(
          onPressed: () async {
            await pickAndUploadSource(context, widget.api, widget.id);
            if (mounted) await _load();
          },
          icon: const Icon(Icons.upload_file),
          label: const Text('Новый файл'),
        ),
        const SizedBox(width: 8),
        if (hasFailed)
          FilledButton.icon(onPressed: () => _retry(), icon: const Icon(Icons.refresh), label: const Text('Перекодировать')),
      ],
      child: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? const Text('Рендиций нет: загрузите исходный файл.')
              : SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Качество')),
                      DataColumn(label: Text('Статус')),
                      DataColumn(label: Text('Битрейт')),
                      DataColumn(label: Text('Активна')),
                      DataColumn(label: Text('Ошибка')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final r in rows)
                        DataRow(cells: [
                          DataCell(Text(r.code)),
                          DataCell(StatusBadge(r.status)),
                          DataCell(Text(r.bitrateKbps == null ? '—' : '${r.bitrateKbps} кбит/с')),
                          DataCell(Icon(r.isActive ? Icons.check : Icons.remove, size: 18)),
                          DataCell(Text(r.errorMessage ?? '')),
                          DataCell(
                            r.isFailed
                                ? TextButton(onPressed: () => _retry(generationId: r.generationId), child: const Text('Повторить'))
                                : const SizedBox.shrink(),
                          ),
                        ]),
                    ],
                  ),
                ),
    );
  }
}

// ---------------------------------------------------------------- trash

class AdminTrashScreen extends StatefulWidget {
  const AdminTrashScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<AdminTrashScreen> createState() => _AdminTrashScreenState();
}

class _AdminTrashScreenState extends State<AdminTrashScreen> {
  List<DeletedTrack>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _guard(context, () async => _items = await widget.api.adminDeletedTracks());
    if (mounted) setState(() {});
  }

  Future<void> _restore(DeletedTrack t) async {
    if (await _guard(context, () => widget.api.adminRestoreTrack(t.id)) && mounted) {
      _toast(context, 'Трек восстановлен');
      await _load();
    }
  }

  String _date(DateTime d) => '${d.toLocal()}'.split(' ').first;

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return _Page(
      title: 'Корзина',
      child: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Text('Пусто')
              : ListView(
                  children: [
                    for (final t in items)
                      ListTile(
                        title: Text(t.title),
                        subtitle: Text('${t.artistName} · ${t.albumTitle} · удалён ${_date(t.deletedAt)}, будет стёрт ${_date(t.purgeAt)}'),
                        trailing: FilledButton(onPressed: () => _restore(t), child: const Text('Восстановить')),
                      ),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------- bulk import

class AdminImportScreen extends StatefulWidget {
  const AdminImportScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<AdminImportScreen> createState() => _AdminImportScreenState();
}

class _AdminImportScreenState extends State<AdminImportScreen> {
  late final ImportRunner _runner = ImportRunner(widget.api);
  List<ParsedAlbum> _albums = [];
  List<ImportItem> _items = [];
  bool _running = false;

  Future<void> _pick() async {
    List<PickedFile> files;
    if (folderPickSupported) {
      files = await pickFolder();
    } else {
      final picked = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
      files = [
        for (final f in picked?.files ?? const <PlatformFile>[])
          PickedFile(path: f.name, size: f.size, read: () async => f.bytes!),
      ];
    }
    if (files.isEmpty || !mounted) return;
    final albums = parseAlbums(files);
    setState(() {
      _albums = albums;
      _items = _runner.plan(albums);
    });
    if (albums.isEmpty) _toast(context, 'Аудиофайлов не найдено');
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _items = _runner.plan(_albums);
    });
    await _runner.run(_items, () {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _running = false);
  }

  Future<void> _retryFailed() async {
    setState(() => _running = true);
    await _runner.run(_items, () {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final started = _items.any((i) => i.state != ImportState.waiting);
    final failed = _items.where((i) => i.state == ImportState.failed).length;
    final done = _items.where((i) => i.state == ImportState.done).length;
    return _Page(
      title: 'Импорт альбомов',
      actions: [
        OutlinedButton.icon(
          onPressed: _running ? null : _pick,
          icon: const Icon(Icons.folder_open),
          label: Text(folderPickSupported ? 'Выбрать папку' : 'Выбрать файлы'),
        ),
        const SizedBox(width: 8),
        if (_albums.isNotEmpty && !started)
          FilledButton(onPressed: _running ? null : _start, child: const Text('Запустить')),
        if (failed > 0 && !_running)
          FilledButton(onPressed: _retryFailed, child: Text('Повторить неудачные ($failed)')),
        if (_running) TextButton(onPressed: () => _runner.cancelled = true, child: const Text('Остановить')),
      ],
      child: _albums.isEmpty
          ? const Text(
              'Выберите папку: «Исполнитель/Альбом/01 - Трек.mp3», обложка cover.jpg рядом. '
              'Названия берутся из имён файлов, теги не читаются.',
            )
          : ListView(
              children: [
                if (started) Text('Готово: $done из ${_items.length}, ошибок: $failed'),
                for (final album in _albums) _albumCard(album),
              ],
            ),
    );
  }

  Widget _albumCard(ParsedAlbum album) {
    final items = _items.where((i) => i.album == album).toList();
    final editable = !_running && !_items.any((i) => i.state != ImportState.waiting);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: album.artist ?? '',
                    enabled: editable,
                    decoration: const InputDecoration(labelText: 'Исполнитель'),
                    onChanged: (v) => album.artist = v.trim().isEmpty ? null : v.trim(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: album.title,
                    enabled: editable,
                    decoration: const InputDecoration(labelText: 'Альбом'),
                    onChanged: (v) => album.title = v.trim(),
                  ),
                ),
                if (album.cover != null) const Padding(padding: EdgeInsets.only(left: 12), child: Icon(Icons.image)),
              ],
            ),
            for (final item in items)
              ListTile(
                dense: true,
                leading: Text('${item.track.number}'),
                title: Text(item.track.title),
                subtitle: item.error == null ? null : Text(item.error!, style: const TextStyle(color: Colors.red)),
                trailing: SizedBox(
                  width: 160,
                  child: item.state == ImportState.uploading
                      ? LinearProgressIndicator(value: item.progress)
                      : Text(_importLabel(item.state), textAlign: TextAlign.end),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _importLabel(ImportState s) => switch (s) {
        ImportState.waiting => 'ожидает',
        ImportState.creating => 'создаю',
        ImportState.uploading => 'загрузка',
        ImportState.processing => 'обработка',
        ImportState.done => 'готово',
        ImportState.failed => 'ошибка',
      };
}
