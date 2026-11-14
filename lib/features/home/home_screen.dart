import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/calendar/results_calendar.dart';
import '../../core/constants/app_constants.dart';
import '../../shared/widgets/common.dart';
import '../bonds/domain/holder.dart';
import '../bonds/presentation/holders_controller.dart';
import '../draws/data/draw_source.dart';
import '../draws/data/nsi_index.dart';
import '../draws/domain/check_models.dart';
import '../draws/presentation/check_session.dart';
import '../draws/presentation/records_controller.dart';
import '../purchases/presentation/purchase_controller.dart';
import '../reminders/reminders_controller.dart';
import '../settings/presentation/app_settings.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Holder> holders = ref.watch(holdersProvider);
    final int bonds = uniqueBondCount(holders);
    final ThemeData t = Theme.of(context);
    final DateTime next = ResultsCalendar.nextResultsDay(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: PageList(
        children: <Widget>[
          _NextResults(next: next, bonds: bonds, holders: holders.length),
          const SizedBox(height: 16),
          if (bonds == 0)
            SectionCard(
              title: 'Add your bond numbers',
              icon: Icons.add_circle_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Copy the bond numbers from an NS&I statement or old paper '
                    'certificates once. Then each month, check them against '
                    'the winners in a tap.',
                    style: t.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.go('/bonds'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add bond numbers'),
                  ),
                ],
              ),
            )
          else
            const _LatestDrawCard(),
          const SizedBox(height: 16),
          const _ReminderCard(),
          const SizedBox(height: 16),
          if (bonds > 0) ...<Widget>[
            const _EarlierDraws(),
            const SizedBox(height: 16),
          ],
          const InfoNote(AppConstants.independenceNotice),
        ],
      ),
    );
  }
}

class _NextResults extends StatelessWidget {
  const _NextResults({
    required this.next,
    required this.bonds,
    required this.holders,
  });
  final DateTime next;
  final int bonds;
  final int holders;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final int days = next.difference(today).inDays;
    final String when = days == 0
        ? 'today'
        : days == 1
        ? 'tomorrow'
        : 'in $days days';
    return Card(
      color: t.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Next results expected $when',
              style: t.textTheme.titleLarge?.copyWith(
                color: t.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('EEEE d MMMM y').format(next),
              style: t.textTheme.bodyLarge?.copyWith(
                color: t.colorScheme.onPrimary,
              ),
            ),
            if (bonds > 0) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                '${countLabel(bonds)} bonds (${gbp(bonds)}) across '
                '$holders ${holders == 1 ? 'holder' : 'holders'}',
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The newest stored draw result, or the button to run one.
class _LatestDrawCard extends ConsumerWidget {
  const _LatestDrawCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final List<CheckRecord> history = ref.watch(drawHistoryProvider);
    final List<Holder> holders = ref.watch(holdersProvider);
    final NsiIndex? index = ref.watch(indexProvider).value;
    final String fp = holdingsFingerprint(holders);
    final String? latestId = index?.latest?.id;
    final CheckRecord? last = history.isEmpty ? null : history.first;
    // Only call a stored result "latest" when it is for NS&I's newest list,
    // or we haven't asked NS&I yet.
    final bool lastIsLatest =
        last != null && (latestId == null || last.listId == latestId);
    final bool stale = last != null && last.fingerprint != fp;
    final bool sample = ref.watch(sampleModeProvider);

    return SectionCard(
      title: lastIsLatest ? '${last.label} draw' : 'Latest draw',
      icon: Icons.emoji_events_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (lastIsLatest && !stale) ...<Widget>[
            Text(
              last.hasWins
                  ? 'You have ${last.prizeCount} '
                        '${last.prizeCount == 1 ? 'prize' : 'prizes'} '
                        'worth ${gbp(last.totalWon)}.'
                  : 'No prizes for your bonds in this draw.',
              style: t.textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Checked ${DateFormat('d MMM y, HH:mm').format(last.checkedAt.toLocal())}',
              style: t.textTheme.bodyMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.push('/result/${last.listId}'),
              child: const Text('See the details'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push('/check/draw/latest'),
              child: const Text('Look for a newer draw'),
            ),
          ] else ...<Widget>[
            Text(
              stale && lastIsLatest
                  ? 'Your bonds have changed since you last checked. Check '
                        'again to include them.'
                  : sample
                  ? 'Run a check against the bundled sample list to see how '
                        'Bondbell works. Nothing is downloaded.'
                  : 'Download NS&I\'s latest winning numbers and check all '
                        'your bonds on this ${deviceNoun(context)}.',
              style: t.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/check/draw/latest'),
              icon: const Icon(Icons.search),
              label: const Text('Check the latest draw'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool on = ref.watch(remindersEnabledProvider);
    if (on) return const SizedBox.shrink();
    final ThemeData t = Theme.of(context);
    return SectionCard(
      title: 'Remind me on results day',
      icon: Icons.notifications_active_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Get one notification a month, at 9am on the day new results '
            'are due. Nothing else.',
            style: t.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => enableReminders(context, ref),
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('Turn on reminders'),
          ),
        ],
      ),
    );
  }
}

/// NS&I keeps about six months of lists online; earlier months are Pro.
class _EarlierDraws extends ConsumerWidget {
  const _EarlierDraws();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final bool pro = ref.watch(isProProvider);
    final AsyncValue<NsiIndex?> index = ref.watch(indexProvider);
    final Map<String, CheckRecord> records = ref.watch(recordsProvider);
    final String fp = holdingsFingerprint(ref.watch(holdersProvider));

    if (!pro) {
      return SectionCard(
        title: 'Earlier draws',
        icon: Icons.history,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'NS&I publishes the last six months of winning numbers. With '
              'Bondbell Pro you can check any of them, for example if you '
              'missed a month or just added a relative\'s bonds.',
              style: t.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.push('/pro'),
              child: const Text('About Bondbell Pro'),
            ),
          ],
        ),
      );
    }

