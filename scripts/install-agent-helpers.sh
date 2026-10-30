#!/usr/bin/env bash
# Bundle Linux builds of the agent-runtime helpers into the ported resources.
#
# The upstream DMG ships open-design/bin/{vela, libexec/opencode/opencode} only
# as Mach-O darwin binaries, which the port drops. The app's daemon resolves:
#   - vela     from <resourceRoot>/bin/vela
#   - opencode from <resourceRoot>/bin/libexec/opencode/opencode
# (verified in the bundled daemon chunk; VELA_BIN/VELA_OPENCODE_BIN env vars
# would override, resourceRoot = Resources/open-design). Both exist as official
# Linux builds on npm inside @powerformer/vela-cli-linux-x64, whose bin/ tree
# has exactly the layout the daemon expects.
#
# The version is pinned by the upstream pack tool: tools/pack/package.json
# optionalDependencies["@powerformer/vela-cli"] at the release tag, and the
# platform package carries the same version number. We fetch that pin from the
# upstream tag so every ported release stays version-exact, verify the npm
# tarball checksum against the registry, and verify `vela --version` matches
# the pin exactly (same gate upstream's pack tool applies).
#
# Usage: bash scripts/install-agent-helpers.sh <upstream-version>
set -euo pipefail

VERSION="${1:?usage: install-agent-helpers.sh <upstream-version>}"
UPSTREAM_REPO="${UPSTREAM_REPO:-nexu-io/open-design}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTRA="$ROOT/resources-extra"
PIN_TARGET="$ROOT/resources-extra/open-design"
WORK="$ROOT/work/agent-helpers"

echo "== Resolving upstream Vela CLI pin for open-design-v$VERSION =="
mkdir -p "$WORK"
RAW="https://raw.githubusercontent.com/${UPSTREAM_REPO}/open-design-v${VERSION}/tools/pack/package.json"
curl -fsSL "$RAW" -o "$WORK/pack-package.json"
PIN=$(node -e 'const m=require(process.argv[1]); const v=(m.optionalDependencies||{})["@powerformer/vela-cli"]; if(typeof v!=="string"||!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(v.trim())){console.error("no exact @powerformer/vela-cli pin in upstream tools/pack");process.exit(1)}; console.log(v.trim());' "$WORK/pack-package.json")
echo "Upstream pin: @powerformer/vela-cli@$PIN -> using @powerformer/vela-cli-linux-x64@$PIN"

echo "== Downloading and checksum-verifying the npm tarball =="
cd "$WORK"
npm view "@powerformer/vela-cli-linux-x64@$PIN" dist.integrity > integrity.txt --silent
EXPECTED_INT=$(cut -d'-' -f2- integrity.txt)
curl -fsSL "https://registry.npmjs.org/@powerformer/vela-cli-linux-x64/-/vela-cli-linux-x64-${PIN}.tgz" -o platform.tgz
ACTUAL_INT=$(openssl dgst -sha512 -binary platform.tgz | base64 -w0)
[ "$EXPECTED_INT" = "$ACTUAL_INT" ] || { echo "npm tarball sha512 mismatch: $ACTUAL_INT != $EXPECTED_INT"; exit 1; }

echo "== Extracting and validating the helper binaries =="
rm -rf package
tar xzf platform.tgz
[ -f package/bin/vela ] || { echo "vela binary missing from package"; exit 1; }
[ -f package/bin/libexec/opencode/opencode ] || { echo "opencode companion missing from package"; exit 1; }
chmod +x package/bin/vela package/bin/libexec/opencode/opencode
file package/bin/vela | grep -q "ELF 64-bit" || { echo "vela is not an ELF x86-64 binary"; exit 1; }
ACTUAL_VER=$(./package/bin/vela --version 2>/dev/null | head -n1)
[ "$ACTUAL_VER" = "$PIN" ] || { echo "vela --version '$ACTUAL_VER' != pin '$PIN'"; exit 1; }
FC=$(./package/bin/libexec/opencode/opencode --version 2>&1 | head -n1 | wc -c)
[ "$FC" -gt 1 ] || { echo "opencode companion does not run"; exit 1; }
echo "vela $ACTUAL_VER OK, opencode companion runs"

echo "== Installing helper tree into resources-extra/open-design/bin =="
mkdir -p "$PIN_TARGET"
rm -rf "$PIN_TARGET/bin"
cp -a package/bin "$PIN_TARGET/bin"
ls -la "$PIN_TARGET/bin" "$PIN_TARGET/bin/libexec/opencode"
echo "Agent-runtime helpers installed (vela $PIN + Linux opencode companion)"
