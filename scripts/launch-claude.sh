#!/usr/bin/env bash
# No installs, credentials, configuration writes, or background daemons here.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: launch-claude.sh [--route auto|local|cloud] [--allow-memory]
                        [--allow-starter-dir] [-- CLAUDE_ARGS...]

Run in the directory Claude Code should work in. auto clears any inherited route
and lets the official CLI choose. local requires a successful daemon status
check; cloud selects a configured hosted BYOK route.

Memory auto-recall and auto-save are OFF by default. --allow-memory opts in to
OpenLLM's cloud-stored memory hooks and possible additional model requests.
This command may make billable requests after prompts; obtain permission first.
EOF
}

route=auto
allow_memory=0
allow_starter_dir=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --route)
      if [ "$#" -lt 2 ]; then printf 'Missing value for --route.\n' >&2; exit 2; fi
      route=$2
      shift 2
      ;;
    --allow-memory) allow_memory=1; shift ;;
    --allow-starter-dir) allow_starter_dir=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    *) printf 'Unknown option: %s (pass Claude arguments after --).\n' "$1" >&2; exit 2 ;;
  esac
done

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
if ! command -v claude >/dev/null 2>&1; then
  printf 'Claude Code not found. Review the official installation guide first.\n' >&2
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

printf 'Starting Claude Code through OpenLLM (%s route; memory %s).\n' "$route" "$([ "$allow_memory" -eq 1 ] && printf on || printf off)" >&2
exec openllm claude "$@"
