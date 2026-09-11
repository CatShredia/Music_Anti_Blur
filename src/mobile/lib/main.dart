import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'api/api_client.dart';

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
          title: 'Verify email',
          submitLabel: 'Confirm',
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
          title: 'Reset password',
          submitLabel: 'Change password',
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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routerConfig: _router,
    );
  }
}

class IdentifierTypeField extends StatelessWidget {
  const IdentifierTypeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'email', label: Text('Email')),
        ButtonSegment(value: 'login', label: Text('Login')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }
}

class CodeField extends StatelessWidget {
  const CodeField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(
        labelText: 'Code from email',
        counterText: '',
      ),
    );
  }
}

void showApiError(BuildContext context, Object error) {
  final text = error is ApiException ? '${error.code}: ${error.title}' : error.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

AppBar buildAppBar(BuildContext context, String title, {List<Widget>? actions}) {
  return AppBar(
    title: Text(title),
    automaticallyImplyLeading: false,
    leading: context.canPop()
        ? BackButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              }
            },
          )
        : null,
    actions: actions,
  );
}

void popOrGo(BuildContext context, String location) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(location);
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context, 'Sign in'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IdentifierTypeField(value: _type, onChanged: (v) => setState(() => _type = v)),
          const SizedBox(height: 16),
          TextField(
            controller: _id,
            decoration: InputDecoration(labelText: _type == 'email' ? 'Email' : 'Login'),
          ),
          PasswordField(controller: _password, label: 'Password'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
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
                        showApiError(context, e);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _busy = false);
                      }
                    }
                  },
            child: const Text('Sign in'),
          ),
          TextButton(onPressed: () => context.push('/register'), child: const Text('Create account')),
          TextButton(onPressed: () => context.push('/forgot'), child: const Text('Forgot password')),
          TextButton(onPressed: () => context.push('/verify'), child: const Text('I have a verification code')),
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
    return Scaffold(
      appBar: buildAppBar(context, 'Register'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _login,
            decoration: const InputDecoration(labelText: 'Login'),
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          PasswordField(controller: _password, label: 'Password (12+ characters)'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
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
                        showApiError(context, e);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _busy = false);
                      }
                    }
                  },
            child: const Text('Register'),
          ),
          TextButton(
            onPressed: () => popOrGo(context, '/login'),
            child: const Text('Already have an account'),
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
    return Scaffold(
      appBar: buildAppBar(context, 'Check your email'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('We sent a 6-digit code to ${widget.email}. Open MailHog at http://localhost:8025 locally.'),
          const SizedBox(height: 16),
          CodeField(controller: _code),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.api.verify(_code.text.trim());
                      if (!context.mounted) {
                        return;
                      }
                      context.go('/home');
                    } catch (e) {
                      if (context.mounted) {
                        showApiError(context, e);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _busy = false);
                      }
                    }
                  },
            child: const Text('Confirm'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await widget.api.resend(widget.email);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('If the account exists, another email was sent.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  showApiError(context, e);
                }
              }
            },
            child: const Text('Resend'),
          ),
          TextButton(onPressed: () => popOrGo(context, '/login'), child: const Text('Back to sign in')),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context, 'Forgot password'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.api.forgot(_email.text);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('If the email is registered, a message was sent.')),
                        );
                        context.push('/reset');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showApiError(context, e);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _busy = false);
                      }
                    }
                  },
            child: const Text('Send reset email'),
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
    return Scaffold(
      appBar: buildAppBar(context, widget.title),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CodeField(controller: _code),
          if (widget.requirePassword)
            PasswordField(controller: _password, label: 'New password'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
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
                        showApiError(context, e);
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _busy = false);
                      }
                    }
                  },
            child: Text(widget.submitLabel),
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
    return Scaffold(
      appBar: buildAppBar(
        context,
        'Home',
        actions: [
          IconButton(onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _error != null
            ? Text(_error!)
            : _user == null
                ? const CircularProgressIndicator()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Catalog will be in sprint 02.'),
                      const SizedBox(height: 12),
                      Text('Login: ${_user!.login ?? '—'}'),
                      Text('Email: ${_user!.email ?? '—'}'),
                      Text('Role: ${_user!.role}'),
                      Text('Email verified: ${_user!.emailVerifiedAt ?? 'no'}'),
                    ],
                  ),
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
  String? _hubStatus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context, 'Settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Bind missing identifier (requires current password)'),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: _login, decoration: const InputDecoration(labelText: 'Login')),
          PasswordField(controller: _password, label: 'Current password'),
          FilledButton(
            onPressed: () async {
              try {
                await widget.api.bindEmail(_email.text, _password.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Check email for a 6-digit code.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  showApiError(context, e);
                }
              }
            },
            child: const Text('Bind email'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await widget.api.bindLogin(_login.text, _password.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login bound.')));
                }
              } catch (e) {
                if (context.mounted) {
                  showApiError(context, e);
                }
              }
            },
            child: const Text('Bind login'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              final token = await widget.api.accessToken();
              if (token == null) {
                setState(() => _hubStatus = 'no access token');
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
                setState(() => _hubStatus = 'connected');
                await hub.stop();
              } catch (e) {
                setState(() => _hubStatus = 'failed: $e');
              }
            },
            child: const Text('Check SignalR hub'),
          ),
          if (_hubStatus != null) Text(_hubStatus!),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () async {
              await widget.api.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
