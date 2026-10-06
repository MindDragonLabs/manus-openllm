#!/usr/bin/env bash
set -euo pipefail

# Tests must be independent of the invoking shell's environment: a BASH_ENV
# file (agent harnesses and CI images often set one) can prepend directories to
# PATH before this script runs, shadowing our mock binaries with the host's
# real claude/codex/grok and silently breaking every PATH-based assertion.
unset BASH_ENV ENV
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/work"

cat > "$tmp/bin/openllm" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  version) [ "${FAKE_VERSION_FAIL:-0}" != 1 ] || exit 1; printf 'openllm-test 1.0\n' ;;
  status) printf 'status\n' >> "$STATUS_LOG"; [ "${FAKE_STATUS_FAIL:-0}" != 1 ] ;;
  claude|codex|grok|hermes|opencode)
    { printf '%s|%s|%s|%s|%s|' "$1" "${OPENLLM_GATEWAY-unset}" "${SUPERMEMORY_AUTO_SAVE-unset}" "${SUPERMEMORY_AUTO_RECALL-unset}" "$PWD"
      printf '<%s>' "$@"
      printf '\n'; } >> "$RUN_LOG"
    ;;
  *) exit 1 ;;
esac
EOF
for c in claude codex grok hermes opencode; do
cat > "$tmp/bin/$c" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ] && [ "${FAKE_CLIENT_FAIL:-0}" != 1 ]; then
  printf 'client-test 1.0\n'
else
  exit 1
fi
EOF
done
cat > "$tmp/bin/uname" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = -s ] && [ -n "${FAKE_OS:-}" ]; then
  printf '%s\n' "$FAKE_OS"
else
  /usr/bin/uname "$@"
fi
EOF
chmod +x "$tmp/bin/openllm" "$tmp/bin/claude" "$tmp/bin/codex" "$tmp/bin/grok" "$tmp/bin/hermes" "$tmp/bin/opencode" "$tmp/bin/uname"
export PATH="$tmp/bin:/usr/bin:/bin"
export RUN_LOG="$tmp/launch.log" STATUS_LOG="$tmp/status.log"

bash -n "$root/scripts/client-list.sh" "$root/scripts/doctor.sh" "$root/scripts/launch-client.sh" "$root/scripts/launch-claude.sh"

# --- doctor.sh ---
"$root/scripts/doctor.sh" > "$tmp/doctor.out"
grep -q 'Binary preflight passed' "$tmp/doctor.out"
grep -q 'Local daemon status: command succeeded' "$tmp/doctor.out"
for c in claude codex grok hermes opencode; do
  grep -q "^$c: client-test 1.0 ($tmp/bin/$c)" "$tmp/doctor.out"
done
# Doctor accepts an explicit subset and reports per-client results.
"$root/scripts/doctor.sh" codex > "$tmp/doctor-codex.out"
grep -q '^codex: client-test 1.0' "$tmp/doctor-codex.out"
if grep -q '^grok:' "$tmp/doctor-codex.out"; then
  printf 'doctor reported an unrequested client.\n' >&2; exit 1
fi
FAKE_STATUS_FAIL=1 "$root/scripts/doctor.sh" > "$tmp/doctor-stopped.out"
grep -q 'Local daemon status: unavailable or stopped' "$tmp/doctor-stopped.out"
for setting in FAKE_VERSION_FAIL FAKE_CLIENT_FAIL; do
  if env "$setting=1" "$root/scripts/doctor.sh" > "$tmp/failure.out" 2>&1; then
    printf '%s unexpectedly passed.\n' "$setting" >&2; exit 1
  fi
done
if FAKE_OS=Windows "$root/scripts/doctor.sh" > "$tmp/failure.out" 2>&1; then
  printf 'Unsupported OS unexpectedly passed.\n' >&2; exit 1
fi
# Always-on and unknown clients are refused with guidance, and fail the doctor.
"$root/scripts/doctor.sh" raycast > "$tmp/doctor-raycast.out" 2>&1 && {
  printf 'Always-on client unexpectedly passed doctor.\n' >&2; exit 1; }
grep -q 'always-on client' "$tmp/doctor-raycast.out"
"$root/scripts/doctor.sh" nosuch > "$tmp/doctor-unknown.out" 2>&1 && {
  printf 'Unknown client unexpectedly passed doctor.\n' >&2; exit 1; }
grep -q 'Unknown client: nosuch' "$tmp/doctor-unknown.out"
# A missing client binary (not on PATH, no fallback location) fails the doctor
# without touching the network or installing anything.
mkdir -p "$tmp/sparse"
ln -s "$tmp/bin/openllm" "$tmp/sparse/openllm"
ln -s "$tmp/bin/uname" "$tmp/sparse/uname"
mkdir -p "$tmp/missing-home"
HOME="$tmp/missing-home" PATH="$tmp/sparse:/usr/bin:/bin" "$root/scripts/doctor.sh" grok > "$tmp/doctor-missing.out" 2>&1 && {
  printf 'Missing client binary unexpectedly passed doctor.\n' >&2; exit 1; }
