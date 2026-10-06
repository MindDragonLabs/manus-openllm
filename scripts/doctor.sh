#!/usr/bin/env bash
# Read-only prerequisites; never inspect credentials or mutate configuration.
set -u

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) printf 'Unsupported host: this starter targets macOS and Linux.\n' >&2; exit 2 ;;
esac

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
  printf 'OpenLLM CLI: not installed or not on PATH.\n' >&2
  fail=1
fi

if command -v claude >/dev/null 2>&1; then
  if version="$(claude --version 2>/dev/null)"; then
    printf 'Claude Code: %s\n' "$version"
  else
    printf 'Claude Code: found, but version check failed; inspect the installation.\n' >&2
    fail=1
  fi
else
  printf 'Claude Code: not installed or not on PATH.\n' >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf 'Binary preflight passed. Pairing, provider availability, MCP and inference are NOT verified.\n'
else
  printf 'Preflight incomplete. Ask before installing or changing software.\n' >&2
fi
exit "$fail"
