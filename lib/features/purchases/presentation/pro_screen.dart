import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/common.dart';
import 'purchase_controller.dart';

/// What Pro adds, exactly matching what the app gates. No timers, no
/// strike-through prices, no pressure.
class ProScreen extends ConsumerWidget {
  const ProScreen({super.key});

  static const List<({IconData icon, String title, String body})> benefits =
      <({IconData icon, String title, String body})>[
        (
          icon: Icons.group_outlined,
          title: 'Unlimited holders',
          body: 'Keep bonds for a partner, children or a relative\'s old '
              'certificates side by side. Free covers one holder.',
        ),
        (
          icon: Icons.history,
          title: 'Earlier draws',
          body: 'Check any of the months NS&I still publishes (about six). '
              'Free checks the latest draw.',
        ),
        (
          icon: Icons.manage_search,
          title: 'Unclaimed search for all your bonds',
          body: 'Search NS&I\'s unclaimed list for every range in one go. '
              'Free searches one number at a time.',
        ),
        (
          icon: Icons.insights_outlined,
          title: 'History and stats',
          body: 'Every result you\'ve checked, total won, and how your prizes '
              'compare with the amount you hold.',
        ),
      ];

  /// Shown in sample mode, where these features are open on the sample
  /// data without a purchase (store reviewers can't buy).
  static const String sampleNote =
      'You\'re in sample mode, so these features are open to try on the '
      'sample data. To use them with your own bonds, unlock Pro.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final PurchaseState s = ref.watch(purchaseControllerProvider);
    final bool pro = ref.watch(isProProvider);
    final String? price = s.prices[AppConstants.proProductId];
    final PurchaseController ctrl = ref.read(
      purchaseControllerProvider.notifier,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Bondbell Pro')),
      body: PageList(
        maxWidth: 640,
        children: <Widget>[
          Text(
            pro ? 'You have Bondbell Pro' : 'Do more with Bondbell Pro',
            style: t.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            pro
                ? 'Thank you for supporting the app. Everything below is '
                      'unlocked.'
                : 'One purchase, yours for good. No subscription.',
            style: t.textTheme.bodyLarge,
          ),
          if (ref.watch(sampleOpensProProvider)) ...<Widget>[
            const SizedBox(height: 16),
            const InfoNote(ProScreen.sampleNote, icon: Icons.science_outlined),
          ],
          const SizedBox(height: 20),
          for (final b in benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(b.icon, color: t.colorScheme.primary, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(b.title, style: t.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(b.body, style: t.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (!pro) ...<Widget>[
            FilledButton(
              onPressed: s.busy || price == null ? null : ctrl.buyPro,
              child: s.busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(
                      price == null
                          ? 'Unavailable right now'
                          : 'Unlock Pro · $price',
                    ),
            ),
            if (price == null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                s.storeAvailable
                    ? 'Pro isn\'t available from the store at the moment.'
                    : 'Can\'t reach the app store. Check your connection and '
                          'try again.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium,
              ),
              TextButton(
                onPressed: ctrl.loadProducts,
                child: const Text('Try again'),
              ),
            ],
            const SizedBox(height: 8),
          ],
          TextButton(
            onPressed: s.busy ? null : ctrl.restore,
            child: const Text('Restore purchases'),
          ),
          const SizedBox(height: 16),
          const InfoNote(
            'Everything else in Bondbell stays free: checking the latest draw '
            'for one holder, single-number unclaimed searches and results-day '
            'reminders.',
          ),
        ],
      ),
    );
  }
}
