#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash scripts/port-app-dir.sh "${1:?version}"
npm install --no-save --no-audit --no-fund "electron@$(cat work/electron-version.txt)"
bash scripts/install-native-modules.sh
bash scripts/smoke-test.sh
npx electron-builder --x64
echo "== Artifacts: packages/*.deb packages/*.AppImage =="
