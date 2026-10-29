#!/usr/bin/env bash
# Verify the ported native modules load under the pinned Electron's Node ABI.
# Runs the Electron binary in node mode (ELECTRON_RUN_AS_NODE=1) and requires
# each native module. If prebuilt binaries don't match the ABI, rebuilds
# better-sqlite3 and node-pty from source against Electron headers, then retries.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EV=$(cat "$ROOT/work/electron-version.txt")
ELECTRON="$ROOT/node_modules/electron/dist/electron"
[ -x "$ELECTRON" ] || { echo "Electron dist missing — run: npm install --no-save electron@$EV"; exit 1; }

cd "$ROOT/app"

CHECK='
try {
  const Database = require("better-sqlite3");
  new Database(":memory:").exec("select 1");
  require("node-pty");
  require("sharp");
  const ff = require("@ffmpeg-installer/ffmpeg");
  const fs = require("fs");
  if (!fs.existsSync(ff.path)) throw new Error("ffmpeg binary missing at " + ff.path);
  console.log("SMOKE OK: better-sqlite3, node-pty, sharp, ffmpeg all load under Electron ABI");
} catch (e) { console.error("SMOKE FAIL:", e.message); process.exit(1); }
'

if ELECTRON_RUN_AS_NODE=1 "$ELECTRON" --no-sandbox -e "$CHECK"; then
  exit 0
fi

echo "== ABI/prebuilt mismatch — rebuilding from source against Electron $EV headers =="
export npm_config_runtime=electron
export npm_config_target="$EV"
export npm_config_disturl=https://electronjs.org/headers
export npm_config_build_from_source=true
npm rebuild better-sqlite3 node-pty

if ELECTRON_RUN_AS_NODE=1 "$ELECTRON" --no-sandbox -e "$CHECK"; then
  echo "== Rebuild fixed it, continuing =="
  exit 0
fi
echo "Native modules still failing after rebuild." >&2
exit 1
