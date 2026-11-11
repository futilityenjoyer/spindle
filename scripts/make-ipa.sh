#!/usr/bin/env bash
# Builds an unsigned Release archive, ad-hoc signs it WITH entitlements, verifies
# the App Group is present, and packages build/<name>.ipa for SideStore/Sideloadly.
#
# Why ad-hoc sign at all? With CODE_SIGNING_ALLOWED=NO, no entitlements end up in the
# binaries, so the re-signing tool never enables the App Group and the widget can't
# share data with the app. Ad-hoc signatures carry entitlements and are replaced
# by the re-signer on install.
#
# Usage: scripts/make-ipa.sh [output-name]   (run after `xcodegen generate`)
set -euo pipefail

NAME="${1:-Spindle}"
ARCHIVE="build/Spindle.xcarchive"
APP="$ARCHIVE/Products/Applications/Spindle.app"
APPEX="$APP/PlugIns/SpindleWidget.appex"

mkdir -p build
LOG="build/xcodebuild.log"

set +e
xcodebuild archive \
  -project Spindle.xcodeproj \
  -scheme Spindle \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" > "$LOG" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  # Surface compiler errors as GitHub annotations (shown at the top of the run page),
  # then the end of the log for context. The full log is uploaded as an artifact.
  grep -E '(error|fatal error):' "$LOG" | sed -E 's#^.*/(App|Shared|Widget|Packages)/#\1/#' | sort -u | head -40 |
    while IFS= read -r line; do echo "::error::$line"; done
  echo "----- last 60 lines of xcodebuild output -----"
  tail -60 "$LOG"
  exit "$status"
fi

if [ ! -d "$APPEX" ]; then
  echo "::error::Widget extension was not embedded in the app"
  exit 1
fi

# Sign inside-out: nested frameworks/dylibs, then the extension, then the app.
# Never use --deep: it would stamp the app's entitlements onto nested code.
find "$APP" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0 |
  while IFS= read -r -d '' nested; do
    codesign --force --sign - --timestamp=none "$nested"
  done
codesign --force --sign - --timestamp=none --entitlements Config/SpindleWidget.entitlements "$APPEX"
codesign --force --sign - --timestamp=none --entitlements Config/Spindle.entitlements "$APP"

# Fail the build if either bundle lost the App Group entitlement.
for bundle in "$APPEX" "$APP"; do
  entitlements="$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null || true)"
  if ! grep -q 'com.apple.security.application-groups' <<<"$entitlements"; then
    echo "::error::App Group entitlement missing on $bundle"
    exit 1
  fi
  echo "Entitlements OK: $(basename "$bundle")"
done

rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && ditto -c -k --sequesterRsrc --keepParent Payload "../$NAME.ipa")
echo "Built build/$NAME.ipa ($(du -h "build/$NAME.ipa" | cut -f1))"
