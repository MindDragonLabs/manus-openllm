#!/usr/bin/env bash
# Compatibility wrapper: Claude Code is the default client of launch-client.sh.
set -euo pipefail
script_dir="${BASH_SOURCE[0]%/*}"
[ "$script_dir" = "${BASH_SOURCE[0]}" ] && script_dir=.
exec "$script_dir/launch-client.sh" --client claude "$@"
