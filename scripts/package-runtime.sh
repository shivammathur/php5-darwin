#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <runtime-archive.tar.gz>" >&2
  exit 1
fi

output=$1
work_dir=${RUNTIME_WORK_DIR:-$(mktemp -d)}
downloads="$work_dir/downloads"
packages="$work_dir/packages"
runtime_root="$work_dir/runtime"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "The runtime must be assembled on an arm64 macOS runner" >&2
  exit 1
fi
/usr/bin/arch -x86_64 /usr/bin/true
test -x /opt/local/bin/php55
mkdir -p "$downloads" "$packages" "$runtime_root/opt/local/lib" "$(dirname "$output")"

download() {
  local url=$1
  local checksum=$2
  local destination="$downloads/${url##*/}"

  curl -fsSL --retry 3 -o "$destination" "$url"
  printf '%s  %s\n' "$checksum" "$destination" | shasum -a 256 -c - >&2
  printf '%s\n' "$destination"
}

add_macports_package() {
  local name=$1
  local checksum=$2
  local archive
  local library
  local package_root="$packages/${name%.tbz2}"
  shift 2

  archive=$(download "https://packages.macports.org/${name%%-*}/$name" "$checksum")
  mkdir -p "$package_root"
  tar -xjf "$archive" -C "$package_root"
  for library in "$@"; do
    test -e "$package_root/opt/local/lib/$library" || \
      test -L "$package_root/opt/local/lib/$library"
    cp -a "$package_root/opt/local/lib/$library" "$runtime_root/opt/local/lib/"
  done
}

# Use official macOS 14 x86_64 MacPorts archives. PHP itself remains x86_64 and
# runs through Rosetta, so native arm64 libraries cannot satisfy its load paths.
add_macports_package expat-2.8.3_0.darwin_23.x86_64.tbz2 e84b4ac47e583d674755b4e382a9b8dccc95157019f661397aa3a46d236bd86a \
  libexpat.1.12.3.dylib libexpat.1.dylib
add_macports_package libffi-3.4.8_0.darwin_23.x86_64.tbz2 f50fc304c0352e49b5634f126c76a952d9695519f58fd0e24a71236d2f7e272b \
  libffi.8.dylib
add_macports_package freetype-2.14.3_0.darwin_23.x86_64.tbz2 6d7fbd042d8a757d900718493104caa0c1a7c356154be4872acd93439d22d834 \
  libfreetype.6.dylib
add_macports_package gmp-6.3.0_0.darwin_23.x86_64.tbz2 8405a2ac53c809954e4761fd32ce9c1313a98243314da7b3a18d9ab12446d1b4 \
  libgmp.10.dylib
add_macports_package libpng-1.6.58_0.darwin_23.x86_64.tbz2 f34f5f0c4fc1aee3cf37982f87689db9d7171ef2dd1b32ac31e6806d0734fd03 \
  libpng16.16.dylib
add_macports_package sqlite3-3.53.4_0.darwin_23.x86_64.tbz2 1dab99308e72015417b487451e52590b9efec861db51154b337b24e95732e1cf \
  libsqlite3.3.53.4.dylib libsqlite3.0.dylib
add_macports_package libyaml-0.2.5_0.darwin_23.x86_64.tbz2 6eb3a2c9e1d7e160c386b6f802727d1bcff009b121a5e2dffb58a1ffac7c49f9 \
  libyaml-0.2.dylib
add_macports_package libzip-1.11.4_1.darwin_23.x86_64.tbz2 ee8e4c4574dd3ce22e89239a004346792aa94c7c5dd7530f41226f585698591d \
  libzip.5.5.dylib libzip.5.dylib

# PECL invokes Autoconf through phpize. Match the Autoconf 2.69 revision 5
# MacPorts recipe used when these PHP packages were built: on Darwin it uses
# /usr/bin/m4 and /usr/bin/perl. Only the commands phpize calls are packaged.
autoconf_archive=$(download \
  https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz \
  64ebcec9f8ac5b2487125a86a7760d2591ac9e1d3dbd59489633f9de62a57684)
autoconf_source="$work_dir/autoconf-source"
autoconf_dest="$work_dir/autoconf-dest"
mkdir -p "$autoconf_source" "$autoconf_dest"
tar -xJf "$autoconf_archive" -C "$autoconf_source" --strip-components=1
(
  cd "$autoconf_source"
  M4=/usr/bin/m4 PERL=/usr/bin/perl ./configure --prefix=/opt/local
  make -j"$(sysctl -n hw.ncpu)"
  make DESTDIR="$autoconf_dest" install
)
mkdir -p "$runtime_root/opt/local/bin" \
  "$runtime_root/opt/local/share/doc/autoconf-2.69"
for tool in autoconf autoheader autom4te; do
  cp "$autoconf_dest/opt/local/bin/$tool" "$runtime_root/opt/local/bin/"
done
cp -a "$autoconf_dest/opt/local/share/autoconf" "$runtime_root/opt/local/share/"
cp "$autoconf_source/COPYINGv3" "$autoconf_source/COPYING.EXCEPTION" \
  "$runtime_root/opt/local/share/doc/autoconf-2.69/"

