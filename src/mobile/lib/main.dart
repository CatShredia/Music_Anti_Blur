import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api/api_client.dart';
import 'catalog/catalog_screens.dart';
import 'player/audio_handler.dart';
import 'player/mini_player.dart';
import 'player/player_controller.dart';
import 'player/player_screen.dart';
import 'theme.dart';
import 'validation/auth_rules.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final handler = await createMusicAudioHandler();
  final player = PlayerController(api, handler: handler);
  try {
    await player.prepare();
  } catch (e) {
    debugPrint('audio session prepare failed: $e');
  }
  runApp(MusicAntiBlurApp(api: api, player: player));
}

class MusicAntiBlurApp extends StatelessWidget {
  MusicAntiBlurApp({super.key, required this.api, this.player});

  final ApiClient api;
  final PlayerController? player;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  late final GoRouter _router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => LoginScreen(api: api)),
      GoRoute(path: '/register', builder: (_, _) => RegisterScreen(api: api)),
      GoRoute(
        path: '/check-email',
        builder: (_, state) => CheckEmailScreen(
          api: api,
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: '/verify',
        builder: (_, _) => CodeScreen(
          api: api,
          title: 'Подтверждение почты',
          submitLabel: 'Подтвердить',
          onSubmit: (code, _) => api.verify(code),
          onDone: (context) {
            api.hasSession().then((ok) {
              if (!context.mounted) {
                return;
              }
              context.go(ok ? '/home' : '/login');
            });
          },
        ),
      ),
      GoRoute(path: '/forgot', builder: (_, _) => ForgotScreen(api: api)),
      GoRoute(
        path: '/reset',
        builder: (_, _) => CodeScreen(
          api: api,
          title: 'Сброс пароля',
          submitLabel: 'Сменить пароль',
          requirePassword: true,
          onSubmit: (code, password) =>
              api.reset(code: code, newPassword: password ?? ''),
          onDone: (context) => context.go('/login'),
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => HomeScreen(api: api)),
      GoRoute(path: '/search', builder: (_, _) => SearchScreen(api: api)),
      GoRoute(
        path: '/artist/:id',
        builder: (_, state) => ArtistScreen(api: api, id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/album/:id',
        builder: (_, state) => AlbumScreen(api: api, id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/track/:id',
        builder: (_, state) => TrackScreen(api: api, id: state.pathParameters['id']!),
      ),
      GoRoute(path: '/settings', builder: (_, _) => SettingsScreen(api: api)),
      if (player case final activePlayer?)
        GoRoute(path: '/player', builder: (_, _) => PlayerScreen(player: activePlayer)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp.router(
      title: 'Music Anti Blur',
      theme: VizeTheme.data(),
      routerConfig: _router,
      scaffoldMessengerKey: _messengerKey,
    );
    final current = player;
    if (current == null) {
      return app;
    }
    return PlayerScope(
      notifier: current,
      child: PlayerNoticeHost(player: current, messengerKey: _messengerKey, child: app),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController();
  final _password = TextEditingController();
  String _type = 'login';
  bool _busy = false;
  FormFeedback _feedback = FormFeedback.empty;

  @override
  void initState() {
    super.initState();
    widget.api.hasSession().then((ok) {
      if (ok && mounted) {
        context.go('/home');
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      header: const VizeHeader(showLogo: true, title: 'Вход'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_feedback.banner != null) VizeFormBanner(message: _feedback.banner!),
          IdentifierTypeField(
            value: _type,
            onChanged: (v) => setState(() {
              _type = v;
              _feedback = FormFeedback.empty;
            }),
          ),
          const SizedBox(height: 16),
          VizeTextField(
            controller: _id,
            label: _type == 'email' ? 'Email' : 'Логин',
            keyboardType: _type == 'email' ? TextInputType.emailAddress : TextInputType.text,
            maxLength: _type == 'email' ? AuthRules.emailMax : AuthRules.loginMax,
            errorText: _feedback.of(['identifier', 'login', 'email']),
            autofillHints: _type == 'email' ? const [AutofillHints.email] : const [AutofillHints.username],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          const SizedBox(height: 12),
          VizePasswordField(
            controller: _password,
            label: 'Пароль',
            errorText: _feedback['password'],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: 'Войти',
            busy: _busy,
            onPressed: () async {
              final codes = AuthRules.login(
                identifierType: _type,
                identifier: _id.text,
                password: _password.text,
              );
              if (codes.isNotEmpty) {
                setState(() => _feedback = FormFeedback.client(codes));
                return;
              }
              setState(() {
                _busy = true;
                _feedback = FormFeedback.empty;
              });
              try {
                await widget.api.login(
                  identifierType: _type,
                  identifier: _id.text.trim(),
                  password: _password.text,
                );
                if (context.mounted) {
                  context.go('/home');
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
            },
          ),
          TextButton(onPressed: () => context.push('/register'), child: const Text('Создать аккаунт')),
          TextButton(onPressed: () => context.push('/forgot'), child: const Text('Забыли пароль')),
          TextButton(onPressed: () => context.push('/verify'), child: const Text('У меня есть код подтверждения')),
        ],
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _login = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  FormFeedback _feedback = FormFeedback.empty;

  @override
  void dispose() {
    _login.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      header: const VizeHeader(title: 'Регистрация'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_feedback.banner != null) VizeFormBanner(message: _feedback.banner!),
          VizeTextField(
            controller: _login,
            label: 'Логин',
            maxLength: AuthRules.loginMax,
            errorText: _feedback['login'],
            autofillHints: const [AutofillHints.username],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          const SizedBox(height: 12),
          VizeTextField(
            controller: _email,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            maxLength: AuthRules.emailMax,
            errorText: _feedback['email'],
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          const SizedBox(height: 12),
          VizePasswordField(
            controller: _password,
            label: 'Пароль (12–128 символов)',
            errorText: _feedback['password'],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: 'Зарегистрироваться',
            busy: _busy,
            onPressed: () async {
              final codes = AuthRules.register(
                login: _login.text,
                email: _email.text,
                password: _password.text,
              );
              if (codes.isNotEmpty) {
                setState(() => _feedback = FormFeedback.client(codes));
                return;
              }
              setState(() {
                _busy = true;
                _feedback = FormFeedback.empty;
              });
              try {
                await widget.api.register(
                  login: _login.text.trim(),
                  email: _email.text.trim(),
                  password: _password.text,
                );
                if (!context.mounted) {
                  return;
                }
                await context.push('/check-email?email=${Uri.encodeComponent(_email.text.trim())}');
              } catch (e) {
                if (mounted) {
                  setState(() => _feedback = FormFeedback.fromError(e));
                }
              } finally {
                if (mounted) {
                  setState(() => _busy = false);
                }
              }
            },
          ),
          TextButton(
            onPressed: () => popOrGo(context, '/login'),
            child: const Text('Уже есть аккаунт'),
          ),
        ],
      ),
    );
  }
}

class CheckEmailScreen extends StatefulWidget {
  const CheckEmailScreen({super.key, required this.api, required this.email});
  final ApiClient api;
  final String email;

  @override
  State<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  FormFeedback _feedback = FormFeedback.empty;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      header: const VizeHeader(title: 'Проверьте почту'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            'Мы отправили 6-значный код на ${widget.email}. Локально письма смотрите в MailHog: http://localhost:8025',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (_feedback.banner != null) VizeFormBanner(message: _feedback.banner!),
          VizeCodeField(
            controller: _code,
            errorText: _feedback['code'],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: 'Подтвердить',
            busy: _busy,
            onPressed: () async {
              final codes = AuthRules.verify(_code.text);
              if (codes.isNotEmpty) {
                setState(() => _feedback = FormFeedback.client(codes));
                return;
              }
              setState(() {
                _busy = true;
                _feedback = FormFeedback.empty;
              });
              try {
                await widget.api.verify(_code.text.trim());
                if (!context.mounted) {
                  return;
                }
                context.go('/home');
              } catch (e) {
                if (mounted) {
                  setState(() => _feedback = FormFeedback.fromError(e));
                }
              } finally {
                if (mounted) {
                  setState(() => _busy = false);
                }
              }
            },
          ),
          TextButton(
            onPressed: () async {
              try {
                await widget.api.resend(widget.email);
                if (context.mounted) {
                  showVizeMessage(context, 'Если аккаунт есть, письмо отправлено ещё раз.');
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _feedback = FormFeedback.fromError(e));
                }
              }
            },
            child: const Text('Отправить ещё раз'),
          ),
          TextButton(onPressed: () => popOrGo(context, '/login'), child: const Text('Ко входу')),
        ],
      ),
    );
  }
}

class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends State<ForgotScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  FormFeedback _feedback = FormFeedback.empty;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      header: const VizeHeader(title: 'Забыли пароль'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_feedback.banner != null) VizeFormBanner(message: _feedback.banner!),
          VizeTextField(
            controller: _email,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            maxLength: AuthRules.emailMax,
            errorText: _feedback['email'],
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: 'Отправить код',
            busy: _busy,
            onPressed: () async {
              final codes = AuthRules.forgot(_email.text);
              if (codes.isNotEmpty) {
                setState(() => _feedback = FormFeedback.client(codes));
                return;
              }
              setState(() {
                _busy = true;
                _feedback = FormFeedback.empty;
              });
              try {
                await widget.api.forgot(_email.text.trim());
                if (context.mounted) {
                  showVizeMessage(context, 'Если email подтверждён, мы отправили код.');
                  context.push('/reset');
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
            },
          ),
        ],
      ),
    );
  }
}

class CodeScreen extends StatefulWidget {
  const CodeScreen({
    super.key,
    required this.api,
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    required this.onDone,
    this.requirePassword = false,
  });

  final ApiClient api;
  final String title;
  final String submitLabel;
  final bool requirePassword;
  final Future<void> Function(String code, String? password) onSubmit;
  final void Function(BuildContext context) onDone;

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  FormFeedback _feedback = FormFeedback.empty;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      header: VizeHeader(title: widget.title),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_feedback.banner != null) VizeFormBanner(message: _feedback.banner!),
          VizeCodeField(
            controller: _code,
            errorText: _feedback['code'],
            onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
          ),
          if (widget.requirePassword) ...[
            const SizedBox(height: 12),
            VizePasswordField(
              controller: _password,
              label: 'Новый пароль (12–128 символов)',
              errorText: _feedback.of(['newPassword', 'password']),
              onChanged: (_) => setState(() => _feedback = FormFeedback.empty),
            ),
          ],
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: widget.submitLabel,
            busy: _busy,
            onPressed: () async {
              final codes = widget.requirePassword
                  ? AuthRules.reset(code: _code.text, newPassword: _password.text)
                  : AuthRules.verify(_code.text);
              if (codes.isNotEmpty) {
                setState(() => _feedback = FormFeedback.client(codes));
                return;
              }
              setState(() {
                _busy = true;
                _feedback = FormFeedback.empty;
              });
              try {
                await widget.onSubmit(
                  _code.text.trim(),
                  widget.requirePassword ? _password.text : null,
                );
                if (context.mounted) {
                  widget.onDone(context);
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
            },
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _quality = 'auto';
  bool _loaded = false;
  FormFeedback _feedback = FormFeedback.empty;

  static const _qualities = ['auto', 'aac_128', 'aac_256', 'src'];

  static String _qualityLabel(String code) => switch (code) {
        'auto' => 'Авто',
        'aac_128' => 'aac_128',
        'aac_256' => 'Высокое',
        'src' => 'Исходник',
        _ => code,
      };

  @override
  void initState() {
    super.initState();
    widget.api.settings().then((s) {
      if (mounted) {
        setState(() {
          _quality = s.preferredQuality;
          _loaded = true;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() => _loaded = true);
      }
    });
  }

  Future<void> _pickQuality() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VizeColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Качество звука', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              for (final q in _qualities)
                ListTile(
                  title: Text(_qualityLabel(q), style: const TextStyle(color: VizeColors.text)),
                  trailing: q == _quality ? const Icon(Icons.check, color: VizeColors.accent) : null,
                  onTap: () => Navigator.pop(context, q),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == _quality) {
      return;
    }
    try {
      final updated = await widget.api.updateSettings(selected);
      if (mounted) {
        setState(() => _quality = updated.preferredQuality);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _feedback = FormFeedback.fromError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 2,
      header: const VizeHeader(title: 'Настройки'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          VizeSettingRow(
            icon: Icons.headphones_outlined,
            label: 'Качество звука',
            value: _loaded ? _qualityLabel(_quality) : '…',
            onTap: _pickQuality,
          ),
          if (_feedback.banner != null) ...[
            const SizedBox(height: 16),
            VizeFormBanner(message: _feedback.banner!),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () async {
              await PlayerScope.maybeOf(context)?.resetLocal();
              await widget.api.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}
