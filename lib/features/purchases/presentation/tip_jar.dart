import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/common.dart';
import 'purchase_controller.dart';

/// "Say thanks" — consumable tips that unlock nothing, and say so.
class TipJarCard extends ConsumerWidget {
  const TipJarCard({super.key, this.compact = false});

  /// On a result screen: one quiet card under the result, never blocking it.
  final bool compact;

  static const List<({String id, String name})> _tips =
      <({String id, String name})>[
        (id: AppConstants.tipSmallId, name: 'Small tip'),
        (id: AppConstants.tipMediumId, name: 'Medium tip'),
        (id: AppConstants.tipLargeId, name: 'Large tip'),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final PurchaseState s = ref.watch(purchaseControllerProvider);
    final bool any = _tips.any((e) => s.prices[e.id] != null);
    return SectionCard(
      title: compact ? 'Glad Bondbell helped?' : 'Tip jar',
      icon: Icons.volunteer_activism_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'If you\'d like to say thank you, you can leave a tip. Tips '
            'don\'t unlock anything. They just help a small independent '
            'developer keep the app going.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          if (!any)
            Text(
              s.storeAvailable
                  ? 'Tips aren\'t available right now.'
                  : 'The app store isn\'t available right now.',
              style: t.textTheme.bodyMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final ({String id, String name}) tip in _tips)
                  if (s.prices[tip.id] != null)
                    OutlinedButton(
                      onPressed: s.busy
                          ? null
                          : () => ref
                                .read(purchaseControllerProvider.notifier)
                                .tip(tip.id),
                      child: Text('${tip.name} · ${s.prices[tip.id]}'),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}
