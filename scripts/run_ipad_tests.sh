#!/usr/bin/env bash
# Pin UI and unit tests to the iPad destination this app actually runs on.
set -euo pipefail
cd "$(dirname "$0")/.."
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"
exec xcodebuild -project CFAL3.xcodeproj -scheme CFAL3 \
  -destination "$DESTINATION" test "$@"
