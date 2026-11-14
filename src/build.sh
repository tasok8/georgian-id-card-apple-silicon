#!/bin/bash
# Build an Apple silicon (arm64) "Georgian ID Card.app" from the original
# Intel installation. The original app is only read, never modified.
#
# Usage:
#   src/build.sh                 # personal build  -> build/Georgian ID Card.app
#   src/build.sh --dist          # clean build for sharing -> dist/ (zip + dmg)
#
# Environment overrides:
#   ORIG_APP           original app   (default: /Applications/Georgian ID Card.app)
#   JDK_HOME           arm64 JDK with JavaFX jmods (default: work/toolchain/jdk17,
#                      downloaded from Azul and SHA-256 verified if missing)
#   CODESIGN_IDENTITY  "Developer ID Application: ..." for a release signature
#                      (default: ad-hoc "-", fine for local use only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIG_APP="${ORIG_APP:-/Applications/Georgian ID Card.app}"
JDK_HOME="${JDK_HOME:-$ROOT/work/toolchain/jdk17}"
IDENTITY="${CODESIGN_IDENTITY:--}"
MODE=personal
[[ "${1:-}" == "--dist" ]] && MODE=dist

# Azul Zulu 17 (LTS) JDK + JavaFX, macOS aarch64
JDK_URL="https://cdn.azul.com/zulu/bin/zulu17.70.113-ca-fx-jdk17.0.21.0.3-macosx_aarch64.tar.gz"
JDK_SHA256="1e7ca529d1c95cbf85dd7bc92e868b1aa8bf5bdd6dbee228ff86ae2deee97150"

# Same module set as the original Java 14 runtime, minus modules that no
# longer exist in Java 17 (jdk.aot, jdk.incubator.jpackage, jdk.scripting.nashorn*).
MODULES="java.base,java.compiler,java.datatransfer,java.desktop,java.instrument,java.logging,java.management,java.management.rmi,java.naming,java.net.http,java.prefs,java.rmi,java.scripting,java.se,java.security.jgss,java.security.sasl,java.smartcardio,java.sql,java.sql.rowset,java.transaction.xa,java.xml,java.xml.crypto,javafx.base,javafx.controls,javafx.fxml,javafx.graphics,javafx.media,javafx.swing,javafx.web,jdk.accessibility,jdk.charsets,jdk.compiler,jdk.crypto.cryptoki,jdk.crypto.ec,jdk.dynalink,jdk.httpserver,jdk.incubator.foreign,jdk.internal.ed,jdk.internal.le,jdk.internal.opt,jdk.internal.vm.ci,jdk.internal.vm.compiler,jdk.internal.vm.compiler.management,jdk.jdeps,jdk.jdwp.agent,jdk.jfr,jdk.jlink,jdk.jsobject,jdk.localedata,jdk.management,jdk.management.agent,jdk.management.jfr,jdk.naming.dns,jdk.naming.rmi,jdk.net,jdk.nio.mapmode,jdk.sctp,jdk.security.auth,jdk.security.jgss,jdk.unsupported,jdk.unsupported.desktop,jdk.xml.dom,jdk.zipfs"

APP_NAME="Georgian ID Card"
if [[ $MODE == dist ]]; then OUT="$ROOT/dist"; else OUT="$ROOT/build"; fi
APP="$OUT/$APP_NAME.app"
C="$APP/Contents"
R="$C/Resources"

log() { printf '\n==> %s\n' "$*"; }

[[ "$(uname -m)" == arm64 ]] || echo "warning: not running on arm64; the result will still be arm64-only"
[[ -d "$ORIG_APP/Contents/Resources/plugins" ]] || { echo "original app not found: $ORIG_APP" >&2; exit 1; }

# --- 1. JDK -------------------------------------------------------------------
if [[ ! -x "$JDK_HOME/bin/jlink" ]]; then
  log "Downloading Azul Zulu 17 FX (arm64)"
  tc="$ROOT/work/toolchain"; mkdir -p "$tc"
  tgz="$tc/$(basename "$JDK_URL")"
  curl -fL --retry 3 -o "$tgz" "$JDK_URL"
  echo "$JDK_SHA256  $tgz" | shasum -a 256 -c -
  tar -xzf "$tgz" -C "$tc"
  ln -sfn "$tc/$(basename "$JDK_URL" .tar.gz)/Contents/Home" "$tc/jdk17"
  JDK_HOME="$tc/jdk17"
fi
file -L "$JDK_HOME/bin/java" | grep -q arm64 || { echo "JDK is not arm64: $JDK_HOME" >&2; exit 1; }

