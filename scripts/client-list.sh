#!/usr/bin/env bash
# Client vocabulary shared by doctor.sh and launch-client.sh. Sourced, not run.
# Keep in sync with the official CLI's client registry
# (openllmsh/cli src/clients/registry.ts, CLIENT_IDS).

# Session clients `openllm <client>` launches with a per-task overlay.
SESSION_CLIENTS="claude codex grok hermes opencode"

# Always-on clients: openllm applies durable host configuration for these, so a
# session launcher must refuse them. macOS-only in the official CLI.
ALWAYS_ON_CLIENTS="chatgpt raycast"

# Fallback binary locations mirroring the CLI registry's binPaths, for hosts
# where the client is installed but not on PATH.
client_bin_paths() {
  case "$1" in
    claude)   printf '%s\n' "$HOME/.local/bin/claude" ;;
    codex)    printf '%s\n' "$HOME/.local/bin/codex" "$HOME/.codex/bin/codex" ;;
    grok)     printf '%s\n' "$HOME/.grok/bin/grok" "$HOME/.local/bin/grok" ;;
    hermes)   printf '%s\n' "$HOME/.hermes/bin/hermes" "$HOME/.local/bin/hermes" ;;
    opencode) printf '%s\n' "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode" ;;
  esac
}

# Locate a session client's binary: PATH first, then the registry's usual
# install locations. Prints the resolved path; returns non-zero if absent.
find_client_bin() {
  if command -v "$1" >/dev/null 2>&1; then
    command -v "$1"
    return 0
  fi
  local p
  while IFS= read -r p; do
    if [ -x "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done < <(client_bin_paths "$1")
  return 1
}
