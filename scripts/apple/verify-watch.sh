#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
: "${APPLE_BUILD_DIR:=$repo_root/frontend/ios/App/DerivedData}"
: "${APPLE_RESULTS_DIR:=$repo_root/frontend/ios/App/output}"
mkdir -p "$APPLE_RESULTS_DIR"
report_failure() {
  result=$?
  if [ "$result" -ne 0 ]; then
    python3 scripts/apple/report-watch.py "$APPLE_RESULTS_DIR" "$result"
  fi
  exit "$result"
}
trap report_failure EXIT
xcodebuild -version
watch_udid=$(python3 scripts/apple/select-watch-simulator.py)
phone_udid=$(python3 scripts/apple/select-simulator.py)
# Watch UI testing uses a companion simulator while the app itself logs without phone services.
xcrun simctl pair "$watch_udid" "$phone_udid" > "$APPLE_RESULTS_DIR/watch-pair.log" 2>&1 || xcrun simctl list pairs | grep -F "$watch_udid"
xcrun simctl boot "$watch_udid" 2>/dev/null || xcrun simctl list devices booted | grep -F "$watch_udid"
xcrun simctl bootstatus "$watch_udid" -b
xcodebuild -project frontend/ios/App/App.xcodeproj -scheme 'OpenGym Watch App' \
  -configuration Release -destination "platform=watchOS Simulator,id=$watch_udid" \
  -derivedDataPath "$APPLE_BUILD_DIR" CODE_SIGNING_ALLOWED=NO build \
  > "$APPLE_RESULTS_DIR/watch-release.log" 2>&1
echo '::notice::VERIFIED OpenGym Watch App Release simulator build passed.'
# Also compile device-only HealthKit branches; signing is intentionally disabled.
xcodebuild -project frontend/ios/App/App.xcodeproj -scheme 'OpenGym Watch App' \
  -configuration Release -destination 'generic/platform=watchOS' \
  -derivedDataPath "$APPLE_BUILD_DIR" CODE_SIGNING_ALLOWED=NO build \
  > "$APPLE_RESULTS_DIR/watch-device-build.log" 2>&1
echo '::notice::VERIFIED OpenGym Watch App unsigned device SDK build passed.'
xcodebuild -project frontend/ios/App/App.xcodeproj -scheme 'OpenGym Watch App' \
  -destination "platform=watchOS Simulator,id=$watch_udid" -derivedDataPath "$APPLE_BUILD_DIR" \
  -resultBundlePath "$APPLE_RESULTS_DIR/watch-tests.xcresult" CODE_SIGNING_ALLOWED=NO \
  -only-testing:OpenGymWatchUITests test > "$APPLE_RESULTS_DIR/watch-tests.log" 2>&1
xcrun xcresulttool get test-results summary --path "$APPLE_RESULTS_DIR/watch-tests.xcresult" \
  > "$APPLE_RESULTS_DIR/watch-test-summary.json"
python3 scripts/apple/report-watch.py "$APPLE_RESULTS_DIR" 0
