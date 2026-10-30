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
   @ffmpeg-installer/ffmpeg; onnxruntime-node already ships linux bindings). The
   agent-runtime helpers (`vela` + its `libexec/opencode/opencode` companion) are bundled
   as official **linux-x64 npm builds**, version-pinned to upstream's own pack tool
   (`tools/pack/package.json` at the release tag) and checksum-verified.
5. An ABI smoke test loads every native module under the pinned Electron before packaging.
6. `electron-builder` produces the `.deb` and `.AppImage`, checksums are generated, and a
   release like `linux-v0.26.1` is published here.

The Actions pipeline lives in this repo's folder
[.github/workflows/auto-build-upstream.yml](.github/workflows/auto-build-upstream.yml) —
that is where every new `.deb` is created. **Releases other than the tested one listed
below are built by GitHub Actions and are NOT tested** — treat them as build-verified
(checksums + ABI smoke test pass) but manually untested.

## Tested releases (Linux Mint)

| Release | Status |
|---|---|
| **linux-v0.26.1** | ✅ Installed and launched on Linux Mint (Ubuntu 24.04 base): deb installs cleanly, menu entry works, app boots, sidecar supervisor runs (Electron-ABI native modules verified); Linux agent-runtime helpers bundled and verified at the daemon's resolution paths — `vela --version` = 0.1.7, exactly upstream's pack-tool pin |
| any other release | ⚠️ Auto-built by GitHub Actions — **not tested**, see above |

Keep this table current: whenever a new release has been tested on Linux Mint, list it here.

## Install

**Debian / Ubuntu / Linux Mint**
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

### Where it is installed (deb)

| What | Where |
|---|---|
| App binary | `/opt/Open Design/open-design` |
| Application files (resources, web-standalone server, open-design assets) | `/opt/Open Design/` |
| Menu entry / .desktop file | `/usr/share/applications/open-design.desktop` |
| App data (settings, projects, databases) | `~/.config/Open Design` |
| Package name (for `apt remove`/`apt purge`) | `open-design` |

The AppImage installs nothing; it runs from wherever you place the file and uses the same
`~/.config/Open Design` data directory.

## Use Freebuff as the model engine (BYOK)

Open Design ships a **BYOK OpenCode** agent runtime that accepts any
OpenAI-compatible endpoint — including [Freebuff](https://freebuff.com). With
bridge connected, Open Design's "What would you like to create?" sessions run
on your own Freebuff credits and models (e.g. the Sol family, `gpt-6.1-sol`),
instead of the built-in AMR runtime.

1. Create a personal API key: **freebuff.com → Account → Developer API**
   (Desktop build: Account → Developer API).
2. Seed the key into the daemon's agent env (hidden prompt, one command):
   ```bash
   bash scripts/freebuff-byok-setup.sh
   ```
3. In Open Design's model picker choose **BYOK OpenCode** and enter:
   - protocol: **openai**
   - base URL: **https://freebuff.com/api/v1/paid**
   - model: a **tool-capable** Freebuff model id, e.g. `gpt-6.1-sol`
   - key env: `OPENAI_API_KEY`

Tool capability matters: agentic sessions only work with models whose
`toolCalls: true`. At the time of writing the Freebuff model list marks these
as tool-capable: `deepseek-v4.1-flash` (the only streaming + tool model),
`gpt-6.1-sol`, `gpt-6-luna`, `gemini-3.8-flash`, `gemini-4-argon`,
`claude-haiku-5-5`, `qwen3.8-max`, `minimax-m3`, `claude-fable-5-1`.
Everything else answers plain chat fine but cannot drive an agentic session.

`scripts/freebuff-byok-setup.sh --clear` removes the stored key again. The
helper only touches the machine-local daemon config (`agentCliEnv` in
`~/.config/Open Design/.../data/app-config.json`); the key never lands in this
repository.

Freebuff as an MCP server for Open Design (`od mcp live-artifacts`) and the
reverse direction — publishing Open Design exports (HTML) on Freebuff Sites —
are separate, follow-up integrations.

## Read/write Open Design from agents (MCP server)

Open Design ships an MCP server (stdio, `daemon-cli.mjs mcp`). Attach it to any
MCP-capable client with the bundled launcher — it auto-discovers the running
daemon and the live sidecar endpoint (no hardcoded ports or sockets):

```bash
install -m755 scripts/open-design-mcp.sh ~/.local/bin/open-design-mcp
```

Client config (Claude Desktop, Cline, codex, any stdio-MCP client):

```json
{ "mcpServers": { "open-design": { "command": "/home/USER/.local/bin/open-design-mcp" } } }
```

Session discovery order: `OD_DAEMON_URL` (explicit) → the running Open Design
process env whose `OD_DATA_DIR` matches → scan local listeners for the daemon
that answers `/api/mcp/install-info`. Without the desktop app running, the MCP
server bootstraps its own headless daemon.

Tools exposed (22): read — `list_projects`, `get_project`, `get_active_context`,
`get_artifact`, `get_file`, `list_files`, `search_files`; write — `write_file`,
`create_artifact`, `create_project`, `delete_file`, `delete_project`; runs —
`start_run`, `get_run`, `cancel_run`, `list_agents`; metadata — `list_skills`,
`list_plugins`; auth/brief — `start_vela_login`, `get_vela_login_status`,
`collect_brief`, `confirm_brief`.

Verified on this port: MCP handshake + `tools/list` + a live `list_projects`
returning real projects. Note upstream's server instructions request the
product naming "OpenDesign Cloud and Local Codex" in user-facing replies.

## Caveats (vs upstream mac/win builds)

- Agent CLIs installed via **snap** can break the tools panel's detection: the daemon
  probes each CLI with a 3-second timeout, and snap-shim cold starts can exceed it
  (reported as "found but is not executable") and its Install button links the vendor
  homepage, which defaults to the macOS download. Fix pattern: symlink the snap's real
  ELF into a dirs Open Design searches first, e.g.
  `ln -sfn /snap/antigravity-cli/current/bin/agy ~/.local/bin/agy` (survives snap
  refreshes), then rescan in the app.
- Sign-in hands off back to the app from the browser via `xdg-open opendesign://…`.
  The deb's desktop entry registers that scheme handler (`MimeType`), so it works out
  of the box on a fresh install. The AppImage registers nothing itself — run once:
  `xdg-mime default open-design.desktop x-scheme-handler/opendesign`.
- Agent-runtime helpers are bundled Linux builds from npm (`@powerformer/vela-cli-linux-x64`
  at the version upstream's pack tool pins). Version drift between the app and the helper
  APIs is possible if upstream changes its pin expecting newer helper capability; report
  agent-runtime errors here with the daemon log.
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
npm run natives               # GNU/Linux native modules against the bundled Electron ABI
npm run smoke
npm run package               # -> packages/*.deb, packages/*.AppImage
```

Plus, separately (also run by the workflow right after the port):
```bash
npm run helpers -- 0.26.1    # vela + opencode linux helpers from npm, upstream-pinned
```

## Provenance & license

- Source artifact: official `open-design-<version>-mac-x64.dmg` from
  [nexu-io/open-design releases](https://github.com/nexu-io/open-design/releases),
  checksum-verified before use.
- Upstream project: https://open-design.ai — Apache-2.0,
  license text bundled as [packaging/LICENSE-OPEN-DESIGN.txt](packaging/LICENSE-OPEN-DESIGN.txt).
- This port is unaffiliated with upstream; report Linux-port issues here.
