import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/bonds/domain/bond_number.dart';
import '../features/bonds/presentation/bonds_screen.dart';
import '../features/bonds/presentation/holder_screen.dart';
import '../features/draws/presentation/check_screen.dart';
import '../features/draws/presentation/check_session.dart';
import '../features/draws/presentation/result_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/purchases/presentation/pro_screen.dart';
import '../features/settings/presentation/about_screen.dart';
import '../features/settings/presentation/app_settings.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/unclaimed/unclaimed_screen.dart';
import 'shell.dart';

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final ValueNotifier<bool> onboarded = ValueNotifier<bool>(
    ref.read(appSettingsProvider).onboarded,
  );
  ref.listen<bool>(
    appSettingsProvider.select((AppSettings s) => s.onboarded),
    (bool? _, bool next) => onboarded.value = next,
  );
  ref.onDispose(onboarded.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: onboarded,
    redirect: (BuildContext context, GoRouterState state) {
      final bool atOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded.value && !atOnboarding) return '/onboarding';
      if (onboarded.value && atOnboarding) return '/home';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, StatefulNavigationShell shell) =>
            AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/bonds', builder: (_, _) => const BondsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/unclaimed',
                builder: (_, _) => const UnclaimedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/history',
                builder: (_, _) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/holder/:id',
        builder: (_, GoRouterState s) =>
            HolderScreen(holderId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/check/draw/:id',
        builder: (_, GoRouterState s) => CheckScreen(
          request: CheckRequest.draw(s.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/check/unclaimed',
        builder: (_, _) =>
            const CheckScreen(request: CheckRequest.unclaimedAll()),
      ),
      GoRoute(
        path: '/check/unclaimed-single/:n',
        builder: (_, GoRouterState s) => CheckScreen(
          request: CheckRequest.unclaimedSingle(
            BondNumber.parse(s.pathParameters['n']!),
          ),
        ),
      ),
      GoRoute(
        path: '/result/:id',
        builder: (_, GoRouterState s) =>
            ResultScreen(recordId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/pro', builder: (_, _) => const ProScreen()),
      GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
    ],
  );
});
