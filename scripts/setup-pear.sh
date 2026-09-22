#!/usr/bin/env bash
set -euo pipefail

version=${1:-}
prefix=/opt/local
script_dir=$(cd "$(dirname "$0")" && pwd)
build_dir=${NATIVE_BUILD_DIR:-$(mktemp -d)}
php_version="php$version"
php_etc_dir="$prefix/etc/$php_version"
pecl_file="$prefix/var/db/$php_version/99-pecl.ini"
mkdir -p "$build_dir"

case "$version" in
  53)
    pear_version=1.9.5
    bootstrap_ref=v1.9.5
    bootstrap_checksum=c45983a5065b8bd2e4fbb9191786aacd43a0d4736493e5008f6f844c13a14563
    ;;
  54|55)
    pear_version=1.10.18
    # pearweb_phars tags are not PEAR package versions.
    bootstrap_ref=v1.10.26
    bootstrap_checksum=a71349da29f1a6e3f0792695b167e582375a93c70c0e9d35e7c4675697c5f039
    ;;
  *) echo "Usage: $0 <53|54|55>" >&2; exit 1 ;;
esac

download() {
  local url=$1 file=$2 checksum=$3
  curl -fsSL --retry 3 -o "$file" "$url"
  echo "$checksum  $file" | shasum -a 256 -c -
}

bootstrap="$build_dir/install-pear-nozlib.phar"
download "https://raw.githubusercontent.com/pear/pearweb_phars/$bootstrap_ref/install-pear-nozlib.phar" \
  "$bootstrap" "$bootstrap_checksum"

# Archive_Tar 1.6 in the current bootstrap requires PHP 5.6. Pin the last
# PHP-5.2-compatible release for all three legacy interpreters instead.
archive_tar="$build_dir/Archive_Tar-1.4.14.tgz"
download https://pear.php.net/get/Archive_Tar-1.4.14.tgz "$archive_tar" \
  4af263e4fdfcb400f888f84cccf8d05d1be2eb78128349431405b2ffb0c0c9f4
packages=("$archive_tar")
if [[ "$version" = 53 ]]; then
  # This historical bootstrap contains PEAR 1.9.4 despite its tag name.
  pear_archive="$build_dir/PEAR-1.9.5.tgz"
  download https://pear.php.net/get/PEAR-1.9.5.tgz "$pear_archive" \
    a1bada1a1e66b6dd1d62058fa48e3651fddd8163e6bd67a16494902910fff2e5
  packages+=("$pear_archive")
fi

sudo "$prefix/bin/php" -d phar.readonly=0 "$script_dir/patch-pear-xml.php" "$bootstrap"
sudo env HOME="$HOME" "$prefix/bin/php" "$bootstrap" \
  -d "$prefix/lib/$php_version" -b "$prefix/bin" "${packages[@]}"
# The bootstrap can return success even when a package failed to install.
sudo "$prefix/bin/php" "$script_dir/patch-pear-xml.php" "$prefix/lib/$php_version/PEAR/XMLParser.php"
for script in pear pecl; do
  sudo env HOME="$HOME" "$prefix/bin/$script" config-set php_ini "$pecl_file"
  sudo env HOME="$HOME" "$prefix/bin/$script" config-set php_bin "$prefix/bin/php"
done
# All three versions load OpenSSL as a shared module, so PECL needs the ini files.
if grep -Fq "exec \$PHP -C -n -q " "$prefix/bin/pecl"; then
  sudo sed -i '' 's/exec $PHP -C -n -q /exec $PHP -C -q /' "$prefix/bin/pecl"
elif ! grep -Fq "exec \$PHP -C -q " "$prefix/bin/pecl"; then
  echo "Unexpected PECL wrapper" >&2
  exit 1
fi
# PEAR 1.10.17+ fixes chunked decoding. Only the PHP 5.3 legacy client needs
# HTTP/1.0; HTTPS remains enabled in both clients.
if [[ "$version" = 53 ]]; then
  for client in REST Downloader; do
    sudo sed -i '' 's|HTTP/1\.1|HTTP/1.0|g' "$prefix/lib/$php_version/PEAR/$client.php"
  done
fi
"$prefix/bin/pecl" version | grep -Fx "PEAR Version: $pear_version"
"$prefix/bin/pear" list | grep -E '^Archive_Tar[[:space:]]+1\.4\.14[[:space:]]'
sudo cp "$HOME/.pearrc" "$php_etc_dir/.pearrc"
