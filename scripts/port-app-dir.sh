#!/usr/bin/env bash
# Port the official Open Design macOS DMG into a Linux-ready layout:
#   app/            the Electron app dir (staged as the electron-builder app)
#   resources-extra/ Resources files referenced via process.resourcesPath
#                   (open-design assets, web-standalone server, dom-to-pptx)
#
# Usage: bash scripts/port-app-dir.sh <upstream-version>
#
# Why not a plain 7zz extract?
#   - The DMG contains pnpm-style symlinks (web-standalone/node_modules/@scope/...
#     -> ../.pnpm/...) which 7zz refuses as "dangerous link path" and reports on
#     stderr while still extracting the real files. We capture the report and
#     recreate those links afterwards, then validate everything needed.
#   - The macOS bundle carries Mach-O binaries (open-design/bin/opencode, vela)
#     plus helper frameworks; native Linux equivalents are not part of the DMG,
#     so Mach-O files are dropped from the ported Resources.
set -euo pipefail

VERSION="${1:?usage: port-app-dir.sh <version>}"
UPSTREAM_REPO="${UPSTREAM_REPO:-nexu-io/open-design}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/work"
APP_DIR="$ROOT/app"
EXTRA="$ROOT/resources-extra"

echo "== Open Design $VERSION: fetching official DMG =="
mkdir -p "$WORK"
DMG_URL="https://github.com/${UPSTREAM_REPO}/releases/download/open-design-v${VERSION}/open-design-${VERSION}-mac-x64.dmg"
F="$WORK/open-design-${VERSION}-mac-x64.dmg"
[ -s "$F" ] || curl -fL "$DMG_URL" -o "$F"
curl -fL "${DMG_URL}.sha256" -o "$WORK/dmg.sha256"
EXPECTED=$(awk 'NR==1{print $1}' "$WORK/dmg.sha256")
ACTUAL=$(sha256sum "$F" | awk '{print $1}')
[ "$EXPECTED" = "$ACTUAL" ] || { echo "DMG sha256 mismatch: $ACTUAL != $EXPECTED"; exit 1; }
echo "Checksum OK: $ACTUAL"

echo "== Extracting DMG (7zz, tolerating skipped dangerous links) =="
rm -rf "$WORK/extract" && mkdir -p "$WORK/extract"
set +e
7z x -y "$F" -o"$WORK/extract" >"$WORK/extraction.log" 2>&1
R7Z=$?
set -e
grep -a "Dangerous link path was ignored" "$WORK/extraction.log" | while IFS= read -r line; do
  rest="${line#*Dangerous link path was ignored : }"
  path="${rest%% : *}"
  target="${rest#* : }"
  mkdir -p "$(dirname "$WORK/extract/$path")"
  ln -sfn "$target" "$WORK/extract/$path"
  echo "relaunched symlink: $path -> $target"
done

APP_SRC=$(find "$WORK/extract" -maxdepth 3 -name "Open Design.app" -type d | head -1)
[ -n "$APP_SRC" ] || { echo "Open Design.app not found in DMG"; tail -5 "$WORK/extraction.log"; exit 1; }
RSRC="$APP_SRC/Contents/Resources"

echo "== Detecting bundled Electron version =="
ELECTRON_FRAMEWORK="$APP_SRC/Contents/Frameworks/Electron Framework.framework/Electron Framework"
EV=$(grep -aoE 'Electron/[0-9]+\.[0-9]+\.[0-9]+' "$ELECTRON_FRAMEWORK" | head -n1 | cut -d/ -f2)
[ -n "$EV" ] || EV="41.3.0"
echo "$EV" > "$WORK/electron-version.txt"
echo "Bundled Electron: $EV"

echo "== Staging app dir =="
rm -rf "$APP_DIR" "$EXTRA"
mkdir -p "$APP_DIR" "$EXTRA"
cp -a "$RSRC/app/." "$APP_DIR/"

echo "== Staging Resources referenced by process.resourcesPath =="
for item in open-design open-design-config.json open-design-web-standalone dom-to-pptx.bundle.js.gz; do
  cp -a "$RSRC/$item" "$EXTRA/$item"
done

echo "== Stripping Mach-O darwin binaries from ported resources =="
find "$EXTRA" -type f -exec sh -c 'LC_ALL=C file -b "$1" | grep -q "Mach-O" && rm -f "$1" && echo "dropped Mach-O: $1"' _ {} \;

echo "== Pruning macOS-only native components from app/node_modules =="
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
pkg.author = { name: 'Open Design Linux port (seelvupledevelop)', email: 'seelvupledevelop@users.noreply.github.com' };
pkg.description = pkg.description || 'Open Design — Linux build from the official macOS package';
if (pkg.optionalDependencies) delete pkg.optionalDependencies.fsevents;
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
EOF

echo "== (native modules are installed separately by scripts/install-native-modules.sh) =="

echo "== Validating ported layout =="
[ -f "$APP_DIR/package.json" ] && [ -f "$APP_DIR/main.cjs" ] && [ -f "$APP_DIR/prebundled/packaged-main.mjs" ]
[ -d "$APP_DIR/node_modules" ] && [ -f "$EXTRA/open-design-config.json" ]
[ -d "$EXTRA/open-design-web-standalone/node_modules/.pnpm" ]
L=$EXTRA/open-design-web-standalone/node_modules/@opentelemetry/api
[ -d "$(readlink -f "$L")" ] || { echo "web-standalone symlink broken: $L"; exit 1; }
echo "Layout OK"

echo "== Port complete =="
echo "Electron: $EV (work/electron-version.txt)"