grep -q '^grok: not installed' "$tmp/doctor-missing.out"
# Fallback binary locations are honored when the client is not on PATH but
# exists at a registry location.
mkdir -p "$tmp/fallback-home/.grok/bin" "$tmp/fallback-home/bin"
cp "$tmp/bin/grok" "$tmp/fallback-home/.grok/bin/grok"
ln -s "$tmp/bin/openllm" "$tmp/fallback-home/bin/openllm"
ln -s "$tmp/bin/uname" "$tmp/fallback-home/bin/uname"
chmod +x "$tmp/fallback-home/.grok/bin/grok"
HOME="$tmp/fallback-home" PATH="$tmp/fallback-home/bin:/usr/bin:/bin" "$root/scripts/doctor.sh" grok > "$tmp/doctor-fallback.out"
grep -q '^grok: client-test 1.0 ('"$tmp/fallback-home"'/\.grok/bin/grok)' "$tmp/doctor-fallback.out"

# --- launch-client.sh: every session client routes through openllm ---
for c in claude codex grok hermes opencode; do
  (cd "$tmp/work" && "$root/scripts/launch-client.sh" --client "$c" --route cloud -- --flag "arg $c")
  grep -Fqx "$c|cloud|0|0|$tmp/work|<$c><--flag><arg $c>" "$RUN_LOG"
done
# Default client is claude; launch-claude.sh remains a compatible wrapper.
(cd "$tmp/work" && "$root/scripts/launch-client.sh" --route cloud -- --resume 'two words')
grep -Fqx "claude|cloud|0|0|$tmp/work|<claude><--resume><two words>" "$RUN_LOG"
(cd "$tmp/work" && "$root/scripts/launch-claude.sh" --route cloud -- --resume 'two words')
grep -Fqx "claude|cloud|0|0|$tmp/work|<claude><--resume><two words>" "$RUN_LOG"
(cd "$tmp/work" && "$root/scripts/launch-client.sh" --route local)
grep -Fqx "claude|local|0|0|$tmp/work|<claude>" "$RUN_LOG"
# auto must override *both* inherited explicit routes rather than silently preserve them.
for inherited in cloud local; do
  (cd "$tmp/work" && OPENLLM_GATEWAY="$inherited" "$root/scripts/launch-client.sh" --route auto)
  [ "$(tail -n 1 "$RUN_LOG")" = "claude|unset|0|0|$tmp/work|<claude>" ]
done
(cd "$tmp/work" && "$root/scripts/launch-client.sh" --allow-memory)
[ "$(tail -n 1 "$RUN_LOG")" = "claude|unset|1|1|$tmp/work|<claude>" ]
count="$(wc -l < "$RUN_LOG")"
if (cd "$tmp/work" && FAKE_STATUS_FAIL=1 "$root/scripts/launch-client.sh" --route local > "$tmp/failure.out" 2>&1); then
  printf 'Stopped local daemon unexpectedly launched.\n' >&2; exit 1
fi
[ "$(wc -l < "$RUN_LOG")" = "$count" ]
for args in '--route invalid' '--route' '--client' '--unknown' '--client nosuch'; do
  # These are fixed test values, not user-provided shell input.
  if (cd "$tmp/work" && "$root/scripts/launch-client.sh" $args > "$tmp/failure.out" 2>&1); then
    printf 'Bad launcher option unexpectedly passed: %s\n' "$args" >&2; exit 1
  fi
done
# Always-on clients are refused with guidance, never launched.
for c in raycast chatgpt; do
  if (cd "$tmp/work" && "$root/scripts/launch-client.sh" --client "$c" > "$tmp/failure-$c.out" 2>&1); then
    printf 'Always-on client unexpectedly launched: %s\n' "$c" >&2; exit 1
  fi
  grep -q "Refusing always-on client: $c" "$tmp/failure-$c.out"
done
# A session client missing from PATH and fallback locations is refused.
if (cd "$tmp/work" && HOME="$tmp/missing-home" PATH="$tmp/sparse:/usr/bin:/bin" "$root/scripts/launch-client.sh" --client grok > "$tmp/failure.out" 2>&1); then
  printf 'Missing client binary unexpectedly launched.\n' >&2; exit 1
fi
grep -q 'grok client binary not found' "$tmp/failure.out"
# A client present only at a fallback location still launches.
(cd "$tmp/work" && HOME="$tmp/fallback-home" PATH="$tmp/fallback-home/bin:/usr/bin:/bin" "$root/scripts/launch-client.sh" --client grok)
grep -Fqx "grok|unset|0|0|$tmp/work|<grok>" "$RUN_LOG"
"$root/scripts/launch-client.sh" --help > "$tmp/help.out"
grep -q -- '--allow-memory' "$tmp/help.out"
grep -q -- '--client' "$tmp/help.out"
if (cd "$root" && "$root/scripts/launch-client.sh" > "$tmp/failure.out" 2>&1); then
  printf 'Starter checkout unexpectedly accepted as workspace.\n' >&2; exit 1
fi
grep -q 'Refusing to launch in the starter checkout' "$tmp/failure.out"
(cd "$root" && "$root/scripts/launch-client.sh" --allow-starter-dir)
if PATH="$tmp/empty" /bin/bash "$root/scripts/launch-client.sh" > "$tmp/failure.out" 2>&1; then
  printf 'Missing binaries unexpectedly passed.\n' >&2; exit 1
fi
grep -q 'OpenLLM CLI not found' "$tmp/failure.out"
# The compatibility wrapper must not reimplement option parsing: a bad option
# fails identically through it.
if (cd "$tmp/work" && "$root/scripts/launch-claude.sh" --route nonsense > "$tmp/failure.out" 2>&1); then
  printf 'Wrapper accepted a bad option.\n' >&2; exit 1
fi
grep -q 'Invalid route: nonsense' "$tmp/failure.out"

printf 'All offline mock tests passed. No real installs, logins, memory writes, or model calls.\n'
