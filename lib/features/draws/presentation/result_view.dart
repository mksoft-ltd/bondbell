import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/common.dart';
import '../../bonds/domain/holder.dart';
import '../../bonds/presentation/holders_controller.dart';
import '../../purchases/presentation/tip_jar.dart';
import '../../settings/presentation/app_settings.dart';
import '../domain/check_models.dart';

/// The outcome of one check: wins grouped by holder, or a clear no-win
/// state, always with "confirm with NS&I" and how to claim.
class ResultView extends ConsumerWidget {
  const ResultView({super.key, required this.record});
  final CheckRecord record;

  bool get _unclaimed => record.listId.startsWith('unclaimed');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final bool sample = ref.watch(sampleModeProvider);
    final List<Holder> holders = ref.watch(holdersProvider);
    final bool stale =
        record.singleNumber == null &&
        record.fingerprint != holdingsFingerprint(holders);

    final Map<String, List<Win>> byHolder = <String, List<Win>>{};
    for (final Win w in record.wins) {
      (byHolder[w.holderName] ??= <Win>[]).add(w);
    }

    return PageList(
      children: <Widget>[
        _Headline(record: record, unclaimed: _unclaimed),
        const SizedBox(height: 16),
        if (stale) ...<Widget>[
          const SectionCard(
            child: InfoNote(
              'Your bonds have changed since this check, so newly added '
              'numbers aren\'t included. Check again to cover them.',
              icon: Icons.update,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (!record.integrityOk) ...<Widget>[
          SectionCard(
            color: t.colorScheme.errorContainer,
            child: Text(
              'The file didn\'t add up the way NS&I\'s own totals say it '
              'should, so its layout may have changed. Please check on NS&I\'s '
              'site before relying on this result.',
              style: t.textTheme.bodyLarge?.copyWith(
                color: t.colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (final MapEntry<String, List<Win>> e
            in byHolder.entries) ...<Widget>[
          SectionCard(
            title: e.key,
            icon: Icons.person_outline,
            child: Column(
              children: <Widget>[
                for (final Win w in e.value)
                  _WinRow(win: w, alsoUnder: record.alsoListedUnder(w)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (record.hasWins) ...<Widget>[
          _HowToClaim(unclaimed: _unclaimed),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: InfoNote(
            '${AppConstants.confirmWithNsi}\n\nChecked '
            '${countLabel(record.numbersScanned)} numbers from NS&I\'s list '
            'against ${countLabel(record.bondsChecked)} of your bonds on '
            '${DateFormat('d MMMM y \'at\' HH:mm').format(record.checkedAt.toLocal())}.',
            icon: Icons.verified_user_outlined,
          ),
        ),
        if (record.hasWins && !sample) ...<Widget>[
          const SizedBox(height: 16),
          const TipJarCard(compact: true),
        ],
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.record, required this.unclaimed});
  final CheckRecord record;
  final bool unclaimed;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final bool won = record.hasWins;
    final String title = !won
        ? (unclaimed ? 'Nothing unclaimed found' : 'No prizes this time')
        : unclaimed
        ? 'Found ${record.prizeCount} unclaimed '
              '${record.prizeCount == 1 ? 'prize' : 'prizes'}'
        : 'Congratulations!';
    final String sub = !won
        ? (record.singleNumber != null
              ? '${record.singleNumber} isn\'t in ${record.label}.'
              : unclaimed
              ? 'None of your bonds are in ${record.label}.'
              : 'None of your bonds are in NS&I\'s ${record.label} winners '
                    'list. Every bond stays in the draw for next month.')
        : unclaimed
        ? 'Worth ${gbp(record.totalWon)} in total, waiting to be claimed.'
        : 'You have ${record.prizeCount} '
              '${record.prizeCount == 1 ? 'prize' : 'prizes'} worth '
              '${gbp(record.totalWon)} in the ${record.label} draw.';
    return Card(
      color: won ? t.colorScheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(
              won ? Icons.celebration_outlined : Icons.check_circle_outline,
              size: 56,
              color: won ? t.colorScheme.secondary : t.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: t.textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _WinRow extends StatelessWidget {
  const _WinRow({required this.win, required this.alsoUnder});
  final Win win;

  /// Other holders the same prize is listed under (a bond saved twice).
  final List<String> alsoUnder;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final String also = alsoUnder.isEmpty
        ? ''
        : 'Also listed under ${alsoUnder.join(' and ')}. It is one prize, '
              'counted once in the total.';
    return Semantics(
      label:
          'Bond ${win.bond.split('').join(' ')}, prize ${gbp(win.prize)}'
          '${win.anonymous ? '. Holder\'s name unknown to NS&I' : ''}'
          '${also.isEmpty ? '' : '. $also'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Bond and prize share a line when they fit; at large text sizes
            // the prize drops to its own line rather than overflowing or
            // being cut off.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 2,
              children: <Widget>[
                SelectableText(
                  win.bond,
                  style: t.textTheme.titleMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  gbp(win.prize),
                  key: ValueKey<String>('prize-${win.holderId}-${win.bond}'),
                  style: t.textTheme.titleLarge?.copyWith(
                    color: t.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            if (win.anonymous)
              Text(
                'Listed by NS&I as a prize whose holder\'s name is unknown',
                style: t.textTheme.bodySmall,
              ),
            if (also.isNotEmpty) Text(also, style: t.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _HowToClaim extends StatelessWidget {
  const _HowToClaim({required this.unclaimed});
  final bool unclaimed;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return SectionCard(
      title: 'How to claim',
      icon: Icons.help_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            unclaimed
                ? 'Contact NS&I to claim. Have the bond number and the '
                      'holder\'s details ready (for old certificates, the '
                      'name and address they were bought under). If the '
                      'holder has died, NS&I can explain what the family '
                      'needs to provide.'
                : 'If NS&I has the holder\'s bank details, prizes are usually '
                      'paid in automatically, or reinvested if that was '
                      'chosen. Otherwise NS&I writes to the holder. For old '
                      'paper bonds, or if the holder has moved, contact NS&I.',
            style: t.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => openUrl(context, AppConstants.nsiContactPage),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Contact NS&I'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    openUrl(context, AppConstants.nsiPrizeCheckerPage),
                icon: const Icon(Icons.open_in_new),
                label: const Text('NS&I prize checker'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
