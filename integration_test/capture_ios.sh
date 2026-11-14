#!/usr/bin/env bash
# Runs integration_test/screenshots_test.dart on an iOS simulator and captures
# each shot host-side with `xcrun simctl io <udid> screenshot`, because
# binding.takeScreenshot() on the simulator can return the launch screen.
#
#   integration_test/capture_ios.sh <simulator-udid> [out-dir]
#
# The test prints "BONDBELL_SHOT <name>" and holds the frame for
# HOLD_SECONDS (4); this script captures on each marker, then fails if any
# two captures are byte-identical (the launch-screen symptom).
set -uo pipefail

UDID="${1:?usage: integration_test/capture_ios.sh <simulator-udid> [out-dir]}"
cd "$(dirname "$0")/.."
OUT="${2:-build/screenshots/ios-$UDID}"
rm -rf "$OUT"
mkdir -p "$OUT"

xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi \
  --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100 || true

flutter drive -d "$UDID" \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  --dart-define=SCREENSHOT_MODE=true \
  --dart-define=HOST_CAPTURE=true 2>&1 |
  while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" =~ BONDBELL_SHOT\ ([0-9a-z_]+) ]]; then
      name="${BASH_REMATCH[1]}"
      sleep 1
      if xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1; then
        echo ">> captured $OUT/$name.png"
      else
        echo ">> CAPTURE FAILED for $name"
      fi
    fi
  done
status=${PIPESTATUS[0]}

xcrun simctl status_bar "$UDID" clear || true

count=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
dups=$(md5 -q "$OUT"/*.png 2>/dev/null | sort | uniq -d | wc -l | tr -d ' ')
echo ">> $count captures in $OUT, $dups duplicate md5(s), flutter drive exit $status"
if [[ "$status" -ne 0 || "$count" -ne 8 || "$dups" -ne 0 ]]; then
  exit 1
fi
