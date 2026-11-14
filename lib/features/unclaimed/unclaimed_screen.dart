import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../shared/widgets/common.dart';
import '../bonds/domain/bond_number.dart';
import '../bonds/domain/holder.dart';
import '../bonds/presentation/holder_screen.dart';
import '../bonds/presentation/holders_controller.dart';
import '../draws/domain/check_models.dart';
import '../draws/presentation/records_controller.dart';
import '../purchases/presentation/purchase_controller.dart';

class UnclaimedScreen extends ConsumerStatefulWidget {
  const UnclaimedScreen({super.key});

  @override
  ConsumerState<UnclaimedScreen> createState() => _UnclaimedScreenState();
}

class _UnclaimedScreenState extends ConsumerState<UnclaimedScreen> {
  final TextEditingController _number = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _searchOne() {
    final BondNumberResult r = BondNumber.tryParse(_number.text);
    if (r.error != null) {
      setState(() => _error = r.error);
      return;
    }
    FocusScope.of(context).unfocus();
    context.push('/check/unclaimed-single/${r.value}');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final bool pro = ref.watch(isProProvider);
    final Map<String, CheckRecord> records = ref.watch(recordsProvider);
    final List<Holder> holders = ref.watch(holdersProvider);
    final int bonds = holders.fold(0, (int a, Holder h) => a + h.bondCount);
    final CheckRecord? all = records['unclaimed'];
    final CheckRecord? one = records['unclaimed-single'];

    return Scaffold(
      appBar: AppBar(title: const Text('Unclaimed prizes')),
      body: PageList(
        children: <Widget>[
          Text(
            'NS&I publishes a list of prizes won 18 months or more ago that '
            'were never claimed, going back to 1957. Old paper bonds in a '
            'drawer are worth a look.',
            style: t.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Search one bond number',
            icon: Icons.search,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _number,
                  inputFormatters: <TextInputFormatter>[
                    UpperCaseFormatter(),
                    LengthLimitingTextInputFormatter(16),
                  ],
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Bond number',
                    hintText: 'e.g. 688ZY673096',
                    errorText: _error,
                    errorMaxLines: 3,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _searchOne(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _searchOne,
                  child: const Text('Search the unclaimed list'),
                ),
                if (one != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _LastResult(record: one),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Search all my bonds',
            icon: Icons.manage_search,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  pro
                      ? 'Check every range you\'ve saved against the whole '
                            'unclaimed list in one go.'
                      : 'Checking every range you\'ve saved in one go is '
                            'part of Bondbell Pro. You can still search any '
                            'single number above for free.',
                  style: t.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                if (pro)
                  FilledButton(
                    onPressed: bonds == 0
                        ? null
                        : () => context.push('/check/unclaimed'),
                    child: Text(
                      bonds == 0
                          ? 'Add bond numbers first'
                          : 'Search ${countLabel(bonds)} bonds',
                    ),
                  )
                else
                  OutlinedButton(
                    onPressed: () => context.push('/pro'),
                    child: const Text('About Bondbell Pro'),
                  ),
                if (pro && all != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _LastResult(record: all),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastResult extends StatelessWidget {
  const _LastResult({required this.record});
  final CheckRecord record;

  @override
  Widget build(BuildContext context) {
    final String what = record.singleNumber != null
        ? 'Last search: ${record.singleNumber}'
        : 'Last search';
    final String outcome = record.hasWins
        ? '${record.prizeCount} unclaimed '
              '${record.prizeCount == 1 ? 'prize' : 'prizes'} '
              '(${gbp(record.totalWon)})'
        : 'nothing found';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('$what: $outcome'),
      subtitle: Text(
        DateFormat('d MMM y, HH:mm').format(record.checkedAt.toLocal()),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/result/${record.listId}'),
    );
  }
}
