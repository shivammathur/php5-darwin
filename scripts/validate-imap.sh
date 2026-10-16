#!/usr/bin/env bash
set -euo pipefail
version=${1:?Specify 53, 54, or 55}
php="/opt/local/bin/php$version"
extension="$(/opt/local/bin/php-config"$version" --extension-dir)/imap.so"
tests="$(cd "$(dirname "$0")/tests" && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
/usr/bin/clang -dynamiclib -Wall -Wextra -Werror \
  "$tests/imap-no-startup-dns.c" -o "$work/no-dns.dylib"
status=0
DYLD_INSERT_LIBRARIES="$work/no-dns.dylib" "$php" -n \
  -r 'stream_socket_client("tcp://localhost:9");' >"$work/probe.log" 2>&1 || status=$?
[[ "$status" = 86 ]] || { cat "$work/probe.log"; echo 'DNS probe was not active' >&2; exit 1; }
DYLD_INSERT_LIBRARIES="$work/no-dns.dylib" "$php" -n -d "extension=$extension" \
  -r 'if (!extension_loaded("imap")) { exit(1); } echo "IMAP startup performed no DNS lookup\n";'
python3 "$tests/test-imap-client.py" "$php" "$extension"
/usr/bin/time -p "$php" -r 'echo PHP_VERSION, "\n";'
