#!/bin/bash
#
# Builds Life and runs the test suite on a Mac with Xcode.
#
# This repository is developed from a Linux container that has no Swift
# toolchain and no Apple SDKs, so compilation and test execution can only
# happen here. Run this after pulling and paste the output back if anything
# fails.
#
#   ./scripts/build-and-test.sh
#
set -uo pipefail

cd "$(dirname "$0")/.."

PROJECT="Life.xcodeproj"
SCHEME="${SCHEME:-Life}"

# Pick whatever iPhone simulator this Mac actually has, rather than pinning a
# model that may not be installed.
DEVICE=$(xcrun simctl list devices available \
    | grep -Eo 'iPhone [^(]*' \
    | tail -1 \
    | sed 's/ *$//')

if [ -z "$DEVICE" ]; then
    echo "No iPhone simulator installed. Open Xcode > Settings > Platforms and add an iOS runtime."
    exit 1
fi

DESTINATION="platform=iOS Simulator,name=$DEVICE"
echo "==> Scheme:      $SCHEME"
echo "==> Destination: $DESTINATION"
echo

echo "==> Building"
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -quiet 2>&1 | grep -E 'error:|warning:|BUILD' | head -80
BUILD_STATUS=${PIPESTATUS[0]}

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo
    echo "==> BUILD FAILED. Full errors:"
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" 2>&1 | grep -E 'error:' | sort -u
    exit "$BUILD_STATUS"
fi

echo
echo "==> Running tests"
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" 2>&1 \
    | grep -E 'error:|Test Case|Test Suite|✔|✘|passed|failed|TEST'
exit "${PIPESTATUS[0]}"
