import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bonds/domain/bond_number.dart';
import '../../bonds/domain/holder.dart';
import '../../bonds/presentation/holders_controller.dart';
import '../../purchases/presentation/purchase_controller.dart';
import '../../settings/presentation/app_settings.dart';
import '../data/draw_source.dart';
import '../data/nsi_index.dart';
import '../domain/check_models.dart';
import '../engine/nsi_list_parser.dart';
import '../engine/range_matcher.dart';
import '../engine/scan_worker.dart';
import 'records_controller.dart';

/// Overridable for tests. Real or sample by mode.
final Provider<DrawSource> drawSourceProvider = Provider<DrawSource>((Ref ref) {
  if (ref.watch(sampleModeProvider)) return SampleDrawSource();
  return ref.watch(liveDrawSourceProvider);
});

final Provider<DrawSource> liveDrawSourceProvider = Provider<DrawSource>(
  (Ref ref) => NsiDrawSource(),
);

/// NS&I's current downloads index. Fetched on demand (opening the app does
/// not touch nsandi.com until the user asks to check).
class IndexController extends AsyncNotifier<NsiIndex?> {
  @override
  Future<NsiIndex?> build() async {
    final DrawSource source = ref.watch(drawSourceProvider);
    // Sample mode is local, so it can load straight away.
    if (source.isSample) return source.fetchIndex();
    return null;
  }

  Future<NsiIndex> refresh() async {
    final DrawSource source = ref.read(drawSourceProvider);
    state = const AsyncLoading<NsiIndex?>();
    try {
      final NsiIndex i = await source.fetchIndex();
      state = AsyncData<NsiIndex?>(i);
      return i;
    } on Object catch (e, st) {
      state = AsyncError<NsiIndex?>(e, st);
      rethrow;
    }
  }
}

final AsyncNotifierProvider<IndexController, NsiIndex?> indexProvider =
    AsyncNotifierProvider<IndexController, NsiIndex?>(IndexController.new);

enum CheckKind { draw, unclaimedAll, unclaimedSingle }

@immutable
class CheckRequest {
  const CheckRequest.draw(String this.drawId)
    : kind = CheckKind.draw,
      single = null;
  const CheckRequest.unclaimedAll()
    : kind = CheckKind.unclaimedAll,
      drawId = null,
      single = null;
  const CheckRequest.unclaimedSingle(BondNumber this.single)
    : kind = CheckKind.unclaimedSingle,
      drawId = null;

  final CheckKind kind;
  final String? drawId;
  final BondNumber? single;

  String get recordId => switch (kind) {
    CheckKind.draw => drawId!,
    CheckKind.unclaimedAll => 'unclaimed',
    CheckKind.unclaimedSingle => 'unclaimed-single',
  };
}

enum CheckPhase {
  idle,
  preparing,
  ready,
  downloading,
  scanning,
  done,
  failed,
  cancelled,
}

@immutable
class CheckSessionState {
  const CheckSessionState({
    this.phase = CheckPhase.idle,
    this.request,
    this.list,
    this.sizeBytes,
    this.progress = 0,
    this.error,
    this.layoutChanged = false,
    this.record,
  });

  final CheckPhase phase;
  final CheckRequest? request;
  final RemoteList? list;
  final int? sizeBytes;

  /// 0..1 within the current phase.
  final double progress;
  final String? error;
  final bool layoutChanged;
  final CheckRecord? record;

  bool get isRunning =>
      phase == CheckPhase.preparing ||
      phase == CheckPhase.downloading ||
      phase == CheckPhase.scanning;

  CheckSessionState copyWith({
    CheckPhase? phase,
    RemoteList? list,
    int? sizeBytes,
    double? progress,
    String? error,
    bool? layoutChanged,
    CheckRecord? record,
  }) => CheckSessionState(
    phase: phase ?? this.phase,
    request: request,
    list: list ?? this.list,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    progress: progress ?? this.progress,
    error: error ?? this.error,
    layoutChanged: layoutChanged ?? this.layoutChanged,
    record: record ?? this.record,
  );
}

/// One check at a time: find the list → show its size → download (with
/// progress and cancel) → scan in a background isolate → store only the
/// matches → delete the download.
class CheckSessionController extends Notifier<CheckSessionState> {
  DownloadCancel? _cancel;
  ScanJob? _job;
  File? _file;
  int _generation = 0;

  @override
  CheckSessionState build() {
    ref.onDispose(() {
      // Retire the running check so it never writes to a disposed ref.
      _generation++;
      _abortWork();
    });
    return const CheckSessionState();
  }

