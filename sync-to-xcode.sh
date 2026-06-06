#!/bin/bash
# Sync latest code from GitHub repo to your Xcode project.
# Run this from the repo folder: ~/Desktop/Life-
# Usage: ./sync-to-xcode.sh [xcode-project-folder]
#
# Default Xcode project folder: ~/Desktop/Life/Life
# Override: ./sync-to-xcode.sh ~/Desktop/MyApp/MyApp

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
XCODE_APP="${1:-$HOME/Desktop/Life/Life}"
XCODE_WIDGET="${2:-$HOME/Desktop/Life/LifeTasksWidget}"

echo "Pulling latest changes from GitHub..."
git -C "$REPO_DIR" fetch origin
git -C "$REPO_DIR" reset --hard origin/main

echo ""
echo "Copying ios-native/*.swift → $XCODE_APP"
mkdir -p "$XCODE_APP"
cp "$REPO_DIR"/ios-native/*.swift "$XCODE_APP/"
cp "$REPO_DIR"/ios-native/Info.plist "$XCODE_APP/" 2>/dev/null || true
cp "$REPO_DIR"/ios-native/Life.entitlements "$XCODE_APP/" 2>/dev/null || true

echo "Copying ios-widget/*.swift → $XCODE_WIDGET"
mkdir -p "$XCODE_WIDGET"
cp "$REPO_DIR"/ios-widget/LifeTasksWidget.swift "$XCODE_WIDGET/" 2>/dev/null || true
cp "$REPO_DIR"/ios-widget/HabitWidget.swift "$XCODE_WIDGET/" 2>/dev/null || true

echo ""
echo "Done! Open Xcode and press Cmd+Shift+K (Clean), then Cmd+B (Build)."