# --- 2. copy original app ------------------------------------------------------
log "Copying original app -> $APP"
mkdir -p "$OUT"
if [[ -e "$APP" ]]; then
  case "$APP" in "$ROOT"/build/*.app|"$ROOT"/dist/*.app) rm -rf -- "$APP" ;; *) echo "refusing to delete $APP" >&2; exit 1 ;; esac
fi
ditto --norsrc --noextattr "$ORIG_APP" "$APP"

# Remove Intel runtime, stale signature, cached OSGi state (records osgi.arch=x86_64)
# and runtime logs (may contain personal data; they are recreated on launch).
rm -rf -- "$R/jre" "$C/_CodeSignature" "$R/configuration/org.eclipse.osgi"
rm -f -- "$R/debug.log" "$R/logging.log"
find "$APP" -name .DS_Store -delete
if [[ $MODE == dist ]]; then
  # factory defaults (same values Main.loadProperties() falls back to)
  printf 'display_prompt_dialogs=true\ndevelopmentMode=0\nlanguage=ka\n' > "$R/config.properties"
fi

# --- 3. arm64 Java runtime -----------------------------------------------------
log "Creating arm64 Java 17 runtime with jlink"
"$JDK_HOME/bin/jlink" --module-path "$JDK_HOME/jmods" --add-modules "$MODULES" \
  --strip-debug --no-man-pages --no-header-files --compress=2 --output "$R/jre"
cp "$JDK_HOME/readme.txt" "$R/jre/legal/ZULU_README.txt" 2>/dev/null || true

# --- 4. arm64 launcher ---------------------------------------------------------
log "Compiling arm64 launcher"
xcrun clang -arch arm64 -mmacosx-version-min=11.0 -O2 -Wall -Wextra \
  -framework CoreFoundation -o "$C/MacOS/$APP_NAME" "$ROOT/src/launcher/main.c"

# --- 5. Info.plist -------------------------------------------------------------
PB=/usr/libexec/PlistBuddy
$PB -c "Set :LSMinimumSystemVersion 11.0" "$C/Info.plist"
$PB -c "Delete :LSArchitecturePriority" "$C/Info.plist" 2>/dev/null || true
$PB -c "Add :LSArchitecturePriority array" -c "Add :LSArchitecturePriority:0 string arm64" "$C/Info.plist"
$PB -c "Delete :LSRequiresNativeExecution" "$C/Info.plist" 2>/dev/null || true
$PB -c "Add :LSRequiresNativeExecution bool true" "$C/Info.plist"
$PB -c "Set :BuildMachineOSBuild $(sw_vers -buildVersion)" "$C/Info.plist"
$PB -c "Delete :CFBundleGetInfoString" "$C/Info.plist" 2>/dev/null || true
$PB -c "Add :CFBundleGetInfoString string 1.0 (arm64 repack: launcher + Java 17 runtime)" "$C/Info.plist"
plutil -lint "$C/Info.plist" >/dev/null

# --- 6. code signing -----------------------------------------------------------
log "Signing (identity: $IDENTITY)"
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN+=(--timestamp --options runtime --entitlements "$ROOT/src/entitlements.plist")
fi
# inside-out: every Mach-O in the runtime, then the launcher, then the bundle
while IFS= read -r -d '' f; do
  if file "$f" | grep -q "Mach-O"; then "${SIGN[@]}" "$f"; fi
done < <(find "$R/jre" -type f -print0)
"${SIGN[@]}" "$C/MacOS/$APP_NAME"
"${SIGN[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# --- 7. packaging (dist only) ---------------------------------------------------
if [[ $MODE == dist ]]; then
  log "Packaging"
  ver=$($PB -c "Print :CFBundleShortVersionString" "$C/Info.plist")
  base="GeorgianIDCard-${ver}-arm64"
  rm -f -- "$OUT/$base.zip" "$OUT/$base.dmg"
  ditto -c -k --keepParent "$APP" "$OUT/$base.zip"
  stage="$OUT/.dmg-stage"; rm -rf -- "$stage"; mkdir -p "$stage"
  ditto "$APP" "$stage/$APP_NAME.app"
  ln -s /Applications "$stage/Applications"
  cp "$ROOT/docs/INSTALL.md" "$stage/INSTALL.md" 2>/dev/null || true
  hdiutil create -quiet -volname "$APP_NAME (Apple silicon)" -srcfolder "$stage" -ov -format UDZO "$OUT/$base.dmg"
  rm -rf -- "$stage"
  [[ "$IDENTITY" != "-" ]] && codesign --force --sign "$IDENTITY" --timestamp "$OUT/$base.dmg"
  (cd "$OUT" && shasum -a 256 "$base.zip" "$base.dmg" > "$base.sha256")
  echo "Notarization is NOT done by this script. See docs/RELEASE-CHECKLIST.md."
fi

log "Done: $APP ($(du -sh "$APP" | cut -f1))"
