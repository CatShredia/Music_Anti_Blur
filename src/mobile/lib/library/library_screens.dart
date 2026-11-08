import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../catalog/catalog_models.dart';
import '../player/player_controller.dart';
import '../player/player_nav.dart';
import '../theme.dart';
import '../widgets.dart';
import 'deep_link.dart';
import 'library_api.dart';
import 'library_models.dart';

String _errorText(Object e) => e is ApiException ? e.localizedMessage : '$e';

// ---------------------------------------------------------------------------
// Коллаж обложек
// ---------------------------------------------------------------------------

/// Обложка плейлиста: до 4 обложек сеткой 2×2, при одной обложке — она целиком, иначе значок.
class PlaylistCollage extends StatelessWidget {
  const PlaylistCollage({
    super.key,
    required this.urls,
    this.size = 56,
    this.radius = 12,
    this.icon = Icons.queue_music,
  });

  final List<String> urls;
  final double size;
  final double radius;
  final IconData icon;

  Widget _image(String url) => Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );

  Widget _placeholder() => Container(
        color: VizeColors.surface,
        alignment: Alignment.center,
        child: Icon(icon, color: VizeColors.accentMuted, size: size * 0.42),
      );

  @override
  Widget build(BuildContext context) {
    final shown = collageUrls(urls);
    final Widget content;
    if (shown.isEmpty) {
      content = _placeholder();
    } else if (shown.length == 1) {
      content = _image(shown.first);
    } else {
      content = GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [for (var i = 0; i < 4; i++) _image(shown[i % shown.length])],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: content),
    );
  }
}

// ---------------------------------------------------------------------------
// Диалог создания и правки плейлиста
// ---------------------------------------------------------------------------

const playlistTitleMax = 200;
const playlistDescriptionMax = 500;

/// Проверка полей плейлиста: код ошибки или `null`.
String? validatePlaylistTitle(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return 'Введите название';
  }
  if (value.length > playlistTitleMax) {
    return 'Не больше $playlistTitleMax символов';
  }
  return null;
}

String? validatePlaylistDescription(String raw) =>
    raw.trim().length > playlistDescriptionMax ? 'Не больше $playlistDescriptionMax символов' : null;

/// Создаёт плейлист (или правит, если передан [edit]) и возвращает результат.
Future<PlaylistListItem?> showPlaylistDialog(BuildContext context, ApiClient api, {PlaylistDetail? edit}) {
  return showDialog<PlaylistListItem>(
    context: context,
    builder: (_) => _PlaylistDialog(api: api, edit: edit),
  );
}

class _PlaylistDialog extends StatefulWidget {
  const _PlaylistDialog({required this.api, this.edit});

  final ApiClient api;
  final PlaylistDetail? edit;

