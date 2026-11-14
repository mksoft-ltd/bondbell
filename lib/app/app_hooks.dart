import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/local_store.dart';
import '../features/draws/presentation/check_session.dart';
import 'router.dart';

/// Orientations to request for a device, or null to leave them to the
/// platform. iOS is decided by Info.plist (iPhone portrait-only, iPad all
/// four), so Dart never overrides it. Android phones stay portrait; tablets
/// and unfolded foldables rotate freely (an empty list means "all").
List<DeviceOrientation>? orientationsFor(
  TargetPlatform platform,
  double shortestSide,
) {
  if (platform != TargetPlatform.android) return null;
  return shortestSide < 600
      ? const <DeviceOrientation>[DeviceOrientation.portraitUp]
      : const <DeviceOrientation>[];
}

/// App-wide hooks that need a laid-out view or the app lifecycle.
///
/// - Orientation is decided from the real window size, after the first
///   frame, and re-applied when the size class changes (code review m4: in
///   `main()` the view size can still be zero, which locked tablets to
///   portrait).
/// - On resume, a stale NS&I index is dropped (code review M1).
class AppHooks extends ConsumerStatefulWidget {
  const AppHooks({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppHooks> createState() => _AppHooksState();
}

class _AppHooksState extends ConsumerState<AppHooks> {
  late final AppLifecycleListener _lifecycle;
  List<DeviceOrientation>? _applied;
  bool _appliedOnce = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(indexProvider.notifier).dropIfStale(),
    );
    final String? damaged = vaultStatusMessage(ref.read(vaultStatusProvider));
    if (damaged != null) {
      // Say what happened to the user's data once, plainly (review N1),
      // rather than opening to an unexplained empty app.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? nav = ref
            .read(routerProvider)
            .routerDelegate
            .navigatorKey
            .currentContext;
        if (nav == null) return;
        showDialog<void>(
          context: nav,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Your saved data was damaged'),
            content: Text(damaged),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Size size = MediaQuery.sizeOf(context);
    if (size.isEmpty) return;
    final List<DeviceOrientation>? wanted = orientationsFor(
      defaultTargetPlatform,
      size.shortestSide,
    );
    if (wanted == null) return;
    if (_appliedOnce && listEquals(wanted, _applied)) return;
    _appliedOnce = true;
    _applied = wanted;
    SystemChrome.setPreferredOrientations(wanted);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
