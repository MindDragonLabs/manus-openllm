#!/usr/bin/env bash
# Minimal official OpenLLM client launcher: no installs, credentials,
# configuration writes, or background daemons here.
set -euo pipefail

# Source the shared client vocabulary (SESSION_CLIENTS, ALWAYS_ON_CLIENTS,
# find_client_bin). Same directory as this script. Path expansion uses only
# shell builtins so an empty PATH fails at the openllm check, not here.
# shellcheck source=/dev/null
script_dir="${BASH_SOURCE[0]%/*}"
[ "$script_dir" = "${BASH_SOURCE[0]}" ] && script_dir=.
. "$script_dir/client-list.sh"

usage() {
  cat <<'EOF'
Usage: launch-client.sh [--client claude|codex|grok|hermes|opencode]
                        [--route auto|local|cloud] [--allow-memory]
                        [--allow-starter-dir] [-- CLIENT_ARGS...]

Run in the directory the client should work in. --client defaults to claude.
Everything after -- goes to the client; the official openllm overlay supplies
model routing and its stdio MCP tools without rewriting the client's config.

Always-on clients (chatgpt, raycast) are refused: openllm applies durable
configuration for those, which is a separate decision, not a launch.

auto clears any inherited route and lets the official CLI choose. local
requires a successful daemon status check; cloud selects a configured hosted
BYOK route.

Memory auto-recall and auto-save are OFF by default. --allow-memory opts in to
OpenLLM's cloud-stored memory hooks and possible additional model requests.
This command may make billable requests after prompts; obtain permission first.
EOF
}

client=claude
route=auto
allow_memory=0
allow_starter_dir=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --client)
      if [ "$#" -lt 2 ]; then printf 'Missing value for --client.\n' >&2; exit 2; fi
      client=$2
      shift 2
      ;;
    --route)
      if [ "$#" -lt 2 ]; then printf 'Missing value for --route.\n' >&2; exit 2; fi
      route=$2
      shift 2
      ;;
    --allow-memory) allow_memory=1; shift ;;
    --allow-starter-dir) allow_starter_dir=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    *) printf 'Unknown option: %s (pass client arguments after --).\n' "$1" >&2; exit 2 ;;
  esac
done

case " $SESSION_CLIENTS " in
  *" $client "*) ;;
  *)
    case " $ALWAYS_ON_CLIENTS " in
      *" $client "*)
        printf 'Refusing always-on client: %s. openllm %s applies durable host configuration; run it directly and review the OpenLLM docs first.\n' "$client" "$client" >&2
        ;;
      *)
        printf 'Unknown client: %s. Supported session clients: %s.\n' "$client" "$SESSION_CLIENTS" >&2
        ;;
    esac
    exit 2
    ;;
esac

case "$route" in
  auto) unset OPENLLM_GATEWAY ;; # Truly delegate route selection to OpenLLM.
  local|cloud) export OPENLLM_GATEWAY="$route" ;;
  *) printf 'Invalid route: %s; choose auto, local, or cloud.\n' "$route" >&2; exit 2 ;;
esac

if [ "$allow_memory" -eq 0 ]; then
  export SUPERMEMORY_AUTO_SAVE=0 SUPERMEMORY_AUTO_RECALL=0
else
  export SUPERMEMORY_AUTO_SAVE=1 SUPERMEMORY_AUTO_RECALL=1
fi

if ! command -v openllm >/dev/null 2>&1; then
  printf 'OpenLLM CLI not found. Review the official installation guide first.\n' >&2
  exit 1
fi
if ! client_bin="$(find_client_bin "$client")"; then
  printf '%s client binary not found on PATH or its usual install location. openllm reports the official install hint when it is missing.\n' "$client" >&2
  exit 1
fi

starter_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
workspace="$(pwd -P)"
printf 'Workspace: %s\n' "$workspace" >&2
if [ "$workspace" = "$starter_root" ] && [ "$allow_starter_dir" -ne 1 ]; then
  printf 'Refusing to launch in the starter checkout. Change to the intended project, or explicitly pass --allow-starter-dir for a no-target demo.\n' >&2
  exit 2
fi
if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  printf 'Git root: %s\n' "$git_root" >&2
else
  printf 'Git root: none (confirm this is the intended directory).\n' >&2
fi

if [ "$route" = local ]; then
  if ! openllm status >/dev/null 2>&1; then
    printf 'Local daemon status failed. Check OpenLLM on this host before a subscription run.\n' >&2
    exit 1
  fi
fi

printf 'Starting %s through OpenLLM (%s route; memory %s).\n' "$client" "$route" "$([ "$allow_memory" -eq 1 ] && printf on || printf off)" >&2
exec openllm "$client" "$@"
