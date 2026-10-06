#!/usr/bin/env bash
# Read-only prerequisites; never inspect credentials or mutate configuration.
# Usage: doctor.sh [client ...]   (default: all session clients)
set -u

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) printf 'Unsupported host: this starter targets macOS and Linux.\n' >&2; exit 2 ;;
esac

# Source the shared client vocabulary (SESSION_CLIENTS, ALWAYS_ON_CLIENTS,
# find_client_bin). Same directory as this script. Builtins only (see
# launch-client.sh for why).
# shellcheck source=/dev/null
script_dir="${BASH_SOURCE[0]%/*}"
[ "$script_dir" = "${BASH_SOURCE[0]}" ] && script_dir=.
. "$script_dir/client-list.sh"

fail=0
printf 'Host: %s / %s\n' "$(uname -s)" "$(uname -m)"
if command -v openllm >/dev/null 2>&1; then
  if version="$(openllm version 2>/dev/null)"; then
    printf 'OpenLLM CLI: %s\n' "$version"
  else
    printf 'OpenLLM CLI: found, but version check failed; inspect the installation.\n' >&2
    fail=1
  fi
  # Status is a read-only daemon check. Do not print its possibly sensitive output.
  if openllm status >/dev/null 2>&1; then
    printf 'Local daemon status: command succeeded; verify provider pairing separately.\n'
  else
    printf 'Local daemon status: unavailable or stopped. Cloud BYOK may still work.\n'
  fi
else
  printf 'OpenLLM CLI: not installed or on PATH.\n' >&2
  fail=1
fi

clients="${*:-$SESSION_CLIENTS}"
for client in $clients; do
  case " $SESSION_CLIENTS " in
    *" $client "*) ;;
    *)
      case " $ALWAYS_ON_CLIENTS " in
        *" $client "*)
          printf '%s: always-on client (durable config), not launched by this starter.\n' "$client" >&2
          ;;
        *) printf 'Unknown client: %s. Supported session clients: %s.\n' "$client" "$SESSION_CLIENTS" >&2 ;;
      esac
      fail=1
      continue
    ;;
  esac
  if bin="$(find_client_bin "$client")"; then
    # Capture without a pipe: piping through head would replace the client's
    # exit status with head's and turn a failing --version into a pass.
    if version="$("$bin" --version 2>/dev/null)" && [ -n "$version" ]; then
      version="${version%%$'\n'*}"
      printf '%s: %s (%s)\n' "$client" "$version" "$bin"
    else
      printf '%s: found at %s, but version check failed; inspect the installation.\n' "$client" "$bin" >&2
      fail=1
    fi
  else
    printf '%s: not installed (checked PATH and its usual install locations).\n' "$client" >&2
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  printf 'Binary preflight passed. Pairing, provider availability, MCP and inference are NOT verified.\n'
else
  printf 'Preflight incomplete: this starter requires the full session-client set (claude, codex, grok, hermes, opencode) to be installed. Complete the missing installs with the user'"'"'s permission before launching. Ask before installing or changing software.\n' >&2
fi
exit "$fail"
