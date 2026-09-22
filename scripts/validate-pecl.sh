#!/usr/bin/env bash
set -euo pipefail
version=${1:-}
install_options=(-f)
case "$version" in
  53) expected=1.9.5 ;;
  54|55) expected=1.10.18; install_options+=(-D '') ;;
  *) echo "Usage: $0 <53|54|55>" >&2; exit 1 ;;
esac
script_dir=$(cd "$(dirname "$0")" && pwd)
pecl=/opt/local/bin/pecl
"$pecl" version | grep -Fx "PEAR Version: $expected"
php -d "include_path=/opt/local/lib/php$version" "$script_dir/tests/pear.php"
sudo env HOME="$HOME" PATH="/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$pecl" channel-update pecl.php.net
sudo env HOME="$HOME" PATH="/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$pecl" -d verbose=3 install "${install_options[@]}" msgpack-0.5.7
extension_dir=$(php -r 'echo ini_get("extension_dir");')
php -r 'if (!extension_loaded("msgpack")) { throw new Exception("msgpack not loaded"); }'
php -r 'if (msgpack_unpack(msgpack_pack(array("native" => true))) !== array("native" => true)) { throw new Exception("msgpack roundtrip failed"); }'
lipo "$extension_dir/msgpack.so" -verify_arch "$(uname -m)"
