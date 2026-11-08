import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/api_client.dart';
import '../library/deep_link.dart';
import '../player/player_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import 'security_models.dart';

String _methodTitle(String method) => switch (method) {
      'totp' => 'Приложение',
      'email' => 'Почта',
      'recovery' => 'Резервный код',
      _ => method,
    };

/// Second step of sign-in.
class TwoFactorLoginScreen extends StatefulWidget {
  const TwoFactorLoginScreen({super.key, required this.api, required this.challenge});

  final ApiClient api;
  final TwoFactorChallenge challenge;

  @override
  State<TwoFactorLoginScreen> createState() => _TwoFactorLoginScreenState();
}

class _TwoFactorLoginScreenState extends State<TwoFactorLoginScreen> {
  final _code = TextEditingController();
  late String _method = widget.challenge.methods.first;
  bool _busy = false;
  bool _emailSent = false;
  FormFeedback _feedback = FormFeedback.empty;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendEmail() async {
    setState(() => _busy = true);
    try {
      await widget.api.sendTwoFactorEmail(widget.challenge.challengeId);
      if (mounted) {
        setState(() {
          _emailSent = true;
          _feedback = FormFeedback.empty;
        });
        showVizeMessage(context, 'Код отправлен на почту');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _feedback = FormFeedback.fromError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _feedback = const FormFeedback(fields: {'code': 'Введите код'}));
      return;
    }
    setState(() {
      _busy = true;
      _feedback = FormFeedback.empty;
    });
    try {
      await widget.api.verifyTwoFactor(
        challengeId: widget.challenge.challengeId,
        method: _method,
        code: code,
      );
      if (mounted) {
        unawaited(PlayerScope.maybeOf(context)?.restoreIfNeeded());
        context.go(PendingLink.take() ?? '/home');
      }
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.code == 'challenge_expired') {
        showVizeError(context, e);
        context.go('/login');
        return;
      }
      setState(() => _feedback = FormFeedback.fromError(e));
    } catch (e) {
      if (mounted) {
        setState(() => _feedback = FormFeedback.fromError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = widget.challenge.methods;
    return VizeScaffold(
      showMiniPlayer: false,
      header: const VizeHeader(title: 'Подтверждение входа', showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_feedback.banner != null) VizeFormBanner(message: _feedback.banner!),
          if (methods.length > 1) ...[
            SegmentedButton<String>(
              segments: [
                for (final m in methods) ButtonSegment(value: m, label: Text(_methodTitle(m))),
              ],
              selected: {_method},
              onSelectionChanged: (v) => setState(() {
                _method = v.first;
                _code.clear();
                _feedback = FormFeedback.empty;
              }),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            switch (_method) {
              'totp' => 'Введите 6-значный код из приложения-аутентификатора.',
              'email' => _emailSent
                  ? 'Введите код из письма. Он действует 5 минут.'
                  : 'Отправим одноразовый код на подтверждённую почту.',
              _ => 'Введите один из резервных кодов. Каждый код работает один раз.',
            },
            style: const TextStyle(color: VizeColors.accentMuted),
          ),
          const SizedBox(height: 12),
          if (_method == 'email' && !_emailSent)
            VizePrimaryButton(label: 'Отправить код', busy: _busy, onPressed: _sendEmail)
          else ...[
            if (_method == 'recovery')
              VizeTextField(
                controller: _code,
                label: 'Резервный код',
                maxLength: 9,
                errorText: _feedback['code'],
                onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
              )
            else
              VizeCodeField(
                controller: _code,
                label: _method == 'totp' ? 'Код из приложения' : 'Код из письма',
                errorText: _feedback['code'],
                onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
              ),
            const SizedBox(height: 20),
            VizePrimaryButton(label: 'Войти', busy: _busy, onPressed: _submit),
            if (_method == 'email')
              TextButton(onPressed: _busy ? null : _sendEmail, child: const Text('Отправить код ещё раз')),
          ],
        ],
      ),
    );
  }
}

/// Settings → Two-factor protection.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  TwoFactorStatus? _status;
  UserDto? _me;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([widget.api.twoFactorStatus(), widget.api.me()]);
      if (mounted) {
        setState(() {
          _status = results[0] as TwoFactorStatus;
          _me = results[1] as UserDto;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.localizedMessage : '$e');
      }
    }
  }

  Future<String?> _askPassword(String title) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PasswordDialog(title: title),
    );
    return result == null || result.isEmpty ? null : result;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
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

  Future<void> _enableTotp() async {
    final password = await _askPassword('Подключить приложение');
    if (password == null || !mounted) {
      return;
    }
    await _run(() async {
      final setup = await widget.api.beginTotpSetup(password);
      if (!mounted) {
        return;
      }
      final codes = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(builder: (_) => _TotpSetupPage(api: widget.api, setup: setup)),
      );
      if (codes != null && mounted) {
        await showRecoveryCodes(context, codes);
      }
    });
  }

  Future<void> _toggleEmail(bool on) async {
    final password = await _askPassword(on ? 'Включить код на почту' : 'Выключить код на почту');
    if (password == null || !mounted) {
      return;
    }
    await _run(() async {
      if (on) {
        final codes = await widget.api.enableEmailTwoFactor(password);
        if (codes != null && mounted) {
          await showRecoveryCodes(context, codes);
        }
      } else {
        await widget.api.disableEmailTwoFactor(password);
      }
    });
  }

  Future<void> _regenerate() async {
    final password = await _askPassword('Новые резервные коды');
    if (password == null || !mounted) {
      return;
    }
    await _run(() async {
      final codes = await widget.api.regenerateRecoveryCodes(password);
      if (mounted) {
        await showRecoveryCodes(context, codes);
      }
    });
  }

  Future<void> _disableAll() async {
    final needsCode = _status?.totp == true;
    final result = await showDialog<({String password, String code})>(
      context: context,
      builder: (context) => _DisableDialog(needsCode: needsCode),
    );
    if (result == null || result.password.isEmpty || !mounted) {
      return;
    }
    await _run(
      () => widget.api.disableTwoFactor(
        currentPassword: result.password,
        code: needsCode ? result.code : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final emailVerified = _me?.emailVerifiedAt != null;
    return VizeScaffold(
      tabIndex: 3,
      header: const VizeHeader(title: 'Двухфакторная защита', showBack: true),
      body: _error != null
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
          : status == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Text(
                      status.enabled
                          ? 'Защита включена: после пароля при входе понадобится второй фактор.'
                          : 'После пароля вход будет требовать код. Так аккаунт не украсть одним паролем.',
                      style: const TextStyle(color: VizeColors.accentMuted),
                    ),
                    const SizedBox(height: 16),
                    VizeSettingRow(
                      icon: Icons.phonelink_lock_outlined,
                      label: 'Приложение-аутентификатор',
                      value: status.totp ? 'Включено' : 'Подключить',
                      onTap: _busy || status.totp ? null : _enableTotp,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.mark_email_read_outlined, color: VizeColors.accentMuted),
                      title: const Text('Код на почту', style: TextStyle(color: VizeColors.text)),
                      subtitle: Text(
                        emailVerified ? 'Запасной способ, если телефона нет рядом' : 'Нужна подтверждённая почта',
                        style: const TextStyle(color: VizeColors.accentMuted, fontSize: 13),
                      ),
                      value: status.email,
                      onChanged: _busy || (!emailVerified && !status.email) ? null : _toggleEmail,
                    ),
                    if (status.enabled) ...[
                      VizeSettingRow(
                        icon: Icons.key_outlined,
                        label: 'Резервные коды',
                        value: 'Осталось ${status.recoveryCodesLeft}',
                        onTap: _busy ? null : _regenerate,
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: _busy ? null : _disableAll,
                        child: const Text('Выключить защиту', style: TextStyle(color: VizeColors.danger)),
                      ),
                    ],
                  ],
                ),
    );
  }
}

