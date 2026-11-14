import 'package:flutter/foundation.dart';

/// `--dart-define=SCREENSHOT_MODE=true`: seeds sample data and unlocks Pro
/// for store screenshots. Compiled out of release builds.
const bool screenshotMode =
    bool.fromEnvironment('SCREENSHOT_MODE') && !kReleaseMode;

/// `--dart-define=SCREENSHOT_TOUR=true` (with SCREENSHOT_MODE): walks the
/// main screens on a timer and runs the sample check end to end, so a
/// simulator with no input tooling can be captured with `simctl io`.
/// Compiled out of release builds.
const bool screenshotTour =
    screenshotMode && bool.fromEnvironment('SCREENSHOT_TOUR');

/// Route sequence for the tour, with how long each stays on screen.
const List<(String, int)> tourStops = <(String, int)>[
  ('/home', 8),
  ('/check/draw/latest', 14),
  ('/history', 8),
  ('/bonds', 6),
  ('/unclaimed', 6),
  ('/settings', 6),
  ('/pro', 6),
];
