import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/debug_flags.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/common.dart';
import '../../settings/presentation/app_settings.dart';
import 'check_session.dart';
import 'result_view.dart';

/// Find → confirm size → download → scan → result, for one list.
class CheckScreen extends ConsumerStatefulWidget {
  const CheckScreen({super.key, required this.request});
  final CheckRequest request;

  @override
  ConsumerState<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends ConsumerState<CheckScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(checkSessionProvider.notifier).prepare(widget.request),
    );
  }

  Future<bool> _confirmLeave() async {
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Stop checking?'),
        content: const Text(
          'The download will be cancelled and nothing will be saved.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final CheckSessionState s = ref.watch(checkSessionProvider);
    if (screenshotTour && s.phase == CheckPhase.ready) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) ref.read(checkSessionProvider.notifier).start();
      });
    }
    final bool sample = ref.watch(sampleModeProvider);
    final String title = switch (widget.request.kind) {
      CheckKind.draw => 'Check a draw',
      CheckKind.unclaimedAll => 'Unclaimed prizes',
      CheckKind.unclaimedSingle => 'Unclaimed prizes',
    };
    return PopScope(
      canPop: !s.isRunning,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) {
          if (s.phase == CheckPhase.ready) {
            // A declarative route change (router.go) invokes this while the
            // Navigator is rebuilding, when providers can't be modified, and
            // this State is about to be disposed: reset after the frame.
            final CheckSessionController ctrl = ref.read(
              checkSessionProvider.notifier,
            );
            Future<void>.microtask(ctrl.reset);
          }
          return;
        }
        if (await _confirmLeave() && context.mounted) {
          ref.read(checkSessionProvider.notifier).cancel();
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Column(
          children: <Widget>[
            if (sample) const SampleBanner(),
            Expanded(
              child: s.phase == CheckPhase.done && s.record != null
                  ? ResultView(record: s.record!)
                  : PageList(children: <Widget>[_body(context, s, sample)]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CheckSessionState s, bool sample) {
    final ThemeData t = Theme.of(context);
    final CheckSessionController ctrl = ref.read(checkSessionProvider.notifier);
    switch (s.phase) {
      case CheckPhase.idle:
      case CheckPhase.preparing:
        return _Working(
          title: sample
              ? 'Opening the sample list…'
              : 'Looking up NS&I\'s downloads page…',
          progress: null,
          onCancel: ctrl.cancel,
        );
      case CheckPhase.ready:
        final String size = s.sizeBytes == null
            ? 'an unknown size'
            : megabytes(s.sizeBytes!);
        final bool unclaimed = s.request?.kind != CheckKind.draw;
        return SectionCard(
          title: s.list!.label,
          icon: unclaimed ? Icons.manage_search : Icons.emoji_events_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                unclaimed
                    ? 'This is NS&I\'s list of prizes that were won 18 '
                          'months or more ago and haven\'t been claimed.'
                    : 'NS&I\'s full list of winning bond numbers for this '
                          'draw.',
                style: t.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              _Fact(
                icon: Icons.download_outlined,
                text: 'Download size: $size',
              ),
              if (!sample)
                const _Fact(
                  icon: Icons.wifi,
                  text: 'Wi-Fi recommended. This is a large file.',
                ),
              _Fact(
                icon: Icons.lock_outline,
                text: sample
                    ? 'Sample list bundled with the app; nothing is '
                          'downloaded.'
                    : 'Downloaded straight from nsandi.com to this '
                          '${deviceNoun(context)}, checked here, then '
                          'deleted. Your numbers never leave your '
                          '${deviceNoun(context)}.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: ctrl.start,
                icon: const Icon(Icons.search),
                label: Text(sample ? 'Check the sample' : 'Download and check'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Not now'),
              ),
            ],
          ),
        );
      case CheckPhase.downloading:
        final int? size = s.sizeBytes;
        return _Working(
          title: sample ? 'Loading the sample list…' : 'Downloading from NS&I…',
          detail: size == null
              ? '${(s.progress * 100).round()}%'
              : '${megabytes((size * s.progress).round())} of ${megabytes(size)}',
          progress: s.progress,
          onCancel: ctrl.cancel,
        );
      case CheckPhase.scanning:
        return _Working(
          title: 'Checking every winning number against yours…',
          detail: '${(s.progress * 100).round()}%',
          progress: s.progress,
          onCancel: ctrl.cancel,
        );
      case CheckPhase.done:
        return const SizedBox.shrink();
      case CheckPhase.failed:
        return MessageState(
          icon: Icons.cloud_off_outlined,
          title: 'That didn\'t work',
          body: s.error ?? 'Something went wrong.',
          actions: <Widget>[
            FilledButton(
              onPressed: () => ctrl.prepare(s.request ?? widget.request),
              child: const Text('Try again'),
            ),
            if (s.layoutChanged)
              OutlinedButton.icon(
                onPressed: () =>
                    openUrl(context, AppConstants.nsiDownloadsPage),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open NS&I\'s page'),
              ),
          ],
        );
      case CheckPhase.cancelled:
        return MessageState(
          icon: Icons.stop_circle_outlined,
          title: 'Check stopped',
          body:
              'Nothing was saved, and any part-downloaded file has been '
              'deleted.',
          actions: <Widget>[
            FilledButton(
              onPressed: () => ctrl.prepare(s.request ?? widget.request),
              child: const Text('Start again'),
            ),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Close'),
            ),
          ],
        );
    }
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    ),
  );
}

class _Working extends StatelessWidget {
  const _Working({
    required this.title,
    required this.progress,
    required this.onCancel,
    this.detail,
  });

  final String title;
  final String? detail;

  /// Null for an indeterminate wait.
  final double? progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: t.textTheme.titleLarge),
          const SizedBox(height: 20),
          Semantics(
            label: title,
            value: progress == null ? null : '${(progress! * 100).round()}%',
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          if (detail != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(detail!, style: t.textTheme.bodyLarge),
          ],
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}
