import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'api/api_client.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MusicAntiBlurApp(api: ApiClient()));
}

class MusicAntiBlurApp extends StatelessWidget {
  MusicAntiBlurApp({super.key, required this.api});

  final ApiClient api;

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
      GoRoute(path: '/settings', builder: (_, _) => SettingsScreen(api: api)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Music Anti Blur',
      theme: VizeTheme.data(),
      routerConfig: _router,
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
          IdentifierTypeField(value: _type, onChanged: (v) => setState(() => _type = v)),
          const SizedBox(height: 16),
          TextField(
            controller: _id,
            keyboardType: _type == 'email' ? TextInputType.emailAddress : TextInputType.text,
            decoration: InputDecoration(labelText: _type == 'email' ? 'Email' : 'Логин'),
          ),
          const SizedBox(height: 12),
          VizePasswordField(controller: _password, label: 'Пароль'),
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: 'Войти',
            busy: _busy,
            onPressed: () async {
              setState(() => _busy = true);
              try {
                await widget.api.login(
                  identifierType: _type,
                  identifier: _id.text,
                  password: _password.text,
                );
                if (context.mounted) {
                  context.go('/home');
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
          TextField(controller: _login, decoration: const InputDecoration(labelText: 'Логин')),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          VizePasswordField(controller: _password, label: 'Пароль (от 12 символов)'),
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: 'Зарегистрироваться',
            busy: _busy,
            onPressed: () async {
              setState(() => _busy = true);
              try {
                await widget.api.register(
                  login: _login.text,
                  email: _email.text,
                  password: _password.text,
                );
                if (!context.mounted) {
                  return;
                }
                await context.push('/check-email?email=${Uri.encodeComponent(_email.text)}');
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
          VizeCodeField(controller: _code),
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: 'Подтвердить',
            busy: _busy,
            onPressed: () async {
              setState(() => _busy = true);
              try {
                await widget.api.verify(_code.text.trim());
                if (!context.mounted) {
                  return;
                }
                context.go('/home');
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
          TextButton(
            onPressed: () async {
              try {
                await widget.api.resend(widget.email);
                if (context.mounted) {
                  showVizeMessage(context, 'Если аккаунт есть, письмо отправлено ещё раз.');
                }
              } catch (e) {
                if (context.mounted) {
                  showVizeError(context, e);
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
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: 'Отправить код',
            busy: _busy,
            onPressed: () async {
              setState(() => _busy = true);
              try {
                await widget.api.forgot(_email.text);
                if (context.mounted) {
                  showVizeMessage(context, 'Если email подтверждён, мы отправили код.');
                  context.push('/reset');
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
          VizeCodeField(controller: _code),
          if (widget.requirePassword) ...[
            const SizedBox(height: 12),
            VizePasswordField(controller: _password, label: 'Новый пароль'),
          ],
          const SizedBox(height: 20),
          VizePrimaryButton(
            label: widget.submitLabel,
            busy: _busy,
            onPressed: () async {
              setState(() => _busy = true);
              try {
                await widget.onSubmit(
                  _code.text.trim(),
                  widget.requirePassword ? _password.text : null,
                );
                if (context.mounted) {
                  widget.onDone(context);
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UserDto? _user;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.me().then((u) => setState(() => _user = u)).catchError((e) {
      setState(() => _error = e.toString());
    });
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
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, style: const TextStyle(color: VizeColors.danger)),
            )
          : _user == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    VizeCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('КАТАЛОГ', style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 8),
                          Text('Скоро здесь', style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 6),
                          const Text(
                            'Поиск и треки появятся в следующем спринте. Сейчас можно войти, подтвердить почту и настроить аккаунт.',
                            style: TextStyle(color: VizeColors.accentMuted, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Аккаунт', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    VizeCard(
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: VizeColors.accent),
                            ),
                            child: const Icon(Icons.person_outline, color: VizeColors.accentMuted),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_user!.login ?? _user!.email ?? 'Пользователь',
                                    style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text(_user!.email ?? 'Email не привязан',
                                    style: Theme.of(context).textTheme.bodySmall),
                                Text(
                                  _user!.emailVerifiedAt == null ? 'Почта не подтверждена' : 'Почта подтверждена',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _email = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  String _quality = 'auto';
  String? _hubStatus;
  bool _loaded = false;

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

  @override
  void dispose() {
    _email.dispose();
    _login.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
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
        showVizeError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VizeScaffold(
      tabIndex: 1,
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
          const SizedBox(height: 20),
          Text('Идентификаторы', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Чтобы привязать email или логин, введите значение и текущий пароль.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 12),
          TextField(controller: _login, decoration: const InputDecoration(labelText: 'Логин')),
          const SizedBox(height: 12),
          VizePasswordField(controller: _password, label: 'Текущий пароль'),
          const SizedBox(height: 12),
          VizePrimaryButton(
            label: 'Привязать email',
            onPressed: () async {
              try {
                await widget.api.bindEmail(_email.text, _password.text);
                if (context.mounted) {
                  showVizeMessage(context, 'Проверьте почту: придёт 6-значный код.');
                }
              } catch (e) {
                if (context.mounted) {
                  showVizeError(context, e);
                }
              }
            },
          ),
          const SizedBox(height: 8),
          VizeCodeField(controller: _code),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              try {
                await widget.api.confirmEmail(_code.text.trim());
                if (context.mounted) {
                  showVizeMessage(context, 'Email подтверждён.');
                }
              } catch (e) {
                if (context.mounted) {
                  showVizeError(context, e);
                }
              }
            },
            child: const Text('Подтвердить код email'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              try {
                await widget.api.bindLogin(_login.text, _password.text);
                if (context.mounted) {
                  showVizeMessage(context, 'Логин привязан.');
                }
              } catch (e) {
                if (context.mounted) {
                  showVizeError(context, e);
                }
              }
            },
            child: const Text('Привязать логин'),
          ),
          const SizedBox(height: 20),
          VizeSettingRow(
            icon: Icons.wifi_tethering,
            label: 'Проверить хаб',
            value: _hubStatus,
            onTap: () async {
              final token = await widget.api.accessToken();
              if (token == null) {
                setState(() => _hubStatus = 'нет токена');
                return;
              }
              final hub = HubConnectionBuilder()
                  .withUrl(
                    widget.api.hubUrl,
                    options: HttpConnectionOptions(
                      accessTokenFactory: () async => token,
                      requestTimeout: 15000,
                    ),
                  )
                  .build();
              try {
                await hub.start();
                setState(() => _hubStatus = 'ок');
                await hub.stop();
              } catch (e) {
                setState(() => _hubStatus = 'ошибка');
              }
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton(
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
    );
  }
}