/// Owns its controller, so it is disposed only after the dialog route is gone.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title});

  final String title;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VizeColors.bgElevated,
      title: Text(widget.title),
      content: VizePasswordField(controller: _controller, label: 'Текущий пароль'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Далее')),
      ],
    );
  }
}

class _DisableDialog extends StatefulWidget {
  const _DisableDialog({required this.needsCode});

  final bool needsCode;

  @override
  State<_DisableDialog> createState() => _DisableDialogState();
}

class _DisableDialogState extends State<_DisableDialog> {
  final _password = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VizeColors.bgElevated,
      title: const Text('Выключить двухфакторную защиту?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VizePasswordField(controller: _password, label: 'Текущий пароль'),
          if (widget.needsCode) ...[
            const SizedBox(height: 12),
            VizeTextField(controller: _code, label: 'Код из приложения или резервный код', maxLength: 9),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(
          onPressed: () => Navigator.pop(context, (password: _password.text, code: _code.text.trim())),
          child: const Text('Выключить', style: TextStyle(color: VizeColors.danger)),
        ),
      ],
    );
  }
}

class _TotpSetupPage extends StatefulWidget {
  const _TotpSetupPage({required this.api, required this.setup});

  final ApiClient api;
  final TotpSetup setup;

  @override
  State<_TotpSetupPage> createState() => _TotpSetupPageState();
}