    final NsiIndex? data = index.value;
    final List<RemoteList> earlier = data == null
        ? const <RemoteList>[]
        : data.draws.skip(1).toList();
    return SectionCard(
      title: 'Earlier draws',
      icon: Icons.history,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (index.isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (index.hasError) ...<Widget>[
            Text(
              index.error is SourceException
                  ? (index.error! as SourceException).message
                  : 'Couldn\'t load NS&I\'s list of draws.',
              style: t.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.read(indexProvider.notifier).refresh(),
              child: const Text('Try again'),
            ),
          ] else if (data == null) ...<Widget>[
            Text(
              'See which months NS&I currently publishes and check any of '
              'them.',
              style: t.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref
                  .read(indexProvider.notifier)
                  .refresh()
                  .catchError(
                    (Object _) =>
                        const NsiIndex(draws: <RemoteList>[], unclaimed: null),
                  ),
              child: const Text('Show available draws'),
            ),
          ] else if (earlier.isEmpty)
            Text(
              data.draws.length == 1 && ref.watch(sampleModeProvider)
                  ? 'The sample has a single draw. With your own bonds, '
                        'NS&I lists about six months to choose from.'
                  : 'No earlier draws are listed right now.',
              style: t.textTheme.bodyLarge,
            )
          else
            for (final RemoteList l in earlier)
              _DrawRow(list: l, record: records[l.id], fingerprint: fp),
        ],
      ),
    );
  }
}

class _DrawRow extends StatelessWidget {
  const _DrawRow({
    required this.list,
    required this.record,
    required this.fingerprint,
  });
  final RemoteList list;
  final CheckRecord? record;
  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    final CheckRecord? r = record;
    final bool fresh = r != null && r.fingerprint == fingerprint;
    final String status = r == null
        ? 'Not checked yet'
        : !fresh
        ? 'Bonds changed since checked'
        : r.hasWins
        ? '${gbp(r.totalWon)} won'
        : 'No prizes';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(list.label),
      subtitle: Text(status),
      trailing: fresh
          ? const Icon(Icons.chevron_right)
          : const Icon(Icons.download_outlined),
      onTap: () => fresh
          ? context.push('/result/${list.id}')
          : context.push('/check/draw/${list.id}'),
    );
  }
}
