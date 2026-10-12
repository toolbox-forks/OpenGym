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
    python3 "$repo_root/scripts/apple/report-results.py" "$APPLE_RESULTS_DIR" "$result"
  fi
  exit "$result"
}
trap report_failure EXIT
phone_udid=$(python3 scripts/apple/select-simulator.py)
xcodebuild -version
echo "::notice::Apple oracle host architecture: $(uname -m); $(xcodebuild -version | tr '\n' ' ')."
xcrun simctl boot "$phone_udid" 2>/dev/null || xcrun simctl list devices booted | grep -F "$phone_udid"
xcrun simctl bootstatus "$phone_udid" -b
xcodebuild -workspace frontend/ios/App/App.xcworkspace -scheme OpenGym \
  -configuration Release -destination "platform=iOS Simulator,id=$phone_udid" \
  -derivedDataPath "$APPLE_BUILD_DIR" CODE_SIGNING_ALLOWED=NO build \
  > "$APPLE_RESULTS_DIR/iphone-release.log" 2>&1
echo '::notice::VERIFIED OpenGym Release simulator build passed.'
# A missing native/test target must fail; a Release build alone cannot show standalone works.
xcodebuild -workspace frontend/ios/App/App.xcworkspace -scheme OpenGym \
  -destination "platform=iOS Simulator,id=$phone_udid" -derivedDataPath "$APPLE_BUILD_DIR" \
  -resultBundlePath "$APPLE_RESULTS_DIR/iphone-tests.xcresult" CODE_SIGNING_ALLOWED=NO \
  -only-testing:AppleShellTests -only-testing:OpenGymUITests test \
  > "$APPLE_RESULTS_DIR/iphone-tests.log" 2>&1
xcrun xcresulttool get test-results summary --path "$APPLE_RESULTS_DIR/iphone-tests.xcresult" \
  > "$APPLE_RESULTS_DIR/iphone-test-summary.json"
python3 "$repo_root/scripts/apple/report-results.py" "$APPLE_RESULTS_DIR" 0
