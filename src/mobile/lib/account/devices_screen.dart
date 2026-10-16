import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../player/player_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<DeviceSession> _devices = const [];
  String? _error;
  bool _loading = true;
  String? _busyId;

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
      final devices = await widget.api.devices();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
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

  String _when(DateTime at) {
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} $hh:$mm';
  }

  String _label(String id) => id.length <= 8 ? id : id.substring(0, 8);

  Future<void> _revoke(DeviceSession device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VizeColors.bgElevated,
        title: Text(device.current ? 'Выйти на этом устройстве?' : 'Отключить устройство?'),
        content: Text(
          device.current
              ? 'Сессия на этом телефоне или компьютере будет закрыта.'
              : 'Устройство ${_label(device.deviceId)} больше не сможет обновлять вход.',
          style: const TextStyle(color: VizeColors.accentMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отключить')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    setState(() => _busyId = device.deviceId);
    try {
      await widget.api.revokeDevice(device.deviceId);
      if (!mounted) {
        return;
      }
      if (device.current) {
        await PlayerScope.maybeOf(context)?.resetLocal();
        await widget.api.logout();
        if (mounted) {
          context.go('/login');
        }
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        showVizeError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 3,
      header: const VizeHeader(title: 'Устройства', showBack: true),
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
                      const Text(
                        'Здесь сессии, которые ещё могут входить. Отключение гасит их refresh-токены.',
                        style: TextStyle(color: VizeColors.accentMuted),
                      ),
                      const SizedBox(height: 16),
                      if (_devices.isEmpty)
                        const Text('Активных устройств нет', style: TextStyle(color: VizeColors.accentMuted))
                      else
                        ..._devices.map(
                          (device) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: VizeCard(
                              child: Row(
                                children: [
                                  const Icon(Icons.devices_outlined, color: VizeColors.accentMuted),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          device.current ? 'Это устройство' : 'Устройство ${_label(device.deviceId)}',
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _when(device.lastSeenAt),
                                          style: const TextStyle(color: VizeColors.accentMuted, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _busyId == null ? () => _revoke(device) : null,
                                    child: Text(
                                      _busyId == device.deviceId ? '…' : 'Отключить',
                                      style: const TextStyle(color: VizeColors.danger),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
