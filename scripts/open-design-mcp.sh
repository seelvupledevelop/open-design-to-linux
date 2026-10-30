#!/usr/bin/env bash
# open-design-mcp.sh — attach Open Design's MCP server to any MCP client.
#
# Verified against the Linux port of Open Design 0.26.x (daemon MCP v0.2.0).
# Tools available once connected: list_projects, get_project, get_active_context,
# get_artifact, get_file, list_files, search_files, create_artifact, write_file,
# delete_file, create_project, delete_project, list_skills, list_plugins,
# start_run, get_run, cancel_run, list_agents, collect_brief, confirm_brief,
# start_vela_login, get_vela_login_status.
#
# MCP client config (generic):
#   { "mcpServers": { "open-design": { "command": "<path to this launcher>" } } }
#
# Session discovery, in order:
#   1. $OD_DAEMON_URL set      -> adopt env from that daemon's /api/mcp/install-info
#   2. $OD_DATA_DIR set        -> take endpoint/data-dir from the running Open
#                                 Design process whose data dir matches (its env
#                                 contains the live OD_SIDECAR_CLIENT_ENDPOINT)
#   3. otherwise               -> scan local listeners for a process answering
#                                 /api/mcp/install-info and adopt that env
set -euo pipefail

APP_BIN="${OD_APP_BIN:-/opt/Open Design/open-design}"
CLI_MJS="${OD_CLI_MJS:-/opt/Open Design/resources/app/prebundled/daemon/daemon-cli.mjs}"

[ -x "$APP_BIN" ] || { echo "Open Design binary not found: $APP_BIN" >&2; exit 1; }
[ -f "$CLI_MJS" ] || { echo "daemon-cli.mjs not found: $CLI_MJS" >&2; exit 1; }

ENV_JSON="$(/usr/bin/env python3 - <<'PYEOF'
import glob, json, os, sys, urllib.request

def session_env_from_proc(pinned_data_dir):
    best, best_start = None, -1.0
    for envp in glob.glob('/proc/[0-9]*/environ'):
        pid = envp.split('/')[2]
        try:
            raw = open(envp, 'rb').read().decode('utf-8', 'replace')
        except (OSError, PermissionError):
            continue
        env = dict(kv.split('=', 1) for kv in raw.split('\0') if '=' in kv)
        sock = env.get('OD_SIDECAR_CLIENT_ENDPOINT', '')
        dd = env.get('OD_DATA_DIR', '')
        if not (dd and sock.startswith('/tmp/od-sidecar-') and os.path.exists(sock)):
            continue
        if pinned_data_dir and dd != pinned_data_dir:
            continue
        try:
            start = os.stat(f'/proc/{pid}').st_mtime
        except OSError:
            continue
        if start > best_start:
            best_start, best = start, {k: env[k] for k in (
                'OD_DATA_DIR', 'OD_SIDECAR_CLIENT_ENDPOINT', 'OD_MCP_BOOTSTRAP_COMMAND',
                'OD_MCP_BOOTSTRAP_ARGS', 'ELECTRON_RUN_AS_NODE') if k in env}
    return best

def daemon_urls():
    if os.environ.get('OD_DAEMON_URL'):
        yield os.environ['OD_DAEMON_URL'].rstrip('/')
        return
    ports = set()
    try:
        for line in os.popen('ss -ltn 2>/dev/null').read().splitlines():
            parts = line.split()
            if len(parts) >= 4 and '127.0.0.1:' in parts[3]:
                ports.add(parts[3].rsplit(':', 1)[1])
    except Exception:
        pass
    for p in list(ports) + ['39629', '44687']:
        yield f'http://127.0.0.1:{p}'

def env_from_daemon(base):
    try:
        with urllib.request.urlopen(f'{base}/api/mcp/install-info', timeout=2) as r:
            info = json.loads(r.read() or b'{}')
        return info.get('env') or None
    except Exception:
        return None

pinned = os.environ.get('OD_DATA_DIR')
if pinned:
    found = session_env_from_proc(pinned)
    if found:
        print(json.dumps(found)); sys.exit(0)

for base in daemon_urls():
    env = env_from_daemon(base)
    if env and env.get('OD_DATA_DIR') and env.get('OD_SIDECAR_CLIENT_ENDPOINT'):
        if not pinned:
            env['OD_DATA_DIR'] = env['OD_DATA_DIR']
        print(json.dumps(env)); sys.exit(0)

sys.stderr.write('No running Open Design daemon found — start the Open Design app first,\n')
sys.stderr.write('or set OD_DAEMON_URL=http://127.0.0.1:<port> to pin it.\n')
sys.exit(1)
PYEOF
)"

# Apply the discovered env (values may contain '=' or spaces; pass through python):
eval "$(ENV_JSON="$ENV_JSON" python3 -c '
import json, os, shlex
env = json.loads(os.environ["ENV_JSON"])
for k, v in sorted(env.items()):
    print(f"export {k}={shlex.quote(str(v))}")
')"

exec "$APP_BIN" "$CLI_MJS" mcp "$@"
