import 'dart:convert';

import 'package:bondbell/app/app.dart';
import 'package:bondbell/app/router.dart';
import 'package:bondbell/core/storage/local_store.dart';
import 'package:bondbell/features/bonds/domain/bond_number.dart';
import 'package:bondbell/features/bonds/domain/holder.dart';
import 'package:bondbell/features/draws/data/draw_source.dart';
import 'package:bondbell/features/draws/domain/check_models.dart';
import 'package:bondbell/features/draws/presentation/check_session.dart';
import 'package:bondbell/features/purchases/presentation/purchase_controller.dart';
import 'package:bondbell/features/reminders/reminder_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Device surfaces, in logical pixels.
abstract final class Surfaces {
  /// iPhone SE (3rd gen): the narrowest current iPhone.
  static const Size smallPhone = Size(375, 667);
  static const Size phone = Size(393, 852);

  /// iPad Pro 13" portrait and landscape.
  static const Size ipad = Size(1032, 1376);
  static const Size ipadLandscape = Size(1376, 1032);
}

/// The JSON the app stores for one holder.
String holdersJson(List<Holder> holders) =>
    jsonEncode(holders.map((Holder h) => h.toJson()).toList());

/// Stored check results as the app writes them.
String recordsJson(List<CheckRecord> records) => jsonEncode(<String, Object?>{
  for (final CheckRecord r in records) r.listId: r.toJson(),
});

/// A real holder used across widget tests: one statement range (1,000) and
/// one certificate.
final Holder meHolder = Holder(
  id: 'me',
  name: 'Me',
  ranges: <BondRange>[
    BondRange(
      id: 'r1',
      start: _p('312KM104000'),
      end: _p('312KM104999'),
    ),
    BondRange(id: 'r2', start: _p('47DW185533'), end: _p('47DW185533')),
  ],
);

BondNumber _p(String s) => BondNumber.parse(s);

class Harness {
  Harness(this.container, this.store, this.reminders);
  final ProviderContainer container;
  final FakeStoreGateway store;
  final FakeReminderService reminders;

  void go(String route) => container.read(routerProvider).go(route);
  void push(String route) => container.read(routerProvider).push(route);
}

/// Pumps the whole app (router, theme, snackbar listener) with every
/// platform seam faked. [prefs] seeds SharedPreferences; onboarding is
/// complete unless [onboarded] is false.
Future<Harness> pumpBondbell(
  WidgetTester tester, {
  Map<String, Object> prefs = const <String, Object>{},
  bool onboarded = true,
  bool forcePro = false,
  FakeStoreGateway? store,
  FakeReminderService? reminders,
  DrawSource? liveSource,
  List<Override> extra = const <Override>[],
  Size size = Surfaces.phone,
  double textScale = 1,
  String? route,
  LocalStore Function(SharedPreferences prefs)? localFactory,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  SharedPreferences.setMockInitialValues(<String, Object>{
    'settings.onboarded': onboarded,
    ...prefs,
  });
  final SharedPreferences prefsInstance = await SharedPreferences.getInstance();
  final LocalStore local =
      localFactory?.call(prefsInstance) ?? LocalStore(prefsInstance);
  final FakeStoreGateway s = store ?? FakeStoreGateway();
  final FakeReminderService r = reminders ?? FakeReminderService();
  final ProviderContainer c = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(local),
      storeGatewayProvider.overrideWithValue(s),
      reminderServiceProvider.overrideWithValue(r),
      if (forcePro) forceProProvider.overrideWithValue(true),
      if (liveSource != null) liveDrawSourceProvider.overrideWithValue(liveSource),
      ...extra,
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const BondbellApp()),
  );
  await tester.pump();
  final Harness h = Harness(c, s, r);
  if (route != null) {
    h.go(route);
  }
  await tester.pumpAndSettle();
  return h;
}

/// Tears the tree down inside the test body (so any controller timers are
/// cancelled before flutter_test's pending-timer check), then the container.
Future<void> disposeApp(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  h.container.dispose();
  await tester.pump();
}

/// A check session whose phase is set by the test, so every screen state
/// can be shown without a network, a file system or an isolate.
class ScriptedCheckSession extends CheckSessionController {
  ScriptedCheckSession(this.script);
  final CheckSessionState Function(CheckRequest) script;
  int starts = 0;
  int cancels = 0;
  int prepares = 0;
  CheckRequest? lastRequest;

  @override
  CheckSessionState build() => const CheckSessionState();

  @override
  Future<void> prepare(CheckRequest initial) async {
    prepares++;
    lastRequest = initial;
    state = script(initial);
  }

  @override
  Future<void> start() async => starts++;

  @override
  void cancel() {
    cancels++;
    state = state.copyWith(phase: CheckPhase.cancelled);
  }

  @override
  void reset() => state = const CheckSessionState();

  void set(CheckSessionState s) => state = s;
}

/// Collects every Flutter error (overflows included) raised while [body]
/// runs, so a layout sweep can report all of them at once.
Future<List<String>> collectFlutterErrors(Future<void> Function() body) async {
  final List<String> errors = <String>[];
  final FlutterExceptionHandler? old = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) =>
      errors.add(d.exceptionAsString().split('\n').first);
  try {
    await body();
  } finally {
    FlutterError.onError = old;
  }
  return errors;
}

/// A fixed run of frames, for screens with endless animations.
Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the on-screen list (not one offstage in another tab or route)
/// until [finder] is built, then brings it to the top of the viewport so it
/// is clear of the bottom navigation bar and can be tapped.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).hitTestable().first,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// A store whose writes to private (vault) keys can be made to fail, like a
/// full disk (code review N1).
class FailingStore extends LocalStore {
  FailingStore(super.prefs);
  bool fail = true;
  int refused = 0;

  @override
  Future<bool> setString(String key, String value) async {
    if (fail && LocalStore.isPrivateKey(key)) {
      refused++;
      return false;
    }
    return super.setString(key, value);
  }
}
