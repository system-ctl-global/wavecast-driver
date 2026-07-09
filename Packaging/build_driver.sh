#!/usr/bin/env bash
# build_driver.sh — Build and rebrand BlackHole as the 16-channel WaveCast driver.
#
# Run from the repo root:
#   ./Packaging/build_driver.sh
#
# Output: Packaging/WaveCast.driver  (ready to embed in the app bundle)
#
# Prerequisites:
#   - Xcode command-line tools installed
#   - Vendor/BlackHole submodule initialised:
#       git submodule update --init Vendor/BlackHole
#   - A valid Developer ID code-signing identity in your keychain.
#     Set SIGN_IDENTITY below, or pass it as an env var:
#       SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Packaging/build_driver.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLACKHOLE_PROJ="$REPO_ROOT/Vendor/BlackHole/BlackHole.xcodeproj"
PACKAGING_DIR="$REPO_ROOT/Packaging"
UUID_FILE="$PACKAGING_DIR/wavecast2ch.uuid"
ICON_FILE="$PACKAGING_DIR/WaveCast.icns"
OUT_DRIVER="$PACKAGING_DIR/WaveCast.driver"
BUILD_DIR="$PACKAGING_DIR/_build"

# ── Identity ────────────────────────────────────────────────────────────────
# Set to "-" to ad-hoc sign (no Notarization, local testing only).
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# PKG signing requires a "Developer ID Installer" identity — different from the
# "Developer ID Application" identity used for the driver binary.
# Leave empty (default) for an unsigned PKG, which is fine for local testing.
# For distribution: PKG_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
PKG_SIGN_IDENTITY="${PKG_SIGN_IDENTITY:-}"

# ── WaveCast-specific defines ────────────────────────────────────────────────
DRIVER_NAME="WaveCast"
CHANNELS=16
BUNDLE_ID="com.wavecast.driver"

# GPL-3.0 corresponding-source location (§6(d)). The public repo MUST host the
# exact BlackHole commit shipped below plus this build_driver.sh, and MUST stay
# reachable for as long as the driver binary is distributed.
# Publish/update it with: ./Packaging/publish_driver_source.sh
SOURCE_URL="https://github.com/system-ctl-global/wavecast-driver"

# ── Validate ─────────────────────────────────────────────────────────────────
if [ ! -f "$BLACKHOLE_PROJ/project.pbxproj" ]; then
    echo "ERROR: BlackHole submodule not initialised."
    echo "Run: git submodule update --init Vendor/BlackHole"
    exit 1
fi

if [ ! -f "$UUID_FILE" ]; then
    echo "ERROR: $UUID_FILE missing."
    exit 1
fi

if [ ! -f "$ICON_FILE" ]; then
    echo "ERROR: $ICON_FILE missing. Regenerate with:"
    echo "  iconutil -c icns Packaging/Assets/WaveCast.iconset -o Packaging/WaveCast.icns"
    exit 1
fi

FACTORY_UUID="$(tr -d '[:space:]' < "$UUID_FILE")"
echo "Driver:  $DRIVER_NAME ${CHANNELS}ch"
echo "Bundle:  $BUNDLE_ID"
echo "UUID:    $FACTORY_UUID"
echo

# ── Build ─────────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# GCC_PREPROCESSOR_DEFINITIONS overrides let us rebrand without touching source.
# kDriver_Name  → device appears as "WaveCast" in macOS
# kPlugIn_BundleID → bundle identifier baked into the driver binary
# kNumber_Of_Channels → 16 (multichannel bed)
#
# CODE_SIGN_IDENTITY="" + CODE_SIGNING_REQUIRED=NO skips Xcode's built-in signing
# so we can sign with our own identity immediately after the build.
xcodebuild \
    -project "$BLACKHOLE_PROJ" \
    -target BlackHole \
    -configuration Release \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    SYMROOT="$BUILD_DIR" \
    OBJROOT="$BUILD_DIR" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    GCC_PREPROCESSOR_DEFINITIONS="\
\$(inherited) \
DEBUG=0 \
kNumber_Of_Channels=$CHANNELS \
kPlugIn_BundleID='\"$BUNDLE_ID\"' \
kDriver_Name='\"$DRIVER_NAME\"' \
kPlugIn_Icon='\"WaveCast.icns\"' \
kSampleRates=48000" \
    2>&1 | grep -E "^(Build|CompileC|error:|warning:)" || true

