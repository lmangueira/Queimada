#!/bin/bash
# Assemble and sign .app bundles from the SPM build (no Xcode required).
#
# Usage:
#   Packaging/scripts/make-app.sh app-direct   # non-sandboxed direct build (KTD4 fallback / default dev build)
#   Packaging/scripts/make-app.sh app-mas      # sandboxed build (MAS access model; ad-hoc signed for local testing)
#   Packaging/scripts/make-app.sh spike        # U1 sandbox spike (sandboxed, ad-hoc)
#   Packaging/scripts/make-app.sh spike-usb    # U1 spike variant WITH com.apple.security.device.usb
#
# Environment:
#   SIGN_IDENTITY   codesign identity (default: "-" = ad-hoc).
#                   Direct release: "Developer ID Application: ..."
#                   MAS release:    "3rd Party Mac Developer Application: ..."
#   HARDENED=1      add hardened runtime (required for notarization).
#
# Output: dist/<Name>.app

set -euo pipefail
cd "$(dirname "$0")/../.."

VARIANT="${1:-app-direct}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
HARDENED="${HARDENED:-0}"

case "$VARIANT" in
  app-direct)
    TARGET=BluRayBurner; APP_NAME="Blu-Ray Burner"
    PLIST=Packaging/Info-App.plist
    ENTITLEMENTS=Packaging/BluRayBurner-Direct.entitlements
    ;;
  app-mas)
    TARGET=BluRayBurner; APP_NAME="Blu-Ray Burner"
    PLIST=Packaging/Info-App.plist
    ENTITLEMENTS=Packaging/BluRayBurner-MAS.entitlements
    ;;
  spike)
    TARGET=SandboxBurnSpike; APP_NAME="SandboxBurnSpike"
    PLIST=Packaging/Info-Spike.plist
    ENTITLEMENTS=Packaging/Spike.entitlements
    ;;
  spike-usb)
    TARGET=SandboxBurnSpike; APP_NAME="SandboxBurnSpike"
    PLIST=Packaging/Info-Spike.plist
    ENTITLEMENTS=Packaging/Spike-USB.entitlements
    ;;
  *)
    echo "unknown variant: $VARIANT (use app-direct | app-mas | spike | spike-usb)" >&2
    exit 1
    ;;
esac

echo "==> Building $TARGET (release)"
swift build -c release --product "$TARGET"

BIN=".build/release/$TARGET"
APP="dist/$APP_NAME.app"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$TARGET"
cp "$PLIST" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM resource bundles (Bundle.module) live next to the built binary and
# must ship inside Contents/Resources for the accessor to find them.
for RES_BUNDLE in ".build/release/${TARGET}_"*.bundle; do
  [[ -d "$RES_BUNDLE" ]] && cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
done

SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
if [[ "$HARDENED" == "1" ]]; then
  SIGN_FLAGS+=(--options runtime)
fi

echo "==> Signing ($SIGN_IDENTITY${HARDENED:+, hardened=$HARDENED})"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Done: $APP"
echo "    Launch:            open \"$APP\""
echo "    Mock smoke test:   BRB_MOCK=1 \"$APP/Contents/MacOS/$TARGET\""
