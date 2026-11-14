import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/common.dart';
import '../../settings/presentation/app_settings.dart';
import '../domain/check_models.dart';
import 'records_controller.dart';
import 'result_view.dart';

/// A stored result, opened from Home or History.
class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.recordId});
  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CheckRecord? r = ref.watch(recordsProvider)[recordId];
    final bool sample = ref.watch(sampleModeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(r?.label ?? 'Result')),
      body: Column(
        children: <Widget>[
          if (sample) const SampleBanner(),
          Expanded(
            child: r == null
                ? PageList(
                    children: <Widget>[
                      MessageState(
                        icon: Icons.search_off,
                        title: 'No result saved',
                        body: 'This list hasn\'t been checked yet.',
                        actions: <Widget>[
                          FilledButton(
                            onPressed: () => context.pop(),
                            child: const Text('Back'),
                          ),
                        ],
                      ),
                    ],
                  )
                : ResultView(record: r),
          ),
        ],
      ),
    );
  }
}