  @override
  State<_PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends State<_PlaylistDialog> {
  late final _title = TextEditingController(text: widget.edit?.title ?? '');
  late final _description = TextEditingController(text: widget.edit?.description ?? '');
  late bool _public = widget.edit?.isPublic ?? false;
  String? _titleError;
  String? _descriptionError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final titleError = validatePlaylistTitle(_title.text);
    final descriptionError = validatePlaylistDescription(_description.text);
    setState(() {
      _titleError = titleError;
      _descriptionError = descriptionError;
      _error = null;
    });
    if (titleError != null || descriptionError != null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final edit = widget.edit;
      final result = edit == null
          ? await widget.api.createPlaylist(
              title: _title.text.trim(),
              description: _description.text.trim(),
              isPublic: _public,
            )
          : await widget.api.updatePlaylist(
              edit.id,
              title: _title.text.trim(),
              description: _description.text.trim(),
              isPublic: _public,
            );
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _errorText(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.edit == null ? 'Новый плейлист' : 'Изменить плейлист'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: playlistTitleMax,
              decoration: InputDecoration(labelText: 'Название', errorText: _titleError, counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              minLines: 1,
              maxLength: playlistDescriptionMax,
              decoration: InputDecoration(labelText: 'Описание', errorText: _descriptionError, counterText: ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Публичный'),
              subtitle: const Text('Доступен по ссылке другим пользователям'),
              value: _public,
              onChanged: _busy ? null : (v) => setState(() => _public = v),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: VizeColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _busy ? null : _submit,
          child: Text(widget.edit == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// «Добавить в плейлист»
// ---------------------------------------------------------------------------

String? _lastPlaylistId;

/// Порядок в списке выбора: последний использованный плейлист первым.
List<PlaylistListItem> orderForPicker(List<PlaylistListItem> all, String? lastId) {
  final own = all.where((p) => !p.isLiked).toList();
  final last = own.where((p) => p.id == lastId).toList();
  return [...last, ...own.where((p) => p.id != lastId)];
}

Future<void> showAddToPlaylistSheet(BuildContext context, ApiClient api, List<String> trackIds) async {
  if (trackIds.isEmpty) {
    showVizeMessage(context, 'Нет треков для добавления');
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final result = await showModalBottomSheet<AddedTracks?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: VizeColors.bgElevated,
    builder: (_) => _AddToPlaylistSheet(api: api, trackIds: trackIds),
  );
  if (result != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(result.added == 0 ? 'Уже в плейлисте' : 'Добавлено: ${result.added}')),
    );
  }
}

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({required this.api, required this.trackIds});

  final ApiClient api;
  final List<String> trackIds;

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  List<PlaylistListItem>? _playlists;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.api.listPlaylists();
      if (mounted) {
        setState(() => _playlists = orderForPicker(all, _lastPlaylistId));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _errorText(e));
      }
    }
  }

  Future<void> _add(String playlistId) async {
    setState(() => _busy = true);
    try {
      final result = await widget.api.addTracksToPlaylist(playlistId, widget.trackIds);
      _lastPlaylistId = playlistId;
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _errorText(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final created = await showPlaylistDialog(context, widget.api);
    if (created != null && mounted) {
      await _add(created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlists;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('В плейлист', style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add, color: VizeColors.accent),
              title: const Text('Новый плейлист'),
              onTap: _busy ? null : _create,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(_error!, style: const TextStyle(color: VizeColors.danger)),
              ),
            if (playlists == null && _error == null)
              const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
            else if (playlists != null)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in playlists)
                      ListTile(
                        leading: const Icon(Icons.queue_music, color: VizeColors.accentMuted),
                        title: Text(p.title),
                        subtitle: Text(p.id == _lastPlaylistId ? 'Последний · ${p.trackCount}' : '${p.trackCount} треков'),
                        onTap: _busy ? null : () => _add(p.id),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Библиотека
// ---------------------------------------------------------------------------

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

/// Ввод ссылки. Контроллер живёт в состоянии диалога: освобождать его снаружи нельзя,
/// пока идёт анимация закрытия.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Открыть по ссылке'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'https://…/s/playlist/…'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Открыть'),
        ),
      ],
    );
  }
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _filters = {'all': 'Всё', 'playlists': 'Плейлисты', 'albums': 'Альбомы'};

  String _filter = 'all';
  List<LibraryItem> _items = const [];
  String? _next;
  String? _error;
  bool _loading = true;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.library(type: _filter);
      if (mounted) {
        setState(() {
          _items = page.items;
          _next = page.nextCursor;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _errorText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _more) {
      return;
    }
    setState(() => _more = true);
    try {
      final page = await widget.api.library(type: _filter, cursor: cursor);
      if (mounted) {
        setState(() {
          _items = [..._items, ...page.items];
          _next = page.nextCursor;
        });
      }
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _more = false);
      }
    }
  }

  Future<void> _create() async {
    final created = await showPlaylistDialog(context, widget.api);
    if (created != null && mounted) {
      await context.push('/playlist/${created.id}');
      if (mounted) {
        await _load();
      }
    }
  }