# The pipe above swallows xcodebuild's exit code, so confirm the bundle exists
# before continuing — otherwise later steps fail with misleading errors.
if [ ! -d "$BUILD_DIR/BlackHole.driver" ]; then
    echo "ERROR: xcodebuild did not produce BlackHole.driver."
    echo "Full Xcode (not just Command Line Tools) is required. Install it, then:"
    echo "  sudo xcode-select -s /Applications/Xcode.app"
    exit 1
fi

echo
echo "Patching factory UUID in Info.plist…"

# The BlackHole placeholder UUID e395c745-… lives only in the compiled plist.
# Replace it with our project-specific UUID so we never collide with BlackHole
# or RIME (which ships the same placeholder UUID).
PLACEHOLDER="e395c745-4eea-4d94-bb92-46224221047c"
PLIST="$BUILD_DIR/BlackHole.driver/Contents/Info.plist"

if ! grep -q "$PLACEHOLDER" "$PLIST"; then
    echo "ERROR: Placeholder UUID not found in built plist. Check BlackHole version."
    exit 1
fi

sed -i '' "s/$PLACEHOLDER/$FACTORY_UUID/g" "$PLIST"

echo "Injecting WaveCast icon…"
RESOURCES="$BUILD_DIR/BlackHole.driver/Contents/Resources"
# Remove BlackHole's icon; add ours under the name the driver binary looks for.
rm -f "$RESOURCES/BlackHole.icns"
cp "$ICON_FILE" "$RESOURCES/WaveCast.icns"
# Also set CFBundleIconFile in the plist — Audio MIDI Setup reads the icon
# from here directly, not via the kAudioDevicePropertyIcon Core Audio property.
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string WaveCast" "$PLIST"

# ── GPL-3.0 compliance NOTICE ──────────────────────────────────────────────────
# The shipped binary is a modified version of BlackHole (GPL-3.0). GPL §5(a)
# requires a prominent notice of the changes and their date; §6 requires the
# corresponding source be available. Both live in the bundle Resources, next to
# the verbatim GPL-3.0 LICENSE that BlackHole already ships.
echo "Writing GPL-3.0 NOTICE…"
# Vendor/BlackHole is a git submodule pinned to our fork
# (github.com/system-ctl-global/BlackHole). The pinned commit IS the authoritative
# provenance, so read it directly. The legacy .wavecast-commit fallback covers a
# tarball export where the .git link is absent.
BH_COMMIT="$(git -C "$REPO_ROOT/Vendor/BlackHole" rev-parse HEAD 2>/dev/null \
    || cat "$REPO_ROOT/Vendor/BlackHole/.wavecast-commit" 2>/dev/null \
    || echo unknown)"
BH_VERSION="$(cat "$RESOURCES/VERSION" 2>/dev/null || echo "unknown")"
BUILD_DATE="$(date -u +%Y-%m-%d)"

NOTICE_TEMPLATE="$PACKAGING_DIR/Assets/NOTICE.template.txt"
if [ ! -f "$NOTICE_TEMPLATE" ]; then
    echo "ERROR: $NOTICE_TEMPLATE missing."
    exit 1
fi
# Render the @VAR@ placeholders in the template. '|' delimiter keeps the URL's
# slashes intact; sed is used instead of envsubst, which is not present on a
# stock macOS install.
sed \
    -e "s|@CHANNELS@|${CHANNELS}|g" \
    -e "s|@BUNDLE_ID@|${BUNDLE_ID}|g" \
    -e "s|@BH_VERSION@|${BH_VERSION}|g" \
    -e "s|@BH_COMMIT@|${BH_COMMIT}|g" \
    -e "s|@BUILD_DATE@|${BUILD_DATE}|g" \
    -e "s|@SOURCE_URL@|${SOURCE_URL}|g" \
    "$NOTICE_TEMPLATE" > "$RESOURCES/NOTICE.txt"

