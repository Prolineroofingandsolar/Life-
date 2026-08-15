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
# The complete, untruncated xcodebuild output is always written to
# build-log.txt (gitignored) regardless of whether the build succeeds. If the
# summary below isn't enough to work from, send that file — it holds the
# `note:` lines, carets and overload candidates that decide whether a fix is
# one line or twenty.
#
# Environment overrides:
#   SCHEME=LifeTasksWidgetExtension   build the widget in isolation
#   SKIP_TESTS=1                      build only, don't run the suite
#
set -uo pipefail

cd "$(dirname "$0")/.."

PROJECT="Life.xcodeproj"
SCHEME="${SCHEME:-Life}"
BUILD_LOG="build-log.txt"
TEST_LOG="test-log.txt"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild not found. This script must run on a Mac with Xcode"
    echo "installed, and Xcode must have been opened once to accept its licence."
    exit 1
fi

# The Command Line Tools ship an xcodebuild stub, so the check above passes
# even when no real Xcode is selected — and then the failure surfaces several
# steps later as a confusing "unable to find utility simctl". Catch it here,
# where the message can say what to actually do.
DEVELOPER_DIR_PATH=$(xcode-select -p 2>/dev/null || true)
if ! xcrun --find simctl >/dev/null 2>&1; then
    echo "The active developer directory is:"
    echo "    ${DEVELOPER_DIR_PATH:-<none>}"
    echo
    echo "That is the Command Line Tools, not a full Xcode, so there is no"
    echo "iOS simulator and no iOS SDK. Building an iPhone app needs Xcode."
    echo
    FOUND_XCODE=$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1)
    if [ -n "$FOUND_XCODE" ]; then
        echo "Xcode is installed at $FOUND_XCODE — point the tools at it with:"
        echo
        echo "    sudo xcode-select -s \"$FOUND_XCODE/Contents/Developer\""
    else
        echo "No Xcode found in /Applications. Install it from the App Store,"
        echo "open it once to accept the licence and let it install components,"
        echo "then run:"
        echo
        echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    fi
    exit 1
fi

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

echo "==> Xcode:       $(xcodebuild -version | head -1)"
echo "==> Scheme:      $SCHEME"
echo "==> Destination: $DESTINATION"
echo "==> Full log:    $BUILD_LOG"
echo

# Summarises a log: every error with surrounding context, uncapped, then a
# count. Context matters more than brevity here — a bare `error:` line rarely
# says enough to fix anything.
summarise() {
    local log="$1"
    local count
    count=$(grep -c 'error:' "$log" 2>/dev/null || true)
    count=${count:-0}

    if [ "$count" -gt 0 ]; then
        echo
        echo "==> Errors, with context ($count total):"
        echo
        grep -n -B1 -A3 'error:' "$log"
    fi

    echo
    echo "==> Unique error lines:"
    grep -o 'error:.*' "$log" | sort | uniq -c | sort -rn

    echo
    echo "==> $count error line(s). Full log: $log"
}

echo "==> Building (first run also resolves the Firebase SPM package, which is slow)"
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?

grep -E '^\s*(BUILD|\*\* BUILD)' "$BUILD_LOG" || true

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo
    echo "==> BUILD FAILED"

    # Package resolution failing is a different animal from a compile error and
    # should not be triaged as one.
    if grep -qiE 'could not resolve package|failed to resolve dependencies|xcodebuild: error: Could not resolve' "$BUILD_LOG"; then
        echo
        echo "!!! This looks like a Swift Package resolution failure, not a compile"
        echo "!!! error. Check network access to github.com and try again before"
        echo "!!! reading anything below as a code problem."
    fi

    summarise "$BUILD_LOG"
    exit "$BUILD_STATUS"
fi

echo "==> BUILD SUCCEEDED"

if [ "${SKIP_TESTS:-0}" = "1" ]; then
    echo "==> SKIP_TESTS=1, stopping here."
    exit 0
fi

echo
echo "==> Running tests (full log: $TEST_LOG)"
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    > "$TEST_LOG" 2>&1
TEST_STATUS=$?

grep -E 'Test Case|Test Suite|✔|✘|passed|failed|TEST (SUCCEEDED|FAILED)' "$TEST_LOG" \
    | grep -vE "passed \(0\.0" \
    || true

if [ "$TEST_STATUS" -ne 0 ]; then
    echo
    echo "==> TESTS FAILED"
    summarise "$TEST_LOG"
    echo
    echo "==> Failures:"
    grep -E 'error:|✘|XCTAssert|Expectation failed' "$TEST_LOG" | sort -u
fi

exit "$TEST_STATUS"
