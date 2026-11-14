import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

final NumberFormat _gbp = NumberFormat.currency(
  locale: 'en_GB',
  symbol: '£',
  decimalDigits: 0,
);
final NumberFormat _count = NumberFormat.decimalPattern('en_GB');

String gbp(int pounds) => _gbp.format(pounds);
String countLabel(int n) => _count.format(n);

String megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Opens [url] in the browser; reports failure in a snackbar.
Future<void> openUrl(BuildContext context, String url) async {
  final bool ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  ).catchError((Object _) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Couldn\'t open $url')),
    );
  }
}

/// Centres content and caps its width so iPad and landscape layouts read
/// as a designed column rather than a stretched phone.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 760});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      // Full width of the column, so cards line up whatever their content.
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Standard scrolling page body with consistent gutters.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.maxWidth = 760});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double gutter = width >= 600 ? 32 : 16;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
      children: <Widget>[
        for (final Widget c in children)
          ContentWidth(maxWidth: maxWidth, child: c),
      ],
    );
  }
}

/// A titled card section.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(20),
  });

  final String? title;
  final IconData? icon;
  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Card(
      color: color,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, color: t.colorScheme.primary),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title!, style: t.textTheme.titleMedium),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A quiet explanatory line with an icon.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: t.textTheme.bodyMedium?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The always-visible label in sample mode, so made-up numbers can never be
/// mistaken for real results.
class SampleBanner extends StatelessWidget {
  const SampleBanner({super.key, this.onExit});
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Sample mode. These are made-up numbers, not real results.',
      child: Material(
        color: t.colorScheme.secondaryContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.science_outlined,
                    color: t.colorScheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      'Sample mode: made-up numbers, not real results',
                      style: t.textTheme.bodyMedium?.copyWith(
                        color: t.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (onExit != null)
                  TextButton(onPressed: onExit, child: const Text('Exit')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Big centred state for empty / error screens.
class MessageState extends StatelessWidget {
  const MessageState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 56, color: t.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center, style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center, style: t.textTheme.bodyLarge),
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
