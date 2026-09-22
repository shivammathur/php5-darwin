#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
for test_version in 53 54 55; do
  (
    install_checked=false
    # Invoked indirectly by the sourced validation script; no PECL install runs.
    # shellcheck disable=SC2329
    function /opt/local/bin/pecl() {
      [[ "$1" = version ]]
      if [[ "$test_version" = 53 ]]; then
        echo 'PEAR Version: 1.9.5'
      else
        echo 'PEAR Version: 1.10.18'
      fi
    }
    sudo() {
      [[ "$1" = env && "$2" = HOME=* && "$3" = PATH=* && "$4" = /opt/local/bin/pecl ]]
      shift 4
      if [[ "$1" = channel-update ]]; then
        [[ $# = 2 && "$2" = pecl.php.net ]]
      else
        [[ "$1" = -d && "$2" = verbose=3 && "$3" = install && "$4" = -f ]]
        shift 4
        if [[ "$test_version" != 53 ]]; then
          [[ $# = 3 && "$1" = -D && "$2" = '' ]]
          shift 2
        fi
        [[ $# = 1 && "$1" = msgpack-0.5.7 ]]
        install_checked=true
      fi
    }
    php() {
      if [[ "$1" = -r && "$2" = 'echo ini_get("extension_dir");' ]]; then
        echo /tmp/mock-extension-dir
      fi
    }
    lipo() {
      [[ $# = 3 && "$1" = /tmp/mock-extension-dir/msgpack.so && "$2" = -verify_arch && "$3" = "$(uname -m)" ]]
    }
    source "$repo/scripts/validate-pecl.sh" "$test_version"
    [[ "$install_checked" = true ]]
    printf 'PHP %s exact PECL arguments passed under Bash %s\n' "$test_version" "$BASH_VERSION"
  )
done
