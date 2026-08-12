#!/bin/bash
# Build SiriAIIndexStatus.app, widget extension included.
#
# The bundle is built by Xcode, not SwiftPM: WidgetKit only discovers a widget shipped as an .appex
# inside the host app's Contents/PlugIns/, which SwiftPM cannot produce (ADR-0005). SiriIndexCore
# and the tests stay pure SwiftPM — the project consumes the package, so `swift test` covers the
# same code the app ships.
#
# The app is also why the bundle needs a real signature rather than an ad-hoc one: the App Group
# container the widget reads from is only created for a provisioned identity.
#
# Usage: Scripts/make-app-bundle.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
case "$CONFIG" in
	debug) XCCONFIG="Debug" ;;
	release) XCCONFIG="Release" ;;
	*) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SiriAIIndexStatus"
DERIVED="$ROOT/build/DerivedData"
APP="$ROOT/build/$APP_NAME.app"

cd "$ROOT"

# project.yml is the source of truth; the .xcodeproj is generated (and committed, so a clone can
# build without xcodegen installed). Regenerate when the tool is available so the two never drift.
if command -v xcodegen >/dev/null 2>&1; then
	xcodegen generate --quiet
else
	echo "note: xcodegen not installed; building the committed .xcodeproj as-is"
fi

xcodebuild \
	-project "$APP_NAME.xcodeproj" \
	-scheme "$APP_NAME" \
	-configuration "$XCCONFIG" \
	-derivedDataPath "$DERIVED" \
	build

# Copy out to a stable path: build/SiriAIIndexStatus.app is what the README, the Full Disk Access
# grant and the operator's muscle memory all point at.
BUILT="$DERIVED/Build/Products/$XCCONFIG/$APP_NAME.app"
rm -rf "$APP"
ditto "$BUILT" "$APP"

# xcodebuild registers its own DerivedData copy with LaunchServices, so the widget gallery would
# otherwise offer the throwaway build. Register the stable copy last: it wins.
# Unregistering the DerivedData copy first is what actually moves the widget's registration —
# re-registering the stable copy alone leaves the throwaway path in place, and it breaks the moment
# build/DerivedData is cleaned.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
"$LSREGISTER" -u "$BUILT" >/dev/null 2>&1 || true
"$LSREGISTER" -f -R -trusted "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "  widget: $(basename "$(ls -d "$APP/Contents/PlugIns/"*.appex 2>/dev/null || echo '(none embedded!)')")"
