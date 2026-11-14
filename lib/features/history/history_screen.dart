import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/common.dart';
import '../bonds/domain/holder.dart';
import '../bonds/presentation/holders_controller.dart';
import '../draws/domain/check_models.dart';
import '../draws/presentation/records_controller.dart';
import '../purchases/presentation/purchase_controller.dart';

/// Totals across the draws the user has checked. Pure, so tests pin it.
class WinStats {
  WinStats(List<CheckRecord> draws, this.heldNow)
    : drawsChecked = draws.length,
      prizes = draws.fold(0, (int a, CheckRecord r) => a + r.prizeCount),
      totalWon = draws.fold(0, (int a, CheckRecord r) => a + r.totalWon);

  final int drawsChecked;
  final int prizes;
  final int totalWon;
  final int heldNow;

  /// Prizes over the checked draws, scaled to a year, as a percentage of
  /// what is held now. Information only: holdings may have changed between
  /// draws, and past prizes say nothing about future ones.
  double? get annualisedPercent {
    if (drawsChecked == 0 || heldNow == 0) return null;
    return totalWon / heldNow * (12 / drawsChecked) * 100;
  }
}

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final bool pro = ref.watch(proFeaturesProvider);
    if (!pro) {
      return Scaffold(
        appBar: AppBar(title: const Text('History')),
        body: PageList(
          children: <Widget>[
            MessageState(
              icon: Icons.insights_outlined,
              title: 'History and stats are part of Pro',
              body:
                  'Bondbell Pro keeps every result you check, adds up what '
                  'you\'ve won, and shows how your prizes compare with the '
                  'amount you hold. Your latest draw result is always on the '
                  'Check tab, free.',
              actions: <Widget>[
                FilledButton(
                  onPressed: () => context.push('/pro'),
                  child: const Text('About Bondbell Pro'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final List<CheckRecord> draws = ref.watch(drawHistoryProvider);
    final List<Holder> holders = ref.watch(holdersProvider);
    final int held = uniqueBondCount(holders);
    final WinStats stats = WinStats(draws, held);
    final double? pct = stats.annualisedPercent;

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: PageList(
        children: <Widget>[
          if (draws.isEmpty)
            const MessageState(
              icon: Icons.history,
              title: 'Nothing checked yet',
              body: 'Results appear here each time you check a draw.',
            )
          else ...<Widget>[
            LayoutBuilder(
              builder: (BuildContext c, BoxConstraints box) {
                final List<Widget> tiles = <Widget>[
                  _Stat(label: 'Total won', value: gbp(stats.totalWon)),
                  _Stat(label: 'Prizes', value: countLabel(stats.prizes)),
                  _Stat(
                    label: 'Draws checked',
                    value: countLabel(stats.drawsChecked),
                  ),
                  _Stat(label: 'Held now', value: gbp(held)),
                ];
                final int perRow = box.maxWidth >= 560 ? 4 : 2;
                final double w = (box.maxWidth - 12 * (perRow - 1)) / perRow;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final Widget tile in tiles)
                      SizedBox(width: w, child: tile),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (pct != null)
              SectionCard(
                title: 'Your prizes as a yearly rate',
                icon: Icons.percent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${pct.toStringAsFixed(2)}% a year',
                      style: t.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Over the ${stats.drawsChecked} '
                      '${stats.drawsChecked == 1 ? 'draw' : 'draws'} you\'ve '
                      'checked, your prizes added up to the equivalent of '
                      'this yearly rate on the ${gbp(held)} you hold now.',
                      style: t.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    const InfoNote(
                      'For information only, not financial advice. It uses '
                      'today\'s holding for every month, and past prizes '
                      'don\'t predict future ones. NS&I sets the prize fund '
                      'rate, which changes from time to time.',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < draws.length; i++) ...<Widget>[
                    if (i > 0) const Divider(indent: 20, endIndent: 20),
                    _HistoryRow(
                      record: draws[i],
                      onTap: () => context.push('/result/${draws[i].listId}'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One checked draw. The amount sits beside the month when there is room
/// and drops below it at large text sizes, so neither is ever squeezed.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record, required this.onTap});
  final CheckRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final String prizes = record.hasWins
        ? '${record.prizeCount} ${record.prizeCount == 1 ? 'prize' : 'prizes'}'
        : 'No prizes';
    return Semantics(
      button: true,
      label: '${record.label}, $prizes, ${gbp(record.totalWon)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      // Full width, so spaceBetween puts the amount at the right edge.
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        children: <Widget>[
                          Text(record.label, style: t.textTheme.titleMedium),
                          Text(
                            gbp(record.totalWon),
                            style: t.textTheme.titleMedium?.copyWith(
                              color: record.hasWins
                                  ? t.colorScheme.secondary
                                  : t.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prizes,
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: t.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: t.textTheme.bodyMedium),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: t.textTheme.headlineSmall),
            ),
          ],
        ),
      ),
    );
  }
}