# The current libxslt archive links to libxml2.16. PHP 5 links to libxml2.2 and
# passes libxml objects into XSL, so retain the exact 1.1.34 ABI used originally.
libxslt_archive=$(download \
  https://distfiles.macports.org/libxslt/libxslt-1.1.34.tar.gz \
  98b1bd46d6792925ad2dfe9a87452ea2adebf69dcb9919ffd55bf926a7f93f7f)
libxslt_source="$work_dir/libxslt-source"
libxslt_dest="$work_dir/libxslt-dest"
mkdir -p "$libxslt_source" "$libxslt_dest"
tar -xzf "$libxslt_archive" -C "$libxslt_source" --strip-components=1
sed -i '' 's/need_relink=yes/need_relink=no/g' "$libxslt_source/ltmain.sh"
(
  cd "$libxslt_source"
  export CC=/usr/bin/clang
  export CFLAGS='-arch x86_64 -O2 -mmacosx-version-min=14.0'
  export CPPFLAGS='-I/opt/local/include'
  export LDFLAGS='-arch x86_64 -mmacosx-version-min=14.0 -L/opt/local/lib'
  export PKG_CONFIG_LIBDIR=/opt/local/lib/pkgconfig
  ./configure --prefix=/opt/local --without-python --without-crypto --disable-silent-rules
  make -j"$(sysctl -n hw.ncpu)"
  make DESTDIR="$libxslt_dest" install
)
cp "$libxslt_dest/opt/local/lib/libxslt.1.dylib" "$runtime_root/opt/local/lib/"
cp "$libxslt_dest/opt/local/lib/libexslt.0.dylib" "$runtime_root/opt/local/lib/"

# The published Imagick cache contains libheif 1.12, whose optional HEIC coder
# needs this exact rav1e install name. Rebuild only its C ABI for x86_64.
rav1e_archive=$(download \
  https://github.com/xiph/rav1e/archive/refs/tags/v0.4.1.tar.gz \
  b0be59435a40e03b973ecc551ca7e632e03190b5a20f944818afa3c2ecf4852d)
rav1e_lock=$(download \
  https://github.com/xiph/rav1e/releases/download/v0.4.1/Cargo.lock \
  f61b12ef1b9a0bcbc9e124d0eaec0d04ff2bf570a2b19d0d1045e754154fd191)
rav1e_source="$work_dir/rav1e-source"
mkdir -p "$rav1e_source"
tar -xzf "$rav1e_archive" -C "$rav1e_source" --strip-components=1
cp "$rav1e_lock" "$rav1e_source/Cargo.lock"
# Rust 1.67 added inherent integer ilog methods. Rename rav1e's older helper so
# the 0.4.1 source keeps its original behavior with the current toolchain.
find "$rav1e_source" -type f -name '*.rs' -exec sed -i '' \
  -e 's/\.ilog()/\.rav1e_ilog()/g' \
  -e 's/fn ilog(/fn rav1e_ilog(/g' {} +
# Both legacy constants have the same value; qualify the CDF table's copy to
# satisfy current ambiguous-glob checks.
sed -i '' \
  's/TXFM_PARTITION_CONTEXTS/crate::entropymode::TXFM_PARTITION_CONTEXTS/g' \
  "$rav1e_source/src/context/cdf_context.rs"
# Cargo must know the final library type before it selects dependency outputs.
sed -i '' '/^\[lib\]$/a\
crate-type = ["cdylib"]
' "$rav1e_source/Cargo.toml"
rustup target add x86_64-apple-darwin
(
  cd "$rav1e_source"
  CARGO_NET_RETRY=3 MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --locked --release \
    --target x86_64-apple-darwin --lib --no-default-features --features capi
)
rav1e_dylib="$rav1e_source/target/x86_64-apple-darwin/release/librav1e.dylib"
install_name_tool -id /opt/local/lib/librav1e.0.4.1.dylib "$rav1e_dylib"
cp "$rav1e_dylib" "$runtime_root/opt/local/lib/librav1e.0.4.1.dylib"

for dylib in \
  libexpat.1.dylib \
  libexslt.0.dylib \
  libffi.8.dylib \
  libfreetype.6.dylib \
  libgmp.10.dylib \
  libpng16.16.dylib \
  librav1e.0.4.1.dylib \
  libsqlite3.0.dylib \
  libxslt.1.dylib \
  libyaml-0.2.dylib \
  libzip.5.dylib; do
  file -L "$runtime_root/opt/local/lib/$dylib" | grep -q x86_64
done
otool -L "$runtime_root/opt/local/lib/libxslt.1.dylib" | grep -q /opt/local/lib/libxml2.2.dylib
nm -gU "$runtime_root/opt/local/lib/librav1e.0.4.1.dylib" | grep -Eq ' _?rav1e_context_new$'
test -x "$runtime_root/opt/local/bin/autoconf"
test -x "$runtime_root/opt/local/bin/autom4te"
head -1 "$runtime_root/opt/local/bin/autom4te" | grep -q '^#! /usr/bin/perl -w$'
M4=/usr/bin/m4 \
  AUTOM4TE_CFG="$runtime_root/opt/local/share/autoconf/autom4te.cfg" \
  autom4te_perllibdir="$runtime_root/opt/local/share/autoconf" \
  "$runtime_root/opt/local/bin/autom4te" --version | grep -q '2\.69'

(
  cd "$runtime_root"
  tar -czf "$output" ./opt/local
)
shasum -a 256 "$output"
