#!/usr/bin/env bash
# Port the official Open Design macOS DMG into a Linux-ready Electron app directory.
#
# Usage: bash scripts/port-app-dir.sh <upstream-version>
#   e.g. bash scripts/port-app-dir.sh 0.26.1
#
# What it does:
#   1. Downloads the official mac-x64 DMG + .sha256 from nexu-io/open-design releases
#      and verifies the checksum.
#   2. Extracts "Open Design.app/Contents/Resources/app" (upstream ships an unpacked
#      Electron app dir: package.json + main.cjs + prebundled + node_modules).
#   3. Prunes macOS-only native binaries and reinstalls the native modules for
#      linux-x64 against the bundled Electron ABI (better-sqlite3, node-pty, sharp,
#      @ffmpeg-installer/ffmpeg). onnxruntime-node already ships linux bindings.
#   4. Detects the bundled Electron version (e.g. Electron/41.3.0) and writes it to
#      work/electron-version.txt so the workflow can pin the runtime.
#   5. Patches the staged package.json (name/author) for clean deb metadata.
set -euo pipefail

VERSION="${1:?usage: port-app-dir.sh <version>}"
UPSTREAM_REPO="${UPSTREAM_REPO:-nexu-io/open-design}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/work"
APP_SRC=""
APP_DIR="$ROOT/app"

echo "== Open Design $VERSION: fetching official DMG =="
mkdir -p "$WORK"
DMG_URL="https://github.com/${UPSTREAM_REPO}/releases/download/open-design-v${VERSION}/open-design-${VERSION}-mac-x64.dmg"
F="$WORK/open-design-${VERSION}-mac-x64.dmg"
[ -s "$F" ] || curl -fL "$DMG_URL" -o "$F"
curl -fL "${DMG_URL}.sha256" -o "$WORK/dmg.sha256"
# The official .sha256 asset contains "<digest> <filename>"; take the digest only.
EXPECTED=$(awk 'NR==1{print $1}' "$WORK/dmg.sha256")
ACTUAL=$(sha256sum "$F" | awk '{print $1}')
[ "$EXPECTED" = "$ACTUAL" ] || { echo "DMG sha256 mismatch: $ACTUAL != $EXPECTED"; exit 1; }
echo "Checksum OK: $ACTUAL"

echo "== Extracting DMG (7zz) =="
rm -rf "$WORK/extract" && mkdir -p "$WORK/extract"
7z x -y "$F" -o"$WORK/extract" >/dev/null
APP_SRC=$(find "$WORK/extract" -maxdepth 2 -name "Open Design.app" | head -1)
[ -n "$APP_SRC" ] || { echo "Open Design.app not found in DMG"; exit 1; }

echo "== Detecting bundled Electron version =="
ELECTRON_FRAMEWORK="$APP_SRC/Contents/Frameworks/Electron Framework.framework/Electron Framework"
EV=$(grep -aom1 'Electron/[0-9][0-9.]*' "$ELECTRON_FRAMEWORK" | cut -d/ -f2)
[ -n "$EV" ] || EV="41.3.0"
echo "$EV" > "$WORK/electron-version.txt"
echo "Bundled Electron: $EV"

echo "== Staging app dir =="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp -a "$APP_SRC/Contents/Resources/app/." "$APP_DIR/"

echo "== Pruning macOS-only native components =="
cd "$APP_DIR"
rm -rf node_modules/fsevents
rm -rf node_modules/@img/sharp-darwin-x64 node_modules/@img/sharp-libvips-darwin-x64
rm -rf node_modules/@ffmpeg-installer/darwin-x64
rm -rf node_modules/node-pty/prebuilds
rm -rf node_modules/onnxruntime-node/bin/napi-v3/darwin-* node_modules/onnxruntime-node/bin/napi-v3/win32-*
rm -rf node_modules/better-sqlite3/build node_modules/better-sqlite3/prebuilds

echo "== Patching package.json for Linux packaging =="
node - <<EOF
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.name = 'open-design';
pkg.author = 'Open Design (Apache-2.0) — Linux port by seelvupledevelop';
pkg.description = pkg.description || 'Open Design — Linux build from the official macOS package';
if (pkg.optionalDependencies) delete pkg.optionalDependencies.fsevents;
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
EOF

echo "== Installing native modules for linux-x64 / Electron $EV =="
BS3=$(node -e "console.log(require('./package.json').dependencies['better-sqlite3'])")
PTV=$(node -e "console.log(require('./package.json').dependencies['node-pty'])")
FAK=$(node -e "console.log(require('./package.json').dependencies['@ffmpeg-installer/ffmpeg'])")
SHV=$(node -e "console.log(require('./package.json').dependencies['sharp'])")
export npm_config_runtime=electron
export npm_config_target="$EV"
export npm_config_disturl=https://electronjs.org/headers
npm install --no-save --no-audit --no-fund \
  "better-sqlite3@$BS3" "node-pty@$PTV" "sharp@$SHV" "@ffmpeg-installer/ffmpeg@$FAK"

echo "== Port complete =="
echo "App dir: $APP_DIR"
echo "Electron: $EV (work/electron-version.txt)"