class _TotpSetupPageState extends State<_TotpSetupPage> {
  final _code = TextEditingController();
  bool _busy = false;
  FormFeedback _feedback = FormFeedback.empty;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _feedback = FormFeedback.empty;
    });
    try {
      final codes = await widget.api.confirmTotp(_code.text.trim());
      if (mounted) {
        Navigator.of(context).pop(codes);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _feedback = FormFeedback.fromError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 3,
      showMiniPlayer: false,
      header: const VizeHeader(title: 'Приложение-аутентификатор', showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Text(
            '1. Отсканируйте QR-код в Google Authenticator, Яндекс Ключе или похожем приложении.',
            style: TextStyle(color: VizeColors.accentMuted),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: widget.setup.otpauthUri, size: 200),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Или введите ключ вручную:', style: TextStyle(color: VizeColors.accentMuted)),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  widget.setup.groupedSecret,
                  style: const TextStyle(color: VizeColors.text, fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                tooltip: 'Скопировать ключ',
                icon: const Icon(Icons.copy, color: VizeColors.accentMuted),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.setup.secret));
                  if (context.mounted) {
                    showVizeMessage(context, 'Ключ скопирован');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('2. Введите код, который показало приложение.', style: TextStyle(color: VizeColors.accentMuted)),
          const SizedBox(height: 8),
          if (_feedback.banner != null) VizeFormBanner(message: _feedback.banner!),
          VizeCodeField(
            controller: _code,
            label: 'Код из приложения',
            errorText: _feedback['code'],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          const SizedBox(height: 20),
          VizePrimaryButton(label: 'Подключить', busy: _busy, onPressed: _confirm),
        ],
      ),
    );
  }
}

/// Shows recovery codes once, with copy-to-clipboard.
Future<void> showRecoveryCodes(BuildContext context, List<String> codes) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: VizeColors.bgElevated,
      title: const Text('Резервные коды'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Сохраните их в надёжном месте. Каждый код срабатывает один раз. Больше они показаны не будут.',
            style: TextStyle(color: VizeColors.accentMuted),
          ),
          const SizedBox(height: 12),
          SelectableText(
            codes.join('\n'),
            style: const TextStyle(color: VizeColors.text, fontFamily: 'monospace', fontSize: 16, height: 1.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: codes.join('\n')));
            if (context.mounted) {
              showVizeMessage(context, 'Коды скопированы');
            }
          },
          child: const Text('Скопировать'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Я сохранил')),
      ],
    ),
  );
}

/// Settings → Login history.
class LoginHistoryScreen extends StatefulWidget {
  const LoginHistoryScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<LoginHistoryScreen> createState() => _LoginHistoryScreenState();
}

class _LoginHistoryScreenState extends State<LoginHistoryScreen> {
  final List<LoginEvent> _items = [];
  String? _cursor;
  bool _loading = true;
  bool _hasMore = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.loginEvents(cursor: reset ? null : _cursor);
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _items.clear();
        }
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException ? e.localizedMessage : '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _notMe(LoginEvent event) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VizeColors.bgElevated,
        title: const Text('Это были не вы?'),
        content: const Text(
          'Сессии этого устройства будут завершены. На почту придёт письмо с советами. Обязательно смените пароль.',
          style: TextStyle(color: VizeColors.accentMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Завершить сессии', style: TextStyle(color: VizeColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    setState(() => _busyId = event.id);
    try {
      await widget.api.reportNotMe(event.id);
      if (mounted) {
        showVizeMessage(context, 'Сессии устройства завершены. Смените пароль.');
        await _load(reset: true);
      }
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

  String _when(DateTime at) {
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 3,
      header: const VizeHeader(title: 'Журнал входов', showBack: true),
      body: _error != null && _items.isEmpty
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  const Text(
                    'Входы и попытки входа за 90 дней. Если видите чужой вход, нажмите «Это не я».',
                    style: TextStyle(color: VizeColors.accentMuted),
                  ),
                  const SizedBox(height: 16),
                  if (_items.isEmpty && !_loading)
                    const Text('Записей нет', style: TextStyle(color: VizeColors.accentMuted)),
                  for (final e in _items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: VizeCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              e.succeeded ? Icons.login : Icons.warning_amber_outlined,
                              color: e.succeeded ? VizeColors.accentMuted : VizeColors.danger,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.resultLabel, style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_when(e.at)} · ${e.methodLabel}${e.currentDevice ? ' · это устройство' : ''}',
                                    style: const TextStyle(color: VizeColors.accentMuted, fontSize: 13),
                                  ),
                                  Text(
                                    'IP ${e.ip}${e.userAgent == null ? '' : ' · ${e.userAgent}'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: VizeColors.accentMuted, fontSize: 12),
                                  ),
                                  if (e.notMeAt != null)
                                    const Text(
                                      'Отмечено как чужой вход',
                                      style: TextStyle(color: VizeColors.danger, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                            if (e.notMeAt == null && !e.currentDevice && e.deviceId != null)
                              TextButton(
                                onPressed: _busyId == null ? () => _notMe(e) : null,
                                child: Text(
                                  _busyId == e.id ? '…' : 'Это не я',
                                  style: const TextStyle(color: VizeColors.danger),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_loading) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
                  if (!_loading && _hasMore)
                    TextButton(onPressed: () => _load(), child: const Text('Показать ещё')),
                ],
              ),
            ),
    );
  }
}
