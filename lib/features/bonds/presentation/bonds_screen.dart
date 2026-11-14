import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/common.dart';
import '../../purchases/presentation/purchase_controller.dart';
import '../domain/holder.dart';
import 'holders_controller.dart';

class BondsScreen extends ConsumerWidget {
  const BondsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final List<Holder> holders = ref.watch(holdersProvider);
    final int total = uniqueBondCount(holders);

    return Scaffold(
      appBar: AppBar(title: const Text('My bonds')),
      floatingActionButton: holders.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => addHolderFlow(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add holder'),
            ),
      body: PageList(
        children: <Widget>[
          if (holders.isEmpty)
            MessageState(
              icon: Icons.confirmation_number_outlined,
              title: 'No bonds yet',
              body: 'Start with the person whose bonds these are, then add '
                  'their bond numbers from a statement or certificate.',
              actions: <Widget>[
                FilledButton.icon(
                  onPressed: () => addHolderFlow(context, ref),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add a holder'),
                ),
              ],
            )
          else ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'In total: ${countLabel(total)} bonds, worth ${gbp(total)}',
                style: t.textTheme.titleMedium,
              ),
            ),
            for (final Holder h in holders) ...<Widget>[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: t.colorScheme.primaryContainer,
                    foregroundColor: t.colorScheme.onPrimaryContainer,
                    child: Text(
                      h.name.isEmpty ? '?' : h.name.characters.first,
                    ),
                  ),
                  title: Text(h.name),
                  subtitle: Text(
                    h.ranges.isEmpty
                        ? 'No bond numbers yet'
                        : '${countLabel(h.bondCount)} bonds · '
                              '${gbp(h.totalValue)} · ${h.ranges.length} '
                              '${h.ranges.length == 1 ? 'entry' : 'entries'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/holder/${h.id}'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 72),
          ],
        ],
      ),
    );
  }
}

/// Adds a holder, or explains that more than one is a Pro feature.
Future<void> addHolderFlow(BuildContext context, WidgetRef ref) async {
  final List<Holder> holders = ref.read(holdersProvider);
  final bool pro = ref.read(isProProvider);
  if (!pro && holders.length >= FreeTier.maxHolders) {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('More holders with Pro'),
        content: const Text(
          'The free version keeps bonds for one holder. Bondbell Pro lets '
          'you add a partner, children or a relative\'s old certificates as '
          'separate holders. You can still add as many bond numbers as you '
          'like to your existing holder.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('See Pro'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) await context.push('/pro');
    return;
  }
  final String? name = await askName(context, title: 'Who are these bonds for?');
  if (name == null) return;
  final Holder h = await ref.read(holdersProvider.notifier).addHolder(name);
  if (context.mounted) await context.push('/holder/${h.id}');
}

Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (BuildContext c) => _NameDialog(title: title, initial: initial),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final String v = _c.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Enter a name, for example "Me" or "Gran".');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLength: 40,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: 'Name',
        hintText: 'e.g. Me, Sam, Grandad',
        errorText: _error,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
