import 'package:flutter/material.dart';
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
        builder: (_, state) => TokenScreen(
          api: api,
          title: 'Verify email',
          initialToken: state.uri.queryParameters['token'] ?? '',
          submitLabel: 'Confirm',
          onSubmit: (token, _) => api.verify(token),
          onDone: (context) => context.go('/login'),
        ),
      ),
      GoRoute(path: '/forgot', builder: (_, _) => ForgotScreen(api: api)),
      GoRoute(
        path: '/reset',
        builder: (_, state) => TokenScreen(
          api: api,
          title: 'Reset password',
          initialToken: state.uri.queryParameters['token'] ?? '',
          submitLabel: 'Change password',
          requirePassword: true,
          onSubmit: (token, password) =>
              api.reset(token: token, newPassword: password ?? ''),
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

void showApiError(BuildContext context, Object error) {
  final text = error is ApiException ? '${error.code}: ${error.title}' : error.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
      appBar: AppBar(title: const Text('Sign in')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IdentifierTypeField(value: _type, onChanged: (v) => setState(() => _type = v)),
          const SizedBox(height: 16),
          TextField(
            controller: _id,
            decoration: InputDecoration(labelText: _type == 'email' ? 'Email' : 'Login'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
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
          TextButton(onPressed: () => context.go('/register'), child: const Text('Create account')),
          TextButton(onPressed: () => context.go('/forgot'), child: const Text('Forgot password')),
          TextButton(onPressed: () => context.go('/verify'), child: const Text('I have a verification token')),
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
  final _id = TextEditingController();
  final _password = TextEditingController();
  String _type = 'email';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IdentifierTypeField(value: _type, onChanged: (v) => setState(() => _type = v)),
          const SizedBox(height: 16),
          TextField(
            controller: _id,
            decoration: InputDecoration(labelText: _type == 'email' ? 'Email' : 'Login'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password (12+ characters)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      final session = await widget.api.register(
                        identifierType: _type,
                        identifier: _id.text,
                        password: _password.text,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      if (session == null) {
                        context.go('/check-email?email=${Uri.encodeComponent(_id.text)}');
                      } else {
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
            child: const Text('Register'),
          ),
          TextButton(onPressed: () => context.go('/login'), child: const Text('Already have an account')),
        ],
      ),
    );
  }
}

class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({super.key, required this.api, required this.email});
  final ApiClient api;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check your email')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('We sent a confirmation link to $email. Open MailHog at http://localhost:8025 locally.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => context.go('/verify'), child: const Text('Enter token')),
            TextButton(
              onPressed: () async {
                try {
                  await api.resend(email);
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
            TextButton(onPressed: () => context.go('/login'), child: const Text('Back to sign in')),
          ],
        ),
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
      appBar: AppBar(title: const Text('Forgot password')),
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
                        context.go('/reset');
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

class TokenScreen extends StatefulWidget {
  const TokenScreen({
    super.key,
    required this.api,
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    required this.onDone,
    this.initialToken = '',
    this.requirePassword = false,
  });

  final ApiClient api;
  final String title;
  final String submitLabel;
  final String initialToken;
  final bool requirePassword;
  final Future<void> Function(String token, String? password) onSubmit;
  final void Function(BuildContext context) onDone;

  @override
  State<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends State<TokenScreen> {
  late final TextEditingController _token;
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.initialToken);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _token, decoration: const InputDecoration(labelText: 'Token from email')),
          if (widget.requirePassword)
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.onSubmit(
                        _token.text.trim(),
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
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(onPressed: () => context.go('/settings'), icon: const Icon(Icons.settings)),
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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Bind missing identifier (requires current password)'),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: _login, decoration: const InputDecoration(labelText: 'Login')),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await widget.api.bindEmail(_email.text, _password.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Check email to confirm.')),
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
