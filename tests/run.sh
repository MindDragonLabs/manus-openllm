#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/work"

cat > "$tmp/bin/openllm" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  version) [ "${FAKE_VERSION_FAIL:-0}" != 1 ] || exit 1; printf 'openllm-test 1.0\n' ;;
  status) printf 'status\n' >> "$STATUS_LOG"; [ "${FAKE_STATUS_FAIL:-0}" != 1 ] ;;
  claude)
    { printf '%s|%s|%s|%s|' "${OPENLLM_GATEWAY-unset}" "${SUPERMEMORY_AUTO_SAVE-unset}" "${SUPERMEMORY_AUTO_RECALL-unset}" "$PWD"
      printf '<%s>' "$@"
      printf '\n'; } >> "$RUN_LOG"
    ;;
  *) exit 1 ;;
esac
EOF
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ] && [ "${FAKE_CLAUDE_FAIL:-0}" != 1 ]; then
  printf 'claude-test 1.0\n'
else
  exit 1
fi
EOF
cat > "$tmp/bin/uname" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = -s ] && [ -n "${FAKE_OS:-}" ]; then
  printf '%s\n' "$FAKE_OS"
else
  /usr/bin/uname "$@"
fi
EOF
chmod +x "$tmp/bin/openllm" "$tmp/bin/claude" "$tmp/bin/uname"
export PATH="$tmp/bin:/usr/bin:/bin"
export RUN_LOG="$tmp/launch.log" STATUS_LOG="$tmp/status.log"

bash -n "$root/scripts/doctor.sh" "$root/scripts/launch-claude.sh"
"$root/scripts/doctor.sh" > "$tmp/doctor.out"
grep -q 'Binary preflight passed' "$tmp/doctor.out"
grep -q 'Local daemon status: command succeeded' "$tmp/doctor.out"
FAKE_STATUS_FAIL=1 "$root/scripts/doctor.sh" > "$tmp/doctor-stopped.out"
grep -q 'Local daemon status: unavailable or stopped' "$tmp/doctor-stopped.out"
for setting in FAKE_VERSION_FAIL FAKE_CLAUDE_FAIL; do
  if env "$setting=1" "$root/scripts/doctor.sh" > "$tmp/failure.out" 2>&1; then
    printf '%s unexpectedly passed.\n' "$setting" >&2; exit 1
  fi
done
if FAKE_OS=Windows "$root/scripts/doctor.sh" > "$tmp/failure.out" 2>&1; then
  printf 'Unsupported OS unexpectedly passed.\n' >&2; exit 1
fi

(cd "$tmp/work" && "$root/scripts/launch-claude.sh" --route cloud -- --resume 'two words')
grep -Fqx "cloud|0|0|$tmp/work|<claude><--resume><two words>" "$RUN_LOG"
(cd "$tmp/work" && "$root/scripts/launch-claude.sh" --route local)
grep -Fqx "local|0|0|$tmp/work|<claude>" "$RUN_LOG"
# auto must override *both* inherited explicit routes rather than silently preserve them.
for inherited in cloud local; do
  (cd "$tmp/work" && OPENLLM_GATEWAY="$inherited" "$root/scripts/launch-claude.sh" --route auto)
  [ "$(tail -n 1 "$RUN_LOG")" = "unset|0|0|$tmp/work|<claude>" ]
done
(cd "$tmp/work" && "$root/scripts/launch-claude.sh" --allow-memory)
[ "$(tail -n 1 "$RUN_LOG")" = "unset|1|1|$tmp/work|<claude>" ]
count="$(wc -l < "$RUN_LOG")"
if (cd "$tmp/work" && FAKE_STATUS_FAIL=1 "$root/scripts/launch-claude.sh" --route local > "$tmp/failure.out" 2>&1); then
  printf 'Stopped local daemon unexpectedly launched.\n' >&2; exit 1
fi
[ "$(wc -l < "$RUN_LOG")" = "$count" ]
for args in '--route invalid' '--route' '--unknown'; do
  # These are fixed test values, not user-provided shell input.
  if (cd "$tmp/work" && "$root/scripts/launch-claude.sh" $args > "$tmp/failure.out" 2>&1); then
    printf 'Bad launcher option unexpectedly passed: %s\n' "$args" >&2; exit 1
  fi
done
"$root/scripts/launch-claude.sh" --help > "$tmp/help.out"
grep -q -- '--allow-memory' "$tmp/help.out"
if (cd "$root" && "$root/scripts/launch-claude.sh" > "$tmp/failure.out" 2>&1); then
  printf 'Starter checkout unexpectedly accepted as workspace.\n' >&2; exit 1
fi
grep -q 'Refusing to launch in the starter checkout' "$tmp/failure.out"
(cd "$root" && "$root/scripts/launch-claude.sh" --allow-starter-dir)
if PATH="$tmp/empty" /bin/bash "$root/scripts/launch-claude.sh" > "$tmp/failure.out" 2>&1; then
  printf 'Missing binaries unexpectedly passed.\n' >&2; exit 1
fi
grep -q 'OpenLLM CLI not found' "$tmp/failure.out"

printf 'All offline mock tests passed. No real installs, logins, memory writes, or model calls.\n'
