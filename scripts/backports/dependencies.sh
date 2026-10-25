#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/backports/common.sh
. "$here/common.sh"
config="$here/project.json"
kind=$1 name=$2 destination=$3
case "$kind" in
  macports-package)
    expected=$(jq -er --arg name "$name" '.dependencies.macports_packages[$name]' "$config")
    url="https://github.com/macports/macports-base/releases/download/v2.12.6/$name"
    ;;
  bison)
    expected=$(jq -er .dependencies.bison_sha256 "$config")
    version=$(jq -er .dependencies.bison_version "$config")
    url="https://ftp.gnu.org/gnu/bison/bison-$version.tar.gz"
    ;;
  ports-tree)
    expected=$(jq -er .dependencies.macports_ports_sha256 "$config")
    commit=$(jq -er .dependencies.macports_ports_commit "$config")
    url="https://github.com/macports/macports-ports/archive/$commit.tar.gz"
    ;;
  *) fail "Unknown dependency: $kind" ;;
esac
download "$url" "$destination" "$expected"
