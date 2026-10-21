#!/usr/bin/env bash
set -euo pipefail
umask 022
here=$(cd "$(dirname "$0")" && pwd)
tool="$PRIVATE_TASK_DIR/bison"
mkdir "$tool"
python3 "$here/dependencies.py" bison unused "$tool/source.tar.gz"
tar -xzf "$tool/source.tar.gz" -C "$tool" --strip-components=1
(
  cd "$tool"
  # Match gnulib's macOS handling: avoid %n in writable format strings.
  # https://mail.gnome.org/archives/commits-list/2017-September/msg09646.html
  patch --batch --forward --fuzz=0 -p1 < "$here/bison-macos.patch"
  ./configure --prefix="$tool/install" --disable-nls
  make -j2
  make install
)
"$tool/install/bin/bison" --version