  Future<void> _openLink() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _LinkDialog());
    if (text == null || !mounted) {
      return;
    }
    final route = routeForText(text);
    if (route == null) {
      showVizeMessage(context, 'Это не ссылка на трек, альбом или плейлист');
      return;
    }
    await context.push(route);
    if (mounted) {
      await _load();
    }
  }

  Future<void> _remove(LibraryItem item) async {
    try {
      if (item.isAlbum) {
        await widget.api.removeAlbumFromLibrary(item.id);
      } else {
        await widget.api.removePlaylistFromLibrary(item.id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    }
  }

  Widget _tile(LibraryItem item) {
    final canRemove = item.isAlbum || item.isSaved;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VizeCard(
        onTap: () async {
          await context.push(item.route);
          if (mounted) {
            await _load();
          }
        },
        child: Row(
          children: [
            PlaylistCollage(
              urls: item.coverUrls,
              icon: item.isAlbum ? Icons.album_outlined : (item.isLiked ? Icons.favorite : Icons.queue_music),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(item.caption, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (canRemove)
              PopupMenuButton<String>(
                tooltip: 'Меню',
                onSelected: (_) => _remove(item),
                itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Убрать из библиотеки'))],
              )
            else
              const Icon(Icons.chevron_right, color: VizeColors.accentMuted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 4,
      header: VizeHeader(
        title: 'Библиотека',
        showBack: false,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Открыть по ссылке',
              onPressed: _openLink,
              icon: const Icon(Icons.link, color: VizeColors.accentMuted),
            ),
            IconButton(
              tooltip: 'Новый плейлист',
              onPressed: _create,
              icon: const Icon(Icons.add, color: VizeColors.accent),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final entry in _filters.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    onSelected: (_) {
                      if (_filter != entry.key) {
                        _filter = entry.key;
                        _load();
                      }
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_error!, style: const TextStyle(color: VizeColors.danger)),
                            const SizedBox(height: 16),
                            VizePrimaryButton(label: 'Повторить', onPressed: _load),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          children: [
                            if (_items.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 24),
                                child: Text(
                                  'Пока пусто. Создайте плейлист или добавьте альбом из каталога.',
                                  style: TextStyle(color: VizeColors.accentMuted),
                                ),
                              ),
                            for (final item in _items) _tile(item),
                            if (_next != null)
                              TextButton(
                                onPressed: _more ? null : _loadMore,
                                child: Text(_more ? 'Загрузка…' : 'Показать ещё'),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Плейлист
// ---------------------------------------------------------------------------

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.api, required this.id});

  final ApiClient api;
  final String id;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  PlaylistDetail? _playlist;
  List<LikedPlaylistTrack> _tracks = const [];
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _playlist == null;
      _error = null;
    });
    try {
      PlaylistDetail detail;
      try {
        detail = await widget.api.playlistAll(widget.id);
      } on ApiException catch (e) {
        if (e.status != 404) {
          rethrow;
        }
        // Не свой — пробуем как чужой публичный.
        detail = await widget.api.playlistAll(widget.id, own: false);
      }
      if (mounted) {
        setState(() {
          _playlist = detail;
          _tracks = detail.tracks;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _errorText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _playAll() async {
    final player = PlayerScope.maybeOf(context);
    if (_tracks.isEmpty || player == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await player.playTrackIds(_tracks.map((t) => t.id));
      if (mounted) {
        openPlayer(context);
      }
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _edit() async {
    final playlist = _playlist;
    if (playlist == null) {
      return;
    }
    final updated = await showPlaylistDialog(context, widget.api, edit: playlist);
    if (updated != null) {
      await _load();
    }
  }

  Future<void> _delete() async {
    final playlist = _playlist;
    if (playlist == null) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить «${playlist.title}»?'),
        content: const Text('Сами треки останутся в каталоге.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await widget.api.deletePlaylist(playlist.id);
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    }
  }

  Future<void> _togglePublic(bool value) async {
    try {
      await widget.api.updatePlaylist(widget.id, isPublic: value);
      await _load();
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    }
  }

  Future<void> _share() async {
    final playlist = _playlist;
    if (playlist == null) {
      return;
    }
    if (!playlist.isPublic && playlist.isOwner) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Плейлист приватный'),
          content: const Text('Чтобы поделиться ссылкой, сделайте его публичным.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сделать публичным'),
            ),
          ],
        ),
      );
      if (ok != true) {
        return;
      }
      await _togglePublic(true);
    }
    await Clipboard.setData(ClipboardData(text: widget.api.shareUrl('playlist', widget.id)));
    if (mounted) {
      showVizeMessage(context, 'Ссылка скопирована');
    }
  }

  Future<void> _toggleLibrary() async {
    final playlist = _playlist;
    if (playlist == null) {
      return;
    }
    try {
      if (playlist.inLibrary) {
        await widget.api.removePlaylistFromLibrary(widget.id);
      } else {
        await widget.api.savePlaylistToLibrary(widget.id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    }
  }

  Future<void> _remove(LikedPlaylistTrack track) async {
    final before = _tracks;
    setState(() => _tracks = before.where((t) => t.id != track.id).toList());
    try {
      await widget.api.removeTrackFromPlaylist(widget.id, track.id);
    } catch (e) {
      if (mounted) {
        setState(() => _tracks = before);
        showVizeError(context, e);
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final before = _tracks;
    final ids = reorderList(before.map((t) => t.id).toList(), oldIndex, newIndex);
    final byId = {for (final t in before) t.id: t};
    setState(() => _tracks = [for (final id in ids) byId[id]!]);
    try {
      await widget.api.reorderPlaylist(widget.id, ids);
    } catch (e) {
      if (!mounted) {
        return;
      }
      showVizeError(context, e);
      // При рассинхроне (`order_mismatch`) и любой другой ошибке показываем серверное состояние.
      await _load();
    }
  }

  Widget _header(PlaylistDetail playlist) {
    final owner = playlist.isOwner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: PlaylistCollage(urls: playlist.coverUrls, size: 160, radius: 16)),
        const SizedBox(height: 16),
        if (playlist.description != null && playlist.description!.isNotEmpty) ...[
          Text(playlist.description!, style: const TextStyle(color: VizeColors.accentMuted)),
          const SizedBox(height: 8),
        ],
        Text(
          [
            if (!owner && playlist.ownerName != null) playlist.ownerName!,
            '${_tracks.length} треков',
            if (owner) (playlist.isPublic ? 'публичный' : 'приватный'),
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        VizePrimaryButton(label: 'Играть', busy: _busy, onPressed: _tracks.isEmpty ? null : _playAll),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Поделиться'),
            ),
            if (!owner)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: _toggleLibrary,
                icon: Icon(playlist.inLibrary ? Icons.check : Icons.library_add_outlined),
                label: Text(playlist.inLibrary ? 'В библиотеке' : 'В библиотеку'),
              ),
          ],
        ),
        if (owner)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Публичный'),
            subtitle: const Text('Доступен по ссылке'),
            value: playlist.isPublic,
            onChanged: _togglePublic,
          ),
        const SizedBox(height: 8),
        if (_tracks.isEmpty)
          Text(
            owner ? 'Пока пусто. Добавьте треки из карточки трека, альбома или очереди.' : 'В плейлисте пока нет треков.',
            style: const TextStyle(color: VizeColors.accentMuted),
          ),
      ],
    );
  }

  Widget _trackTile(LikedPlaylistTrack track, {required bool owner, int? index}) {
    return Padding(
      key: ValueKey(track.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: VizeCard(
        onTap: () => context.push('/track/${track.id}'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    '${track.artistName} · ${formatDuration(track.durationMs)}',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (owner) ...[
              IconButton(
                tooltip: 'Убрать из плейлиста',
                onPressed: () => _remove(track),
                icon: const Icon(Icons.remove_circle_outline, color: VizeColors.accentMuted),
              ),
              if (index != null)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle, color: VizeColors.accentMuted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _menu(PlaylistDetail? playlist) {
    if (playlist == null || !playlist.isOwner) {
      return null;
    }
    return PopupMenuButton<String>(
      tooltip: 'Меню',
      onSelected: (value) => value == 'edit' ? _edit() : _delete(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Изменить')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;
    return VizeScaffold(
      header: VizeHeader(title: playlist?.title ?? 'Плейлист', showBack: true, trailing: _menu(playlist)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || playlist == null
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_error ?? 'Не найдено', style: const TextStyle(color: VizeColors.danger)),
                      const SizedBox(height: 16),
                      VizePrimaryButton(label: 'Повторить', onPressed: _load),
                    ],
                  ),
                )
              : playlist.isOwner
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      header: Padding(padding: const EdgeInsets.only(bottom: 12), child: _header(playlist)),
                      buildDefaultDragHandles: false,
                      itemCount: _tracks.length,
                      onReorderItem: _onReorder,
                      itemBuilder: (_, i) => _trackTile(_tracks[i], owner: true, index: i),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          _header(playlist),
                          const SizedBox(height: 12),
                          for (final t in _tracks) _trackTile(t, owner: false),
                        ],
                      ),
                    ),
    );
  }
}
