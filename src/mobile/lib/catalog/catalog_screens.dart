import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../player/player_controller.dart';
import '../player/player_nav.dart';
import '../theme.dart';
import '../validation/catalog_rules.dart';
import '../widgets.dart';
import 'catalog_models.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ArtistListItem> _artists = const [];
  List<AlbumListItem> _albums = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    PlayerScope.maybeOf(context)?.restoreIfNeeded();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final artists = await widget.api.listArtists(limit: 20);
      final albums = <AlbumListItem>[];
      for (final artist in artists.items.take(3)) {
        final page = await widget.api.listAlbums(artistId: artist.id, limit: 8);
        albums.addAll(page.items);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _artists = artists.items;
        _albums = albums;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e is ApiException ? e.localizedMessage : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 0,
      header: VizeHeader(
        showLogo: true,
        trailing: IconButton(
          tooltip: 'Профиль',
          onPressed: () => context.go('/settings'),
          icon: const Icon(Icons.person_outline, color: VizeColors.accentMuted),
        ),
      ),
      body: _loading
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      Text('Каталог', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 6),
                      const Text(
                        'Исполнители и альбомы. Воспроизведение появится позже.',
                        style: TextStyle(color: VizeColors.accentMuted, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      Text('Исполнители', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      if (_artists.isEmpty)
                        const Text('Пока пусто', style: TextStyle(color: VizeColors.accentMuted))
                      else
                        ..._artists.map(
                          (artist) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: CatalogTile(
                              icon: Icons.person_outline,
                              title: artist.name,
                              onTap: () => context.push('/artist/${artist.id}'),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text('Альбомы', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      if (_albums.isEmpty)
                        const Text('Пока пусто', style: TextStyle(color: VizeColors.accentMuted))
                      else
                        ..._albums.map(
                          (album) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: CatalogTile(
                              icon: Icons.album_outlined,
                              title: album.title,
                              subtitle: [
                                album.artist.name,
                                if (album.year != null) '${album.year}',
                              ].join(' · '),
                              coverObjectKey: album.coverObjectKey,
                              onTap: () => context.push('/album/${album.id}'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  FormFeedback _feedback = FormFeedback.empty;
  List<SearchItem> _items = const [];
  bool _busy = false;
  bool _searched = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final codes = CatalogRules.search(_query.text);
    if (codes.isNotEmpty) {
      setState(() {
        _feedback = FormFeedback.client(codes);
        _items = const [];
        _searched = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _feedback = FormFeedback.empty;
    });
    try {
      final page = await widget.api.search(_query.text.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _items = page.items;
        _searched = true;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _feedback = FormFeedback.fromError(e);
        _busy = false;
        _searched = true;
      });
    }
  }

  void _open(SearchItem item) {
    final path = switch (item.type) {
      'artist' => '/artist/${item.id}',
      'album' => '/album/${item.id}',
      'track' => '/track/${item.id}',
      _ => null,
    };
    if (path != null) {
      context.push(path);
    }
  }

  IconData _icon(String type) => switch (type) {
        'artist' => Icons.person_outline,
        'album' => Icons.album_outlined,
        _ => Icons.audiotrack_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 1,
      header: const VizeHeader(title: 'Поиск'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_feedback.banner != null) VizeFormBanner(message: _feedback.banner!),
          VizeTextField(
            controller: _query,
            label: 'Название трека, альбома или исполнителя',
            maxLength: CatalogRules.queryMax,
            textInputAction: TextInputAction.search,
            errorText: _feedback['q'],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 16),
          VizePrimaryButton(label: 'Найти', busy: _busy, onPressed: _search),
          const SizedBox(height: 20),
          if (_searched && _items.isEmpty && _feedback.banner == null)
            const Text('Ничего не найдено', style: TextStyle(color: VizeColors.accentMuted)),
          ..._items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CatalogTile(
                icon: _icon(item.type),
                title: item.title,
                subtitle: item.subtitle,
                onTap: () => _open(item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.api, required this.id});
  final ApiClient api;
  final String id;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  ArtistDetail? _artist;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.artist(widget.id).then((value) {
      if (mounted) {
        setState(() => _artist = value);
      }
    }).catchError((e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.localizedMessage : e.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      header: VizeHeader(title: _artist?.name ?? 'Исполнитель'),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, style: const TextStyle(color: VizeColors.danger)),
            )
          : _artist == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    if (_artist!.albums.isEmpty)
                      const Text('Альбомов пока нет', style: TextStyle(color: VizeColors.accentMuted))
                    else
                      ..._artist!.albums.map(
                        (album) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CatalogTile(
                            icon: Icons.album_outlined,
                            title: album.title,
                            subtitle: album.year?.toString(),
                            onTap: () => context.push('/album/${album.id}'),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.api, required this.id});
  final ApiClient api;
  final String id;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  AlbumDetail? _album;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.api.album(widget.id).then((value) {
      if (mounted) {
        setState(() => _album = value);
      }
    }).catchError((e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.localizedMessage : e.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final album = _album;
    return VizeScaffold(
      header: VizeHeader(title: album?.title ?? 'Альбом'),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, style: const TextStyle(color: VizeColors.danger)),
            )
          : album == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    CatalogCover(coverObjectKey: album.coverObjectKey),
                    const SizedBox(height: 16),
                    Text(album.artist.name, style: Theme.of(context).textTheme.titleMedium),
                    if (album.year != null)
                      Text('${album.year}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 20),
                    VizePrimaryButton(
                      label: 'Играть альбом',
                      busy: _busy,
                      onPressed: album.tracks.isEmpty || PlayerScope.maybeOf(context) == null
                          ? null
                          : () async {
                              final player = PlayerScope.maybeOf(context);
                              if (player == null) {
                                return;
                              }
                              setState(() => _busy = true);
                              try {
                                await player.playAlbum(album);
                                if (context.mounted) {
                                  openPlayer(context);
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  showVizeError(context, e);
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _busy = false);
                                }
                              }
                            },
                    ),
                    const SizedBox(height: 20),
                    ...album.tracks.map(
                      (track) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CatalogTile(
                          icon: Icons.audiotrack_outlined,
                          title: '${track.trackNumber}. ${track.title}',
                          subtitle: formatDuration(track.durationMs),
                          onTap: () => context.push('/track/${track.id}'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, required this.api, required this.id});
  final ApiClient api;
  final String id;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  TrackDetail? _track;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.api.track(widget.id).then((value) {
      if (mounted) {
        setState(() => _track = value);
      }
    }).catchError((e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.localizedMessage : e.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return VizeScaffold(
      header: VizeHeader(title: track?.title ?? 'Трек'),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, style: const TextStyle(color: VizeColors.danger)),
            )
          : track == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    CatalogCover(coverObjectKey: null),
                    const SizedBox(height: 16),
                    Text(track.artist.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(track.album.title, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      'Трек ${track.trackNumber} · ${formatDuration(track.durationMs)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    if (track.availableQualities.isEmpty)
                      const Text(
                        'Файл ещё не загружен. После обработки admin здесь появятся качества.',
                        style: TextStyle(color: VizeColors.accentMuted, fontSize: 14),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final quality in track.availableQualities)
                            VizeChip(label: quality.label, selected: true, onTap: () {}),
                        ],
                      ),
                    const SizedBox(height: 20),
                    VizePrimaryButton(
                      label: 'Play',
                      busy: _busy,
                      onPressed: track.availableQualities.isEmpty ||
                              PlayerScope.maybeOf(context) == null
                          ? null
                          : () async {
                              final player = PlayerScope.maybeOf(context);
                              if (player == null) {
                                return;
                              }
                              setState(() => _busy = true);
                              try {
                                await player.playTrack(track.id);
                                if (context.mounted) {
                                  openPlayer(context);
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  showVizeError(context, e);
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _busy = false);
                                }
                              }
                            },
                    ),
                  ],
                ),
    );
  }
}

class CatalogCover extends StatelessWidget {
  const CatalogCover({super.key, this.coverObjectKey});

  final String? coverObjectKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: VizeColors.surface,
        borderRadius: BorderRadius.circular(VizeRadii.card),
        border: Border.all(color: VizeColors.stroke),
      ),
      child: Icon(
        coverObjectKey == null ? Icons.album_outlined : Icons.image_outlined,
        size: 56,
        color: VizeColors.accentMuted,
      ),
    );
  }
}

class CatalogTile extends StatelessWidget {
  const CatalogTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.coverObjectKey,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? coverObjectKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return VizeCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: VizeColors.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: VizeColors.stroke),
            ),
            child: Icon(
              coverObjectKey == null ? icon : Icons.image_outlined,
              color: VizeColors.accentMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: VizeColors.accentMuted),
        ],
      ),
    );
  }
}
