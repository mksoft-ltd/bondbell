import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calendar/results_calendar.dart';
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
import '../../../core/utils/app_log.dart';

/// Overridable for tests. Real or sample by mode.
final Provider<DrawSource> drawSourceProvider = Provider<DrawSource>((Ref ref) {
  if (ref.watch(sampleModeProvider)) return SampleDrawSource();
  return ref.watch(liveDrawSourceProvider);
});

final Provider<DrawSource> liveDrawSourceProvider = Provider<DrawSource>(
  (Ref ref) => NsiDrawSource(),
);

/// "Now", injectable so tests can move the clock past a results day.
final Provider<DateTime Function()> indexClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

/// NS&I's current downloads index. Fetched on demand (opening the app does
/// not touch nsandi.com until the user asks to check).
///
/// The copy is only trusted for a short while: a process kept alive across
/// a results day must not keep offering last month as "the latest draw"
/// (code review M1). See [isStale].
class IndexController extends AsyncNotifier<NsiIndex?> {
  /// How long a fetched index is reused for a non-"latest" request.
  static const Duration ttl = Duration(minutes: 10);

  DateTime? _fetchedAt;

  DateTime _now() => ref.read(indexClockProvider)();

  @override
  Future<NsiIndex?> build() async {
    final DrawSource source = ref.watch(drawSourceProvider);
    _fetchedAt = null;
    // Sample mode is local, so it can load straight away.
    if (source.isSample) return source.fetchIndex();
    return null;
  }

  /// True when the cached index may be out of date: older than [ttl], or
  /// fetched before the most recent results day began.
  bool isStale() {
    final DateTime? at = _fetchedAt;
    if (at == null) return true;
    final DateTime now = _now();
    if (now.difference(at) > ttl) return true;
    return at.isBefore(latestResultsDayStart(now));
  }

  /// Midnight at the start of the most recent results day on or before
  /// [now].
  static DateTime latestResultsDayStart(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    DateTime r = ResultsCalendar.resultsDay(now.year, now.month);
    if (r.isAfter(today)) r = ResultsCalendar.resultsDay(now.year, now.month - 1);
    return r;
  }

  /// The cached index if it is fresh (and [force] is false), otherwise a new
  /// fetch. A sample index is local and never goes stale.
  Future<NsiIndex> ensure({bool force = false}) async {
    final NsiIndex? cached = state.value;
    final bool sample = ref.read(drawSourceProvider).isSample;
    if (cached != null && (sample || (!force && !isStale()))) return cached;
    return refresh();
  }

  Future<NsiIndex> refresh() async {
    final DrawSource source = ref.read(drawSourceProvider);
    state = const AsyncLoading<NsiIndex?>();
    try {
      final NsiIndex i = await source.fetchIndex();
      _fetchedAt = _now();
      state = AsyncData<NsiIndex?>(i);
      return i;
    } on Object catch (e, st) {
      state = AsyncError<NsiIndex?>(e, st);
      rethrow;
    }
  }

  /// On resume: forget a stale live index so screens stop showing it (Home
  /// then offers "Show available draws" again). Nothing is fetched here;
  /// nsandi.com is only contacted on the user's tap.
  void dropIfStale() {
    if (ref.read(drawSourceProvider).isSample) return;
    if (state.value != null && isStale()) {
      _fetchedAt = null;
      state = const AsyncData<NsiIndex?>(null);
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
      // "Latest" always asks NS&I again: the newest list is the one thing
      // that changes on results day.
      final NsiIndex index = await ref
          .read(indexProvider.notifier)
          .ensure(force: request.kind == CheckKind.draw &&
              request.drawId == 'latest');
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
      appLog('prepare: $e');
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
          final double p = t == null || t == 0 ? 0 : (got / t).clamp(0.0, 1.0);
          // Whole-percent steps only: a 34 MB file arrives in ~500 chunks,
          // and each state change rebuilds the check screen (review n1).
          if ((p * 100).floor() == (state.progress * 100).floor()) return;
          state = state.copyWith(progress: p);
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
      // Cancelled while the isolate was spawning: _abortWork ran before
      // _job was set, so kill it here (review n3).
      if (gen != _generation) {
        job.cancel();
        return;
      }
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
      final String? monthError = monthMismatch(
        request,
        summary,
        sample: source.isSample,
      );
      if (monthError != null) {
        state = state.copyWith(
          phase: CheckPhase.failed,
          error: monthError,
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
      appLog('check: $e');
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
      appLog('delete download: $e');
    }
  }

  /// The winners file names its own month in its heading. If that is not
  /// the month the link was labelled with (NS&I's page is hand-edited), the
  /// result would be filed under the wrong month, so refuse it (code review
  /// m3). Returns the message to show, or null when it matches. The bundled
  /// sample's heading is deliberately not a real month, so it is exempt.
  @visibleForTesting
  static String? monthMismatch(
    CheckRequest request,
    ScanSummary summary, {
    required bool sample,
  }) {
    if (request.kind != CheckKind.draw || sample) return null;
    final String expected = NsiIndexParser.labelFor(request.drawId!);
    String norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final String? found = summary.drawLabel;
    if (found != null && norm(found) == norm(expected)) return null;
    return found == null
        ? 'NS&I\'s file for $expected doesn\'t say which draw it is for, so '
              'Bondbell can\'t be sure it\'s the right list. Please check on '
              'NS&I\'s site instead.'
        : 'NS&I\'s link for $expected leads to the $found list. Bondbell has '
              'not saved anything, so results aren\'t filed under the wrong '
              'month. Please check on NS&I\'s site instead.';
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
          : uniqueBondCount(holders),
      singleNumber: single ? request.single.toString() : null,
      sourceUrl: list.url.toString(),
    );
  }
}

final NotifierProvider<CheckSessionController, CheckSessionState>
checkSessionProvider =
    NotifierProvider<CheckSessionController, CheckSessionState>(
      CheckSessionController.new,
    );
