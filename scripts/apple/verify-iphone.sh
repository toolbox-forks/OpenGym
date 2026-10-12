#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
: "${APPLE_BUILD_DIR:=$repo_root/frontend/ios/App/DerivedData}"
: "${APPLE_RESULTS_DIR:=$repo_root/frontend/ios/App/output}"
mkdir -p "$APPLE_RESULTS_DIR"
phone_udid=$(python3 scripts/apple/select-simulator.py)
xcodebuild -version
xcrun simctl boot "$phone_udid" 2>/dev/null || xcrun simctl list devices booted | grep -F "$phone_udid"
xcrun simctl bootstatus "$phone_udid" -b
xcodebuild -workspace frontend/ios/App/App.xcworkspace -scheme OpenGym \
  -configuration Release -destination "platform=iOS Simulator,id=$phone_udid" \
  -derivedDataPath "$APPLE_BUILD_DIR" CODE_SIGNING_ALLOWED=NO build \
  > "$APPLE_RESULTS_DIR/iphone-release.log" 2>&1
# A missing native/test target must fail; a Release build alone cannot show standalone works.
xcodebuild -workspace frontend/ios/App/App.xcworkspace -scheme OpenGym \
  -destination "platform=iOS Simulator,id=$phone_udid" -derivedDataPath "$APPLE_BUILD_DIR" \
  -resultBundlePath "$APPLE_RESULTS_DIR/iphone-tests.xcresult" CODE_SIGNING_ALLOWED=NO \
  -only-testing:AppleShellTests -only-testing:OpenGymUITests test \
  > "$APPLE_RESULTS_DIR/iphone-tests.log" 2>&1
