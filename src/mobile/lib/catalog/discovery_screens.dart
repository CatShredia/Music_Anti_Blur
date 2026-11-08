import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../player/player_controller.dart';
import '../player/player_nav.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalog_models.dart';
import 'catalog_screens.dart';
import 'discovery_api.dart';

String _errorText(Object e) => e is ApiException ? e.localizedMessage : '$e';

/// Жанры чипами; нажатие открывает страницу жанра.
class GenreChips extends StatelessWidget {
  const GenreChips({super.key, required this.genres});

  final List<GenreRef> genres;

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final genre in genres)
          ActionChip(
            label: Text(genre.name),
            onPressed: () => context.push('/genre/${genre.id}'),
          ),
      ],
    );
  }
}

/// Плитка популярного трека: название, альбом и длительность, без числа прослушиваний.
class PopularTrackTile extends StatelessWidget {
  const PopularTrackTile({super.key, required this.track});

  final PopularTrack track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CatalogTile(
        icon: Icons.audiotrack_outlined,
        title: track.title,
        subtitle: '${track.albumTitle} · ${formatDuration(track.durationMs)}',
        coverUrl: track.coverUrl,
        onTap: () => context.push('/track/${track.id}'),
      ),
    );
  }
}

/// Играет [ids] с первого трека и открывает плеер. Пустой список даёт подсказку.
Future<void> playIds(BuildContext context, List<String> ids) async {
  final player = PlayerScope.maybeOf(context);
  if (player == null) {
    return;
  }
  if (ids.isEmpty) {
    showVizeMessage(context, 'Пока нечего играть');
    return;
  }
  await player.playTrackIds(ids);
  if (context.mounted) {
    openPlayer(context);
  }
}

// ---------------------------------------------------------------------------
// Страница исполнителя
// ---------------------------------------------------------------------------

class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.api, required this.id});

  final ApiClient api;
  final String id;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  ArtistDetail? _artist;
  List<PopularTrack> _popular = const [];
  bool _allPopular = false;
  String? _error;
  bool _notFound = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _notFound = false;
    });
    try {
      final artist = await widget.api.artist(widget.id);
      if (mounted) {
        setState(() {
          _artist = artist;
          _popular = artist.popular;
        });
      }
    } catch (e) {
      if (mounted) {
        final missing = e is ApiException && e.status == 404;
        setState(() {
          _notFound = missing;
          _error = missing ? 'Исполнитель не найден' : _errorText(e);
        });
      }
    }
  }

  Future<void> _showAllPopular() async {
    try {
      final all = await widget.api.artistPopular(widget.id, limit: 50);
      if (mounted) {
        setState(() {
          _popular = all;
          _allPopular = true;
        });
      }
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    }
  }

  /// «Слушать»: популярные треки; если прослушиваний ещё нет, дискография по порядку.
  Future<void> _listen() async {
    final artist = _artist;
    if (artist == null || PlayerScope.maybeOf(context) == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final ids = (await widget.api.artistPopular(widget.id)).map((t) => t.id).toList();
      if (ids.isEmpty) {
        for (final album in artist.albums) {
          final detail = await widget.api.album(album.id);
          ids.addAll(detail.tracks.map((t) => t.id));
        }
      }
      if (mounted) {
        await playIds(context, ids);
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

  @override
  Widget build(BuildContext context) {
    final artist = _artist;
    return VizeScaffold(
      header: VizeHeader(title: artist?.name ?? 'Исполнитель'),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!, style: const TextStyle(color: VizeColors.danger)),
                  const SizedBox(height: 16),
                  if (_notFound)
                    VizePrimaryButton(
                      label: 'Назад',
                      onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    )
                  else
                    VizePrimaryButton(label: 'Повторить', onPressed: _load),
                ],
              ),
            )
          : artist == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    CatalogCover(coverUrl: artist.coverUrl),
                    if (artist.genres.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      GenreChips(genres: artist.genres),
                    ],
                    const SizedBox(height: 16),
                    VizePrimaryButton(
                      label: 'Слушать',
                      busy: _busy,
                      onPressed: PlayerScope.maybeOf(context) == null ? null : _listen,
                    ),
                    if (_popular.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Популярное', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      for (final track in _popular) PopularTrackTile(track: track),
                      if (!_allPopular && _popular.length >= ArtistDetail.popularPreview)
                        TextButton(onPressed: _showAllPopular, child: const Text('Показать все')),
                    ],
                    const SizedBox(height: 24),
                    Text('Дискография', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (artist.albums.isEmpty)
                      const Text('Альбомов пока нет', style: TextStyle(color: VizeColors.accentMuted))
                    else
                      for (final album in artist.albums)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CatalogTile(
                            icon: Icons.album_outlined,
                            title: album.title,
                            subtitle: album.year?.toString(),
                            coverUrl: album.coverUrl,
                            onTap: () => context.push('/album/${album.id}'),
                          ),
                        ),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Страница жанра
// ---------------------------------------------------------------------------

class GenreScreen extends StatefulWidget {
  const GenreScreen({super.key, required this.api, required this.id});

  final ApiClient api;
  final String id;

  @override
  State<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends State<GenreScreen> {
  GenreDetail? _genre;
  String? _error;
  bool _notFound = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _notFound = false;
    });
    try {
      final genre = await widget.api.genre(widget.id);
      if (mounted) {
        setState(() => _genre = genre);
      }
    } catch (e) {
      if (mounted) {
        final missing = e is ApiException && e.status == 404;
        setState(() {
          _notFound = missing;
          _error = missing ? 'Жанр не найден' : _errorText(e);
        });
      }
    }
  }

  Future<void> _listen() async {
    final genre = _genre;
    if (genre == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await playIds(context, genre.popular.map((t) => t.id).toList());
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

  @override
  Widget build(BuildContext context) {
    final genre = _genre;
    return VizeScaffold(
      header: VizeHeader(title: genre?.name ?? 'Жанр'),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!, style: const TextStyle(color: VizeColors.danger)),
                  const SizedBox(height: 16),
                  if (_notFound)
                    VizePrimaryButton(
                      label: 'Назад',
                      onPressed: () => context.canPop() ? context.pop() : context.go('/search'),
                    )
                  else
                    VizePrimaryButton(label: 'Повторить', onPressed: _load),
                ],
              ),
            )
          : genre == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    if (genre.popular.isNotEmpty) ...[
                      VizePrimaryButton(
                        label: 'Слушать популярное',
                        busy: _busy,
                        onPressed: PlayerScope.maybeOf(context) == null ? null : _listen,
                      ),
                      const SizedBox(height: 24),
                      Text('Популярное', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      for (final track in genre.popular) PopularTrackTile(track: track),
                      const SizedBox(height: 12),
                    ],
                    Text('Альбомы', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (genre.albums.isEmpty)
                      const Text('Альбомов с этим жанром пока нет', style: TextStyle(color: VizeColors.accentMuted))
                    else
                      for (final album in genre.albums)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CatalogTile(
                            icon: Icons.album_outlined,
                            title: album.title,
                            subtitle: [
                              album.artist.name,
                              if (album.year != null) '${album.year}',
                            ].join(' · '),
                            coverUrl: album.coverUrl,
                            onTap: () => context.push('/album/${album.id}'),
                          ),
                        ),
                  ],
                ),
    );
  }
}