  /// Steps 1-2: locate the list and its size, then wait for the user.
  Future<void> prepare(CheckRequest initial) async {
    CheckRequest request = initial;
    _abortWork();
    final int gen = ++_generation;
    state = CheckSessionState(phase: CheckPhase.preparing, request: request);
    try {
      final DrawSource source = ref.read(drawSourceProvider);
      final NsiIndex index =
          ref.read(indexProvider).value ??
          await ref.read(indexProvider.notifier).refresh();
      if (gen != _generation) return;
      // 'latest' resolves to whatever NS&I lists newest right now.
      if (request.kind == CheckKind.draw && request.drawId == 'latest') {
        final RemoteList? latest = index.latest;
        if (latest != null) {
          request = CheckRequest.draw(latest.id);
          state = CheckSessionState(
            phase: CheckPhase.preparing,
            request: request,
          );
        }
      }
      final String? gateError = _gate(request, index);
      if (gateError != null) {
        state = state.copyWith(phase: CheckPhase.failed, error: gateError);
        return;
      }
      final String drawId = request.drawId ?? '';
      final RemoteList? list = switch (request.kind) {
        CheckKind.draw =>
          index.draws.where((RemoteList l) => l.id == drawId).firstOrNull,
        _ => index.unclaimed,
      };
      if (list == null) {
        state = state.copyWith(
          phase: CheckPhase.failed,
          error: request.kind == CheckKind.draw
              ? 'NS&I no longer lists that draw. They keep about six months '
                    'of results online.'
              : 'Bondbell couldn\'t find the unclaimed prizes list on NS&I\'s '
                    'downloads page. The page may have changed.',
          layoutChanged: request.kind != CheckKind.draw,
        );
        return;
      }
      final int? size = await source.sizeOf(list);
      if (gen != _generation) return;
      state = state.copyWith(
        phase: CheckPhase.ready,
        list: list,
        sizeBytes: size,
      );
    } on SourceException catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
        phase: CheckPhase.failed,
        error: e.message,
        layoutChanged: e.layoutChanged,
      );
    } on Object catch (e) {
      if (gen != _generation) return;
      debugPrint('prepare: $e');
      state = state.copyWith(
        phase: CheckPhase.failed,
        error: 'Something went wrong finding NS&I\'s list. Please try again.',
      );
    }
  }

  /// Steps 3-6, on the user's go-ahead.
  Future<void> start() async {
    final CheckRequest? request = state.request;
    final RemoteList? list = state.list;
    if (state.phase != CheckPhase.ready || request == null || list == null) {
      return;
    }
    final int gen = _generation;
    final List<Holder> holders = ref.read(holdersProvider);
    final List<ScanTarget> targets = _targets(request, holders);
    if (targets.isEmpty) {
      state = state.copyWith(
        phase: CheckPhase.failed,
        error: 'Add some bond numbers first.',
      );
      return;
    }
    final DrawSource source = ref.read(drawSourceProvider);
    final DownloadCancel cancel = _cancel = DownloadCancel();
    state = state.copyWith(phase: CheckPhase.downloading, progress: 0);
    final Stopwatch sw = Stopwatch()..start();
    try {
      final File file = _file = await source.download(
        list,
        cancel: cancel,
        onProgress: (int got, int? total) {
          if (gen != _generation) return;
          final int? t = total ?? state.sizeBytes;
          state = state.copyWith(
            progress: t == null || t == 0 ? 0 : (got / t).clamp(0.0, 1.0),
          );
        },
      );
      final int downloadMs = sw.elapsedMilliseconds;
      if (gen != _generation) return;
      state = state.copyWith(phase: CheckPhase.scanning, progress: 0);
      final ScanJob job = _job = await ScanJob.start(
        zipPath: file.path,
        kind: request.kind == CheckKind.draw
            ? ListKind.winners
            : ListKind.unclaimed,
        targets: targets,
        onProgress: (double f) {
          if (gen == _generation) state = state.copyWith(progress: f);
        },
      );
      final ScanSummary summary = await job.result;
      _job = null;
      // Timings and sizes only; no bond numbers leave this line.
      debugPrint(
        '[bondbell] ${list.id}: download ${downloadMs}ms, scan '
        '${sw.elapsedMilliseconds - downloadMs}ms, '
        '${summary.numbersScanned} numbers, integrity ${summary.integrityOk}, '
        'maxRss ${ProcessInfo.maxRss ~/ (1024 * 1024)}MB',
      );
      if (gen != _generation) return;
      if (summary.numbersScanned == 0) {
        state = state.copyWith(
          phase: CheckPhase.failed,
          error:
              'Bondbell couldn\'t read any bond numbers from NS&I\'s file. '
              'Its format may have changed. Please check on NS&I\'s site '
              'instead.',
          layoutChanged: true,
        );
        return;
      }
      final CheckRecord record = _record(request, list, summary, holders);
      await ref.read(recordsProvider.notifier).put(record);
      if (gen != _generation) return;
      state = state.copyWith(
        phase: CheckPhase.done,
        record: record,
        progress: 1,
      );
    } on DownloadCancelledException {
      if (gen == _generation) {
        state = state.copyWith(phase: CheckPhase.cancelled);
      }
    } on ScanCancelled {
      if (gen == _generation) {
        state = state.copyWith(phase: CheckPhase.cancelled);
      }
    } on SourceException catch (e) {
      if (gen == _generation) {
        state = state.copyWith(
          phase: CheckPhase.failed,
          error: e.message,
          layoutChanged: e.layoutChanged,
        );
      }
    } on ScanException catch (e) {
      if (gen == _generation) {
        state = state.copyWith(
          phase: CheckPhase.failed,
          error: '${e.message} Please check on NS&I\'s site instead.',
          layoutChanged: true,
        );
      }
    } on Object catch (e) {
      debugPrint('check: $e');
      if (gen == _generation) {
        state = state.copyWith(
          phase: CheckPhase.failed,
          error: 'Something went wrong while checking. Please try again.',
        );
      }
    } finally {
      _deleteFile();
    }
  }

  void cancel() {
    if (!state.isRunning && state.phase != CheckPhase.ready) return;
    _abortWork();
    _generation++;
    state = state.copyWith(phase: CheckPhase.cancelled);
  }

  void reset() {
    _abortWork();
    _generation++;
    state = const CheckSessionState();
  }

  void _abortWork() {
    _cancel?.cancel();
    _cancel = null;
    _job?.cancel();
    _job = null;
    _deleteFile();
  }

  void _deleteFile() {
    final File? f = _file;
    _file = null;
    if (f == null) return;
    try {
      if (f.existsSync()) f.deleteSync();
    } on Object catch (e) {
      debugPrint('delete download: $e');
    }
  }

  /// Defence in depth: the screens already hide these behind Pro.
  String? _gate(CheckRequest request, NsiIndex index) {
    final bool pro = ref.read(isProProvider);
    if (pro) return null;
    if (request.kind == CheckKind.unclaimedAll) {
      return 'Checking all your bonds against the unclaimed list is part of '
          'Bondbell Pro.';
    }
    if (request.kind == CheckKind.draw) {
      final String? latest = index.latest?.id;
      if (latest != null && request.drawId != latest) {
        return 'Checking earlier draws is part of Bondbell Pro.';
      }
    }
    return null;
  }

  static List<ScanTarget> _targets(CheckRequest request, List<Holder> holders) {
    if (request.kind == CheckKind.unclaimedSingle) {
      final BondNumber n = request.single!;
      return <ScanTarget>[
        ScanTarget(series: n.series, lo: n.serial, hi: n.serial, holderId: ''),
      ];
    }
    return <ScanTarget>[
      for (final Holder h in holders)
        for (final BondRange r in h.ranges)
          ScanTarget(
            series: r.series,
            lo: r.start.serial,
            hi: r.end.serial,
            holderId: h.id,
          ),
    ];
  }

  static CheckRecord _record(
    CheckRequest request,
    RemoteList list,
    ScanSummary s,
    List<Holder> holders,
  ) {
    final Map<String, String> names = <String, String>{
      for (final Holder h in holders) h.id: h.name,
    };
    final List<Win> wins = <Win>[
      for (int i = 0; i < s.hits.length; i++)
        for (final String id in s.hits[i].holderIds)
          Win(
            hit: i,
            bond: s.hits[i].bond,
            prize: s.hits[i].prize,
            holderId: id,
            holderName: names[id] ?? 'The number you entered',
            anonymous: s.hits[i].anonymous,
          ),
    ]..sort((Win a, Win b) => b.prize.compareTo(a.prize));
    final bool single = request.kind == CheckKind.unclaimedSingle;
    return CheckRecord(
      listId: request.recordId,
      label: list.label,
      checkedAt: DateTime.now(),
      fingerprint: single ? '' : holdingsFingerprint(holders),
      wins: wins,
      numbersScanned: s.numbersScanned,
      integrityOk: s.integrityOk,
      bondsChecked: single
          ? 1
          : holders.fold(0, (int a, Holder h) => a + h.bondCount),
      singleNumber: single ? request.single.toString() : null,
    );
  }
}

final NotifierProvider<CheckSessionController, CheckSessionState>
checkSessionProvider =
    NotifierProvider<CheckSessionController, CheckSessionState>(
      CheckSessionController.new,
    );
