import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'account/two_factor_screens.dart';
import 'account/security_models.dart';
import 'admin/admin_screens.dart';
import 'api/api_client.dart';
import 'main.dart' show LoginScreen;
import 'theme.dart';

/// Точка входа веб-админки: `flutter run -d chrome -t lib/main_admin.dart`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AdminApp(api: ApiClient()));
}

/// Тема клиента задаёт кнопкам бесконечную минимальную ширину (`Size.fromHeight`) —
/// в строках заголовка и `ListTile` это ломает вёрстку, поэтому в админке сбрасываем её.
ThemeData _adminTheme() {
  final base = VizeTheme.data();
  ButtonStyle? compact(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 40)));
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: compact(base.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: compact(base.outlinedButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: compact(base.textButtonTheme.style)),
  );
}

class AdminApp extends StatelessWidget {
  AdminApp({super.key, required this.api});

  final ApiClient api;

  late final GoRouter _router = GoRouter(
    initialLocation: '/admin',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => LoginScreen(api: api)),
      // LoginScreen после входа переходит на /home — в админке это корень каталога.
      GoRoute(path: '/home', redirect: (_, _) => '/admin'),
      GoRoute(
        path: '/2fa',
        redirect: (_, state) => state.extra is TwoFactorChallenge ? null : '/login',
        builder: (_, state) => TwoFactorLoginScreen(api: api, challenge: state.extra! as TwoFactorChallenge),
      ),
      ShellRoute(
        builder: (_, state, child) => AdminGate(
          api: api,
          child: AdminShell(api: api, location: state.uri.path, child: child),
        ),
        routes: [
          GoRoute(path: '/admin', builder: (_, _) => AdminArtistsScreen(api: api)),
          GoRoute(
            path: '/admin/artist/:id',
            builder: (_, s) => AdminArtistScreen(api: api, id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/admin/album/:id',
            builder: (_, s) => AdminAlbumScreen(api: api, id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/admin/track/:id',
            builder: (_, s) => AdminTrackScreen(api: api, id: s.pathParameters['id']!),
          ),
          GoRoute(path: '/admin/genres', builder: (_, _) => AdminGenresScreen(api: api)),
          GoRoute(path: '/admin/trash', builder: (_, _) => AdminTrashScreen(api: api)),
          GoRoute(path: '/admin/import', builder: (_, _) => AdminImportScreen(api: api)),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Music Anti Blur · Админка',
        theme: _adminTheme(),
        routerConfig: _router,
      );
}
