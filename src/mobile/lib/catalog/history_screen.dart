import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalog_models.dart';
import 'catalog_screens.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _items = <PlayHistoryItem>[];
  String? _cursor;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_cursor == null || _loadingMore)) {
      return;
    }
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await widget.api.playHistory(cursor: reset ? null : _cursor);
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          _items.addAll(page.items);
        }
        _cursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e is ApiException ? e.localizedMessage : e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  String _when(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return '$hh:$mm';
    }
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 2,
      header: const VizeHeader(title: 'История'),
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
                      VizePrimaryButton(label: 'Повторить', onPressed: () => _load(reset: true)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(20),
                          children: const [
                            Text(
                              'Пока пусто. История появится после прослушивания.',
                              style: TextStyle(color: VizeColors.accentMuted),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: _items.length + (_cursor != null ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _items.length) {
                              if (!_loadingMore) {
                                WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: false));
                              }
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final item = _items[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: CatalogTile(
                                icon: Icons.audiotrack_outlined,
                                title: item.title,
                                subtitle: '${item.artistName} · ${_when(item.playedAt)} · ${item.playCount}×',
                                coverUrl: item.coverUrl,
                                onTap: () => context.push('/track/${item.trackId}'),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
