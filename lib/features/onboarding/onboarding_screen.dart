import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/widgets/common.dart';
import '../settings/presentation/app_settings.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pages = PageController();
  int _page = 0;

  static List<({IconData icon, String title, String body})> _steps(
    String device,
  ) => <({IconData icon, String title, String body})>[
    (
      icon: Icons.notifications_active_outlined,
      title: 'Check your bonds without logging in',
      body:
          'Save your Premium Bond numbers once, from a statement or old '
          'paper certificates. Each month Bondbell checks them against '
          'the winning numbers for you. It works for a relative\'s bonds '
          'too.',
    ),
    (
      icon: Icons.lock_outline,
      title: 'Your numbers stay on this $device',
      body:
          'When you check, Bondbell downloads NS&I\'s public list '
          'straight from nsandi.com and compares it here. No account, no '
          'server of ours, no tracking.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool sample}) async {
    await ref
        .read(appSettingsProvider.notifier)
        .completeOnboarding(sampleMode: sample);
    if (!mounted) return;
    context.go(sample ? '/home' : '/bonds');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final List<({IconData icon, String title, String body})> steps = _steps(
      deviceNoun(context),
    );
    final int count = steps.length + 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (int p) => setState(() => _page = p),
                children: <Widget>[
                  for (final s in steps)
                    _Page(icon: s.icon, title: s.title, body: s.body),
                  _Page(
                    icon: Icons.check_circle_outline,
                    title: 'Ready when you are',
                    body:
                        'Add your bond numbers, or try Bondbell first with '
                        'made-up sample numbers to see how a check works.',
                    footer: const InfoNote(AppConstants.independenceNotice),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ContentWidth(
                maxWidth: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      label: 'Page ${_page + 1} of $count',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          for (int i = 0; i < count; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.all(4),
                              width: i == _page ? 24 : 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? t.colorScheme.primary
                                    : t.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_page < count - 1)
                      FilledButton(
                        onPressed: () => _pages.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                        child: const Text('Next'),
                      )
                    else ...<Widget>[
                      FilledButton(
                        onPressed: () => _finish(sample: false),
                        child: const Text('Add my bond numbers'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => _finish(sample: true),
                        child: const Text('Try with sample numbers'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.footer,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    // Vertically centred so a tall iPad screen reads as a composed page,
    // still scrollable at large text sizes.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) =>
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 72),
              child: Center(
                child: ContentWidth(
                  maxWidth: 560,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: t.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          icon,
                          size: 48,
                          color: t.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Semantics(
                        header: true,
                        child: Text(title, style: t.textTheme.headlineMedium),
                      ),
                      const SizedBox(height: 16),
                      Text(body, style: t.textTheme.bodyLarge),
                      if (footer != null) ...<Widget>[
                        const SizedBox(height: 28),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }
}
