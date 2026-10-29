# open-design-to-linux

Repackages the official **Open Design** macOS DMG (`nexu-io/open-design`, Apache-2.0) into
installable **Linux `.deb`** and portable **`.AppImage`** packages — automatically, on every
upstream release.

This is the same scheme as the Factory Desktop Linux artifacts pipeline:

1. A scheduled GitHub Action checks the upstream latest release once a day.
2. If it contains a new `open-design-<ver>-mac-x64.dmg` and no matching Linux release exists
   here yet, it downloads the DMG **and verifies its upstream `.sha256`**.
3. The Electron app directory (`Resources/app`: `main.cjs`, `prebundled`,
   `node_modules`) is migrated from the mac bundle.
4. macOS-only native binaries are pruned and the native modules are reinstalled for
   **linux-x64 against the bundled Electron ABI** (better-sqlite3, node-pty, sharp,
   @ffmpeg-installer/ffmpeg; onnxruntime-node already ships linux bindings).
5. An ABI smoke test loads every native module under the pinned Electron before packaging.
6. `electron-builder` produces the `.deb` and `.AppImage`, checksums are generated, and a
   release like `linux-v0.26.1` is published here.

## Install

**Debian / Ubuntu / Mint**
```bash
sudo apt install ./open-design_<version>_amd64.deb
```

**AppImage (any distro)** — note AppImages need libfuse2 on many distros:
```bash
chmod +x Open-Design-<version>-x86_64.AppImage
./Open-Design-<version>-x86_64.AppImage
```

Same version, two artifacts: the .deb integrates with your system (app menu, `/opt`),
the AppImage is portable. Do not run both side by side expecting shared state — Electron
user data (`~/.config/Open Design`) is shared by default.

## Caveats (vs upstream mac/win builds)

- Upstream's auto-updater feed is a placeholder (`updates.invalid`); the Linux builds do
  **not** self-update. Watch this repo's releases — the scheduled workflow builds new
  versions automatically, reinstall the new .deb to update.
- App builds are x86_64 only (matches the `mac-x64` DMG we port). Apple Silicon and ARM
  Linux are not covered.
- Native modules are re-installed from npm at build time with npm-published version pins
  taken from the DMG's own `package.json`; a from-source rebuild fallback runs against the
  pinned Electron headers if npm prebuilt binaries don't match the ABI.

## Local build (optional)

```bash
npm ci
npm run port -- 0.26.1        # download + port the DMG app dir
npm install --no-save electron@$(cat work/electron-version.txt)
npm run smoke
npm run package               # -> packages/*.deb, packages/*.AppImage
```

## Provenance & license

- Source artifact: official `open-design-<version>-mac-x64.dmg` from
  [nexu-io/open-design releases](https://github.com/nexu-io/open-design/releases),
  checksum-verified before use.
- Upstream project: https://open-design.ai — Apache-2.0,
  license text bundled as [packaging/LICENSE-OPEN-DESIGN.txt](packaging/LICENSE-OPEN-DESIGN.txt).
- This port is unaffiliated with upstream; report Linux-port issues here.
