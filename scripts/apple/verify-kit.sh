#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
mkdir -p frontend/ios/App/output
set +e
swift test --package-path apple/OpenGymKit > frontend/ios/App/output/kit-tests.log 2>&1
result=$?
set -e
python3 scripts/apple/report-kit.py frontend/ios/App/output/kit-tests.log "$result"
exit "$result"
