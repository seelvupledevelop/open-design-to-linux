#!/usr/bin/env bash
# Install the four native npm modules with linux-x64 binaries and make them
# load under the bundled Electron's Node ABI (pinned in work/electron-version.txt).
#
# Runs AFTER scripts/port-app-dir.sh and after `npm install electron@$EV`, because
# @electron/rebuild needs the local Electron package/headers.
# node-pty ships no linux prebuilds in its npm tarball, so it is compiled against
# Electron headers; better-sqlite3 gets an electron-ABI prebuild or a rebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
EV=$(cat work/electron-version.txt)

[ -f node_modules/electron/package.json ] || {
  echo "Electron $EV runtime missing — installing";
  npm install --no-save --no-audit --no-fund "electron@$EV";
}

cd app
BS3=$(node -e "console.log(require('./package.json').dependencies['better-sqlite3'])")
PTV=$(node -e "console.log(require('./package.json').dependencies['node-pty'])")
FAK=$(node -e "console.log(require('./package.json').dependencies['@ffmpeg-installer/ffmpeg'])")
SHV=$(node -e "console.log(require('./package.json').dependencies['sharp'])")

echo "== Installing natives (scripts deferred) =="
npm install --no-save --ignore-scripts --no-audit --no-fund \
  "better-sqlite3@$BS3" "node-pty@$PTV" "sharp@$SHV" "@ffmpeg-installer/ffmpeg@$FAK"

echo "== Rebuilding native modules against Electron $EV =="
cd "$ROOT"
npx electron-rebuild -f --only better-sqlite3,node-pty --module-dir app --version "$EV"

echo "== Native modules rebuilt for Electron $EV =="
