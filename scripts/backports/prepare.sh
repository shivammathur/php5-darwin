#!/usr/bin/env bash
set -euo pipefail
umask 022
here=$(cd "$(dirname "$0")" && pwd)
[[ "$(uname -m)" = "$EXPECTED_ARCHITECTURE" ]]
command -v zstd >/dev/null || brew install zstd
backup="$RUNNER_TEMP/opt-local.preinstalled"
state="$RUNNER_TEMP/opt-local-state"
test ! -e "$backup"
if [[ -d /opt/local ]]; then
  sudo mv /opt/local "$backup"
  echo present > "$state"
else
  echo absent > "$state"
fi
bash "$here/dependencies.sh" macports-package "$MACPORTS_PACKAGE" "$BACKPORT_TASK_DIR/macports.pkg"
sudo installer -pkg "$BACKPORT_TASK_DIR/macports.pkg" -target /
bash "$here/dependencies.sh" ports-tree unused "$BACKPORT_TASK_DIR/ports.tar.gz"
mkdir "$BACKPORT_TASK_DIR/ports"
tar -xzf "$BACKPORT_TASK_DIR/ports.tar.gz" --strip-components=1 -C "$BACKPORT_TASK_DIR/ports"
export PORTS_ROOT=/opt/local/var/macports/sources/backport-ports
sudo mv "$BACKPORT_TASK_DIR/ports" "$PORTS_ROOT"
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
export BACKPORT_BISON="$BACKPORT_TASK_DIR/bison-prefix/bin/bison"
# Only /opt/local and this job's build workspace are modified.
sudo env \
  "SOURCE_ARCHIVE=$SOURCE_ARCHIVE" \
  "SOURCE_SHA256=$SOURCE_SHA256" \
  "SOURCE_ROOT=$SOURCE_ROOT" \
  "PHP_VERSION=$PHP_VERSION" \
  "PHP_FULL_VERSION=$PHP_FULL_VERSION" \
  "BACKPORT_TASK_DIR=$BACKPORT_TASK_DIR" \
  "PORTS_ROOT=$PORTS_ROOT" \
  "REPORT_DIR=$REPORT_DIR" \
  "BUILD_REPOSITORY=$BUILD_REPOSITORY" \
  "BACKPORT_BISON=$BACKPORT_BISON" \
  "PATH=$PATH" bash "$here/prepare-macports.sh"
(cd "$PORTS_ROOT" && /opt/local/bin/portindex)
# Use the exact extension bytes already pinned in the source manifest.
# MacPorts independently checks its own Portfile checksum before extracting.
sudo mkdir -p /opt/local/var/macports/distfiles/php5-mongo
sudo cp "$MONGO_ARCHIVE" /opt/local/var/macports/distfiles/php5-mongo/mongo-1.6.16.tgz
sudo chmod 644 /opt/local/var/macports/distfiles/php5-mongo/mongo-1.6.16.tgz