# ── Sign ──────────────────────────────────────────────────────────────────────
echo "Signing with: $SIGN_IDENTITY"
# A secure timestamp is required for notarization, but ad-hoc signing ("-")
# cannot contact Apple's timestamp server — only add it for a real identity.
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign \
        --force \
        --deep \
        --options runtime \
        --sign "$SIGN_IDENTITY" \
        "$BUILD_DIR/BlackHole.driver"
else
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$BUILD_DIR/BlackHole.driver"
fi

# ── Output ────────────────────────────────────────────────────────────────────
rm -rf "$OUT_DRIVER"
mv "$BUILD_DIR/BlackHole.driver" "$OUT_DRIVER"
rm -rf "$BUILD_DIR"

echo
echo "Done: $OUT_DRIVER"
echo
echo "Verify UUID in output plist:"
/usr/libexec/PlistBuddy -c "Print :CFPlugInFactories" "$OUT_DRIVER/Contents/Info.plist"

# ── PKG installer ─────────────────────────────────────────────────────────────
echo
echo "Building installer PKG…"

PKG_STAGING="$PACKAGING_DIR/_pkg_staging"
PKG_SCRIPTS="$PACKAGING_DIR/_pkg_scripts"
COMPONENT_PKG="$PACKAGING_DIR/_WaveCastDriverComponent.pkg"
FINAL_PKG="$PACKAGING_DIR/WaveCastDriver.pkg"

rm -rf "$PKG_STAGING" "$PKG_SCRIPTS" "$COMPONENT_PKG"
mkdir -p "$PKG_STAGING/Library/Audio/Plug-Ins/HAL"
mkdir -p "$PKG_SCRIPTS"

cp -R "$OUT_DRIVER" "$PKG_STAGING/Library/Audio/Plug-Ins/HAL/"

# postinstall: restart coreaudiod so the new driver loads without a reboot.
# `launchctl kickstart -k coreaudiod` is SIP-blocked on macOS 26+ ("Operation
# not permitted while System Integrity Protection is engaged"), so the driver
# would install but never load. `killall coreaudiod` is allowed and launchd
# respawns it, reloading HAL plugins. Keep kickstart as a fallback for older
# macOS. If both fail the driver still loads on next reboot.
cat > "$PKG_SCRIPTS/postinstall" << 'POSTINSTALL'
#!/bin/bash
killall coreaudiod 2>/dev/null \
    || launchctl kickstart -k system/com.apple.audio.coreaudiod 2>/dev/null \
    || true
exit 0
POSTINSTALL
chmod +x "$PKG_SCRIPTS/postinstall"

# Component package (flat, contains the payload + postinstall script).
if [ -n "$PKG_SIGN_IDENTITY" ]; then
    pkgbuild \
        --root "$PKG_STAGING" \
        --scripts "$PKG_SCRIPTS" \
        --identifier "com.wavecast.driver.pkg" \
        --version "1.0" \
        --sign "$PKG_SIGN_IDENTITY" \
        "$COMPONENT_PKG"
else
    pkgbuild \
        --root "$PKG_STAGING" \
        --scripts "$PKG_SCRIPTS" \
        --identifier "com.wavecast.driver.pkg" \
        --version "1.0" \
        "$COMPONENT_PKG"
fi

# Distribution package — custom XML sets the Installer.app title and sidebar
# background image (the icon shown in the left panel of Installer.app).
PKG_RESOURCES="$PACKAGING_DIR/_pkg_resources"
DIST_XML="$PACKAGING_DIR/_distribution.xml"
COMPONENT_BASENAME="$(basename "$COMPONENT_PKG")"

mkdir -p "$PKG_RESOURCES"
# The Installer.app sidebar image is pinned bottom-left with scaling="none" and
# the <background> element has no margin attribute, so a bare icon sits flush in
# the corner. Bake a transparent margin into the image itself: a 120px icon
# centred on a 168px canvas leaves a 24px inset from the left/bottom edges,
# aligning it with the installer's text and buttons.
PAD_SWIFT="$PKG_RESOURCES/_pad_icon.swift"
cat > "$PAD_SWIFT" << 'PADSWIFT'
import AppKit
let icon: CGFloat = 120, margin: CGFloat = 24
let side = icon + margin * 2
let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let out = NSImage(size: NSSize(width: side, height: side))
out.lockFocus()
src.draw(in: NSRect(x: margin, y: margin, width: icon, height: icon),
         from: .zero, operation: .sourceOver, fraction: 1.0)
