import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/common.dart';
import '../domain/holder.dart';
import 'bonds_screen.dart';
import 'holders_controller.dart';

class HolderScreen extends ConsumerWidget {
  const HolderScreen({super.key, required this.holderId});
  final String holderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData t = Theme.of(context);
    final Holder? h = ref
        .watch(holdersProvider)
        .where((Holder x) => x.id == holderId)
        .firstOrNull;
    if (h == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const PageList(
          children: <Widget>[
            MessageState(
              icon: Icons.person_off_outlined,
              title: 'Holder not found',
              body: 'They may have been deleted.',
            ),
          ],
        ),
      );
    }
    final HoldersController ctrl = ref.read(holdersProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(h.name),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final String? n = await askName(
                context,
                title: 'Rename holder',
                initial: h.name,
              );
              if (n != null) await ctrl.rename(h.id, n);
            },
          ),
          IconButton(
            tooltip: 'Delete holder',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final bool? ok = await showDialog<bool>(
                context: context,
                builder: (BuildContext c) => AlertDialog(
                  title: Text('Delete ${h.name}?'),
                  content: Text(
                    'Their bond numbers are removed from this '
                    '${deviceNoun(c)}. Saved '
                    'results stay in your history.',
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(c).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(c).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await ctrl.deleteHolder(h.id);
                if (context.mounted) context.pop();
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showRangeSheet(context, ref, holderId: h.id),
        icon: const Icon(Icons.add),
        label: const Text('Add bond numbers'),
      ),
      body: PageList(
        children: <Widget>[
          Text(
            '${countLabel(h.bondCount)} bonds · ${gbp(h.totalValue)}',
            style: t.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          if (h.totalValue > Holder.holdingLimit) ...<Widget>[
            InfoNote(
              'That\'s more than NS&I\'s ${gbp(Holder.holdingLimit)} limit '
              'per person. Double-check for a typo or a range entered twice.',
              icon: Icons.warning_amber_outlined,
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          if (h.ranges.isEmpty)
            MessageState(
              icon: Icons.post_add_outlined,
              title: 'Add their bond numbers',
              body:
                  'Statements list bonds in ranges, like '
                  '688ZY673000 – 688ZY673999. Paper certificates show one '
                  'number or a short run.',
              actions: <Widget>[
                FilledButton.icon(
                  onPressed: () => showRangeSheet(context, ref, holderId: h.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Add bond numbers'),
                ),
              ],
            )
          else
            Card(
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < h.ranges.length; i++) ...<Widget>[
                    if (i > 0) const Divider(indent: 20, endIndent: 20),
                    _RangeTile(holder: h, range: h.ranges[i]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 88),
        ],
      ),
    );
  }
}

class _RangeTile extends ConsumerWidget {
  const _RangeTile({required this.holder, required this.range});
  final Holder holder;
  final BondRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
      title: Text(
        range.isSingle ? '${range.start}' : '${range.start} to\n${range.end}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      subtitle: Text(
        range.isSingle
            ? '1 bond · £1'
            : '${countLabel(range.count)} bonds · ${gbp(range.count)}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Options',
        onSelected: (String v) async {
          if (v == 'edit') {
            await showRangeSheet(
              context,
              ref,
              holderId: holder.id,
              existing: range,
            );
          } else {
            await ref
                .read(holdersProvider.notifier)
                .deleteRange(holder.id, range.id);
          }
        },
        itemBuilder: (_) => const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
          PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

Future<void> showRangeSheet(
  BuildContext context,
  WidgetRef ref, {
  required String holderId,
  BondRange? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => _RangeSheet(holderId: holderId, existing: existing),
);

class _RangeSheet extends ConsumerStatefulWidget {
  const _RangeSheet({required this.holderId, this.existing});
  final String holderId;
  final BondRange? existing;

  @override
  ConsumerState<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends ConsumerState<_RangeSheet> {
  late final TextEditingController _start = TextEditingController(
    text: widget.existing?.start.toString() ?? '',
  );
  late final TextEditingController _end = TextEditingController(
    text: widget.existing == null || widget.existing!.isSingle
        ? ''
        : widget.existing!.end.toString(),
  );
  String? _error;
  bool _submitted = false;

  /// True while a save is running: a double tap on Save, or Save plus the
  /// keyboard's Done, must add the range once (code review m7).
  bool _saving = false;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  RangeResult get _result => BondRange.validate(_start.text, _end.text);

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    final RangeResult r = _result;
    if (r.error != null) {
      setState(() => _error = r.error);
      return;
    }
    setState(() => _saving = true);
    final HoldersController ctrl = ref.read(holdersProvider.notifier);
    try {
      if (widget.existing == null) {
        await ctrl.addRange(widget.holderId, r.start!, r.end!);
      } else {
        await ctrl.updateRange(
          widget.holderId,
          widget.existing!.id,
          r.start!,
          r.end!,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final RangeResult r = _result;
    final bool valid = r.error == null;
    final List<String> overlaps = valid
        ? overlappingRanges(
            ref.watch(holdersProvider),
            r.start!,
            r.end!,
            ignoreRangeId: widget.existing?.id,
          )
        : const <String>[];
    final int count = valid ? r.end!.serial - r.start!.serial + 1 : 0;
    final List<TextInputFormatter> fmt = <TextInputFormatter>[
      UpperCaseFormatter(),
      LengthLimitingTextInputFormatter(16),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.existing == null
                  ? 'Add bond numbers'
                  : 'Edit bond numbers',
              style: t.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter a range from a statement, or one number from a '
              'certificate. Examples: 688ZY673096, 85LV272879, or very old '
              'bonds like DW369715.',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _start,
              autofocus: widget.existing == null,
              inputFormatters: fmt,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'First (or only) bond number',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _end,
              inputFormatters: fmt,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Last bond number (optional)',
                helperText: 'Leave blank for a single bond.',
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            if (_error != null || (_submitted && !valid))
              Semantics(
                liveRegion: true,
                child: Text(
                  _error ?? r.error!,
                  style: t.textTheme.bodyLarge?.copyWith(
                    color: t.colorScheme.error,
                  ),
                ),
              )
            else if (valid)
              Text(
                count == 1
                    ? '1 bond · £1'
                    : '${countLabel(count)} bonds · ${gbp(count)}',
                style: t.textTheme.titleMedium,
              ),
            if (overlaps.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              InfoNote(
                'This overlaps numbers you\'ve already added: '
                '${overlaps.join(', ')}.',
                icon: Icons.warning_amber_outlined,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
