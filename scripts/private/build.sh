#!/usr/bin/env bash
set -euo pipefail
umask 022
here=$(cd "$(dirname "$0")" && pwd)
[[ "$(uname -m)" = "$EXPECTED_ARCHITECTURE" ]]
command -v zstd >/dev/null || brew install zstd
[[ ! -d /opt/local ]] || sudo mv /opt/local "$PRIVATE_TASK_DIR/opt-local.preinstalled"
python3 "$here/dependencies.py" macports-package "$MACPORTS_PACKAGE" "$PRIVATE_TASK_DIR/macports.pkg"
sudo installer -pkg "$PRIVATE_TASK_DIR/macports.pkg" -target /
python3 "$here/dependencies.py" ports-tree unused "$PRIVATE_TASK_DIR/ports.tar.gz"
mkdir "$PRIVATE_TASK_DIR/ports"
tar -xzf "$PRIVATE_TASK_DIR/ports.tar.gz" --strip-components=1 -C "$PRIVATE_TASK_DIR/ports"
export PORTS_ROOT=/opt/local/var/macports/sources/private-ports
sudo mv "$PRIVATE_TASK_DIR/ports" "$PORTS_ROOT"
sudo chmod -R a+rX "$PORTS_ROOT"
sudo chown -R "$(id -u):$(id -g)" "$PORTS_ROOT"
printf 'file://%s [default]\n' "$PORTS_ROOT" | sudo tee /opt/local/etc/macports/sources.conf >/dev/null
python3 "$BUILD_REPOSITORY/scripts/enable-legacy-macports.py" "$PORTS_ROOT"
cp "$BUILD_REPOSITORY/scripts/ports/php-Twig/Portfile" "$PORTS_ROOT/php/php-Twig/Portfile"
(cd "$PORTS_ROOT" && /opt/local/bin/portindex)
autoconf=autoconf269
[[ "$PHP_VERSION" = 5.3 ]] && autoconf=autoconf213
sudo /opt/local/bin/port -N install "$autoconf"
bash "$here/build-bison.sh"
export PRIVATE_BISON="$PRIVATE_TASK_DIR/bison-prefix/bin/bison"
# Only /opt/local and this job's private workspace are modified.
sudo env \
  "SOURCE_ARCHIVE=$SOURCE_ARCHIVE" \
  "MITIGATION_PATCH=$MITIGATION_PATCH" \
  "SOURCE_SHA256=$SOURCE_SHA256" \
  "SOURCE_ROOT=$SOURCE_ROOT" \
  "PHP_VERSION=$PHP_VERSION" \
  "PHP_FULL_VERSION=$PHP_FULL_VERSION" \
  "PRIVATE_TASK_DIR=$PRIVATE_TASK_DIR" \
  "PORTS_ROOT=$PORTS_ROOT" \
  "REPORT_DIR=$REPORT_DIR" \
  "BUILD_REPOSITORY=$BUILD_REPOSITORY" \
  "PRIVATE_BISON=$PRIVATE_BISON" \
  "$(command -v python3)" "$here/prepare-macports.py"
(cd "$PORTS_ROOT" && /opt/local/bin/portindex)
export NATIVE_BUILD_DIR="$REPORT_DIR/native"
# Full MacPorts logs are collected even on build failure.
trap 'sudo tar -czf "$REPORT_DIR/macports-logs.tar.gz" -C /opt/local/var/macports logs 2>/dev/null || true; sudo chown -R "$(id -u):$(id -g)" "$REPORT_DIR"' EXIT
bash "$BUILD_REPOSITORY/scripts/build-native-cache.sh" "${PHP_VERSION/./}" "$OUTPUT_DIR"
/opt/local/bin/port -q installed active > "$REPORT_DIR/installed-ports.txt"
