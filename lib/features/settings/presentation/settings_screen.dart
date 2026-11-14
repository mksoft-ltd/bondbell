import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/local_store.dart';
import '../../../shared/widgets/common.dart';
import '../../bonds/presentation/holders_controller.dart';
import '../../draws/presentation/check_session.dart';
import '../../draws/presentation/records_controller.dart';
import '../../purchases/presentation/purchase_controller.dart';
import '../../purchases/presentation/tip_jar.dart';
import '../../reminders/reminders_controller.dart';
import 'app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final AppSettings settings = ref.watch(appSettingsProvider);
    final bool pro = ref.watch(isProProvider);
    final PurchaseState purchases = ref.watch(purchaseControllerProvider);
    final String? price = purchases.prices[AppConstants.proProductId];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageList(
        children: <Widget>[
          SectionCard(
            title: pro ? 'Bondbell Pro: unlocked' : 'Bondbell Pro',
            icon: Icons.workspace_premium_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  pro
                      ? 'Unlimited holders, earlier draws, full unclaimed '
                            'search, history and stats. Thank you!'
                      : 'Unlimited holders, earlier draws, full unclaimed '
                            'search, history and stats. One purchase'
                            '${price == null ? '' : ', $price'}, no '
                            'subscription.',
                  style: t.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                if (!pro)
                  FilledButton(
                    onPressed: () => context.push('/pro'),
                    child: const Text('See what Pro adds'),
                  ),
                TextButton(
                  onPressed: purchases.busy
                      ? null
                      : ref.read(purchaseControllerProvider.notifier).restore,
                  child: const Text('Restore purchases'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text('Results-day reminder'),
                  subtitle: const Text(
                    'One notification at 9am on the day new results are due',
                  ),
                  value: settings.remindersEnabled,
                  onChanged: (bool on) => on
                      ? enableReminders(context, ref)
                      : disableReminders(ref),
                ),
                const Divider(indent: 20, endIndent: 20),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text('Sample mode'),
                  subtitle: const Text(
                    'Try the whole app with made-up numbers. Your own bonds '
                    'are kept separately and untouched.',
                  ),
                  value: settings.sampleMode,
                  onChanged: (bool on) async {
                    ref.read(checkSessionProvider.notifier).reset();
                    await ref
                        .read(appSettingsProvider.notifier)
                        .setSampleMode(on);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const TipJarCard(),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: <Widget>[
                _LinkTile(
                  icon: Icons.info_outline,
                  title: 'About Bondbell',
                  onTap: () => context.push('/about'),
                ),
                const Divider(indent: 20, endIndent: 20),
                _LinkTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  external: true,
                  onTap: () => openUrl(context, AppConstants.privacyPolicyUrl),
                ),
                const Divider(indent: 20, endIndent: 20),
                _LinkTile(
                  icon: Icons.support_outlined,
                  title: 'Help and support',
                  external: true,
                  onTap: () => openUrl(context, AppConstants.supportUrl),
                ),
                const Divider(indent: 20, endIndent: 20),
                _LinkTile(
                  icon: Icons.open_in_new,
                  title: 'NS&I\'s winning numbers page',
                  external: true,
                  onTap: () =>
                      openUrl(context, AppConstants.nsiDownloadsPage),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: _LinkTile(
              icon: Icons.delete_forever_outlined,
              title: 'Delete all my data',
              onTap: () => _deleteAll(context, ref),
            ),
          ),
          const SizedBox(height: 16),
          const InfoNote(AppConstants.independenceNotice),
        ],
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Delete all your data?'),
        content: const Text(
          'This removes every holder, bond number and saved result from '
          'this phone. It can\'t be undone. Purchases aren\'t affected and '
          'can be restored.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(checkSessionProvider.notifier).reset();
    final LocalStore store = ref.read(localStoreProvider);
    await store.clearPrefix('real.');
    await store.clearPrefix('sample.');
    ref.invalidate(holdersProvider);
    ref.invalidate(recordsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All your data has been deleted.')),
      );
    }
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.external = false,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool external;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    leading: Icon(icon),
    title: Text(title),
    trailing: Icon(external ? Icons.open_in_new : Icons.chevron_right),
    onTap: onTap,
  );
}
