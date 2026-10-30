#!/usr/bin/env bash
# freebuff-byok-setup.sh — connect Freebuff (freebuff.com) as the model engine
# behind Open Design's "BYOK OpenCode" runtime on Linux.
#
# What it does:
#   1. Finds the local Open Design daemon HTTP port (default 39629).
#   2. Reads your Freebuff API key from a hidden prompt (never stored in shell
#      history and never placed in project files).
#   3. Merges the key into the daemon's agentCliEnv for the opencode/byok agent
#      (GET -> modify -> PUT; the config PUT replaces whole keys, so we never
#      blind-write).
#
# After this, in Open Design pick the BYOK OpenCode runtime in the model picker
# with:
#   protocol : openai
#   base URL : https://freebuff.com/api/v1/paid
#   model    : a tool-capable Freebuff model id, e.g. gpt-6.1-sol
#   key env  : OPENAI_API_KEY
#
# Usage:
#   bash scripts/freebuff-byok-setup.sh [--port 39629] [--clear] [--key-env NAME]
#   echo "$KEY" | bash scripts/freebuff-byok-setup.sh --stdin [--port 39629]
#
set -euo pipefail

PORT_NAME="39629"
KEY_ENV="OPENAI_API_KEY"
STDIN_MODE=""
CLEAR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT_NAME="$2"; shift 2 ;;
    --key-env) KEY_ENV="$2"; shift 2 ;;
    --stdin) STDIN_MODE=1; shift ;;
    --clear) CLEAR=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

BASE="http://127.0.0.1:${PORT_NAME}"

if ! curl -sf -m 3 "$BASE/api/health" >/dev/null 2>&1; then
  echo "No Open Design daemon answered on $BASE (try --port N)." >&2
  echo "List candidate ports:  ss -ltnp | grep -iE 'Open Design|open-design'" >&2
  exit 1
fi

CURRENT_JSON="$(curl -sf -m 5 "$BASE/api/app-config")"

if [ -n "$CLEAR" ]; then
  PAYLOAD="$(printf '%s' "$CURRENT_JSON" | KEY_ENV="$KEY_ENV" python3 -c '
import json, os
cfg = json.load(sys.stdin)["config"]
agent_env = dict(cfg.get("agentCliEnv") or {})
inner = dict(agent_env.get("opencode") or {})
inner[os.environ["KEY_ENV"]] = None
agent_env["opencode"] = {k: v for k, v in inner.items() if v is not None}
print(json.dumps({"agentCliEnv": agent_env}))
')"
  curl -sf -m 5 -X PUT "$BASE/api/app-config" -H 'content-type: application/json' \
    -d "$PAYLOAD" >/dev/null
  echo "Cleared ${KEY_ENV} from the OpenDesign<->Freebuff agent env."
  exit 0
fi

if [ -n "$STDIN_MODE" ]; then
  KEY="$(python3 -c 'import sys; sys.stdout.write(sys.stdin.readline().strip())')"
else
  KEY="$(python3 -c 'import getpass,sys; sys.stdout.write(getpass.getpass(prompt="Freebuff API key (hidden): ").strip())')"
fi

if [ -z "$KEY" ]; then
  echo "No key given — nothing changed." >&2
  exit 1
fi

# Freebuff advertises its model list unauthenticated; the chat endpoint is what
# consumes the key. Verify the key in place so a typo fails here, not mid-session:
STATUS="$(curl -s -m 15 -o /tmp/fb-key-check.json -w '%{http_code}' \
  https://freebuff.com/api/v1/paid/chat/completions \
  -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"gpt-6.1-sol","messages":[{"role":"user","content":"ping"}],"max_tokens":8}')" || STATUS=000
if [ "$STATUS" != "200" ]; then
  echo "Freebuff rejected the key check (HTTP $STATUS)." >&2
  head -c 200 /tmp/fb-key-check.json 2>/dev/null || true; echo
  exit 1
fi

PAYLOAD="$(printf '%s' "$CURRENT_JSON" | KEY="$KEY" KEY_ENV="$KEY_ENV" python3 -c '
import json, os
cfg = json.load(sys.stdin)["config"]
agent_env = dict(cfg.get("agentCliEnv") or {})
inner = dict(agent_env.get("opencode") or {})
inner[os.environ["KEY_ENV"]] = os.environ["KEY"]
agent_env["opencode"] = inner
print(json.dumps({"agentCliEnv": agent_env})
)')"

curl -sf -m 5 -X PUT "$BASE/api/app-config" -H 'content-type: application/json' \
  -d "$PAYLOAD" >/dev/null

echo "Done. ${KEY_ENV} is now available to the opencode/BYOK runtime."
echo "Next, in Open Design's model picker choose BYOK OpenCode with:"
echo "  protocol: openai    base URL: https://freebuff.com/api/v1/paid"
echo "  model: gpt-6.1-sol  (or deepseek-v4.1-flash for a coding-tuned option)"
echo "To remove: bash $0 --clear --port $PORT_NAME"
