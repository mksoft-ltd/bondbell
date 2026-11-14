#!/bin/sh
# Release build guard (security audit L-3).
#
# Flutter writes the entry point and --dart-define values into
# ios/Flutter/Generated.xcconfig on every `flutter build`/`flutter run`/
# `flutter drive`. A bare Xcode Archive does NOT regenerate it, so archiving
# right after a screenshot capture would ship the integration-test harness
# (FLUTTER_TARGET=integration_test/...) with screenshot defines.
#
# This runs in Runner's "Run Script" phase and fails a Release build unless
# the target is lib/main.dart and no screenshot/capture define is present.
# Fix: run `flutter build ipa --release` (or `flutter build ios --release`)
# before archiving; it regenerates the file.
[ "$CONFIGURATION" = "Release" ] || exit 0

case "$FLUTTER_TARGET" in
  ""|lib/main.dart|*/lib/main.dart) ;;
  *)
    echo "error: Release build with FLUTTER_TARGET=$FLUTTER_TARGET. Run 'flutter build ipa --release' first (stale ios/Flutter/Generated.xcconfig)." >&2
    exit 1
    ;;
esac

old_ifs=$IFS
IFS=','
for d in $DART_DEFINES; do
  decoded=$(printf '%s' "$d" | base64 -D 2>/dev/null || printf '%s' "$d" | base64 -d 2>/dev/null)
  case "$decoded" in
    SCREENSHOT_*|HOST_CAPTURE*)
      echo "error: Release build carries the debug define '$decoded'. Run 'flutter build ipa --release' first (stale ios/Flutter/Generated.xcconfig)." >&2
      exit 1
      ;;
  esac
done
IFS=$old_ifs
exit 0
