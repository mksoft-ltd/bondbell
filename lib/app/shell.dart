import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/draws/presentation/check_session.dart';
import '../features/settings/presentation/app_settings.dart';
import '../shared/widgets/common.dart';
import '../features/purchases/presentation/purchase_controller.dart';

/// Bottom navigation on phones, a navigation rail on tablets and in
/// landscape, with the sample-mode label above everything.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const List<({IconData icon, IconData selected, String label})>
  _dests = <({IconData icon, IconData selected, String label})>[
    (
      icon: Icons.notifications_none,
      selected: Icons.notifications,
      label: 'Check',
    ),
    (
      icon: Icons.confirmation_number_outlined,
      selected: Icons.confirmation_number,
      label: 'My bonds',
    ),
    (
      icon: Icons.manage_search_outlined,
      selected: Icons.manage_search,
      label: 'Unclaimed',
    ),
    (icon: Icons.insights_outlined, selected: Icons.insights, label: 'History'),
    (
      icon: Icons.settings_outlined,
      selected: Icons.settings,
      label: 'Settings',
    ),
  ];

  void _go(int i) =>
      shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool sample = ref.watch(sampleModeProvider);
    final bool wide = MediaQuery.sizeOf(context).width >= 720;
    final Widget body = Column(
      children: <Widget>[
        if (sample)
          SampleBanner(
            proOpen: ref.watch(sampleOpensProProvider),
            onExit: () async {
              ref.read(checkSessionProvider.notifier).reset();
              await ref
                  .read(appSettingsProvider.notifier)
                  .setSampleMode(false);
            },
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: sample,
            child: shell,
          ),
        ),
      ],
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.85,
                destinations: <NavigationRailDestination>[
                  for (final d in _dests)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selected),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: <NavigationDestination>[
          for (final d in _dests)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