out.unlockFocus()
let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
PADSWIFT
swiftc "$PAD_SWIFT" -o "$PKG_RESOURCES/_pad_icon"
"$PKG_RESOURCES/_pad_icon" \
    "$REPO_ROOT/Packaging/Assets/wavecast_icon.png" \
    "$PKG_RESOURCES/wavecast_icon.png"
rm -f "$PAD_SWIFT" "$PKG_RESOURCES/_pad_icon"
# lockFocus renders at 2x backing; force exact 168px so scaling="none" doesn't
# blow the image up to 336px and overflow the sidebar.
sips -z 168 168 "$PKG_RESOURCES/wavecast_icon.png" \
    --out "$PKG_RESOURCES/wavecast_icon.png" > /dev/null

# GPL-3.0 licence pane: Installer.app shows this and requires agreement before
# the modified BlackHole binary is installed. Prepend the WaveCast NOTICE so the
# modification + corresponding-source disclosure is seen up front.
DRIVER_RES="$OUT_DRIVER/Contents/Resources"
cat "$DRIVER_RES/NOTICE.txt" - "$DRIVER_RES/LICENSE" > "$PKG_RESOURCES/LICENSE.txt" << 'SEP'

--------------------------------------------------------------------------------
                    GNU GENERAL PUBLIC LICENSE, VERSION 3
--------------------------------------------------------------------------------

SEP

cat > "$DIST_XML" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>WaveCast Audio Driver</title>
    <background file="wavecast_icon.png" mime-type="image/png"
                alignment="bottomleft" scaling="none"/>
    <background-darkAqua file="wavecast_icon.png" mime-type="image/png"
                         alignment="bottomleft" scaling="none"/>
    <license file="LICENSE.txt" mime-type="text/plain"/>
    <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.wavecast.driver.pkg"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.wavecast.driver.pkg" visible="false">
        <pkg-ref id="com.wavecast.driver.pkg"/>
    </choice>
    <pkg-ref id="com.wavecast.driver.pkg" version="1.0" onConclusion="none">$COMPONENT_BASENAME</pkg-ref>
</installer-gui-script>
EOF

if [ -n "$PKG_SIGN_IDENTITY" ]; then
    productbuild \
        --distribution "$DIST_XML" \
        --resources "$PKG_RESOURCES" \
        --package-path "$PACKAGING_DIR" \
        --sign "$PKG_SIGN_IDENTITY" \
        "$FINAL_PKG"
else
    productbuild \
        --distribution "$DIST_XML" \
        --resources "$PKG_RESOURCES" \
        --package-path "$PACKAGING_DIR" \
        "$FINAL_PKG"
fi

rm -rf "$PKG_STAGING" "$PKG_SCRIPTS" "$COMPONENT_PKG" "$PKG_RESOURCES" "$DIST_XML"

# Copy PKG and icon into the consuming app's source tree — both are auto-included
# as bundle resources by Xcode 16's synchronized root group. When this repo is
# used standalone (its own corresponding source), there is no app tree, so the
# destination is opt-in: set APP_BUNDLE_RES_DIR to the app's resource folder.
# The main WaveCast repo consumes this driver as a submodule and passes
# APP_BUNDLE_RES_DIR=<main>/WaveCast.
APP_BUNDLE_RES_DIR="${APP_BUNDLE_RES_DIR:-}"

echo "Done: $FINAL_PKG"
if [ -n "$APP_BUNDLE_RES_DIR" ]; then
    mkdir -p "$APP_BUNDLE_RES_DIR"
    cp "$FINAL_PKG" "$APP_BUNDLE_RES_DIR/WaveCastDriver.pkg"
    echo "Bundled: $APP_BUNDLE_RES_DIR/WaveCastDriver.pkg"
else
    echo "(APP_BUNDLE_RES_DIR unset — skipped copy into app tree)"
fi
