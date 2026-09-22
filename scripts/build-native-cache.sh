#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <53|54|55> <output-directory>" >&2
  exit 1
fi

version=$1
output_dir=$2
php_version="php$version"
prefix=/opt/local
port="$prefix/bin/port"
build_dir=${NATIVE_BUILD_DIR:-$(mktemp -d)}
php_etc_dir="$prefix/etc/$php_version"
scan_dir="$prefix/var/db/$php_version"
pecl_file="$scan_dir/99-pecl.ini"
openssl_dependency_log="$build_dir/openssl-dependencies.log"
build_failures="$build_dir/failed-ports.log"

case "$version" in
  53|54|55) ;;
  *) echo "Unsupported PHP version: $version" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64) arch=arm64; arch_suffix=-arm64 ;;
  x86_64) arch=x86_64; arch_suffix= ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$output_dir" "$build_dir"
: > "$build_failures"
test -x "$port"

install_ports() {
  sudo "$port" -N install --allow-failing "$@"
}

verify_php_runtime() {
  local check_dir="$build_dir/php-runtime-check"
  local diagnostic_log="$build_dir/php-runtime-dyld.log"
  local command_ok ini output

  mkdir -p "$check_dir/conf.d"
  : > "$check_dir/php.ini"
  for ini in "$scan_dir"/*.ini; do
    [[ -f "$ini" ]] || continue
    cp "$ini" "$check_dir/conf.d/"
    echo "Validating PHP after enabling $(basename "$ini")"
    if output=$(PHP_INI_SCAN_DIR="$check_dir/conf.d" \
      "$prefix/bin/php$version" -c "$check_dir/php.ini" -v 2>&1); then
      command_ok=true
    else
      command_ok=false
    fi
    printf '%s\n' "$output"
    if [[ "$command_ok" != true ]] || \
      grep -Eq 'PHP (Warning|Fatal error):[[:space:]]+PHP Startup:' \
        <<< "$output"; then
      echo "PHP runtime failed after enabling $(basename "$ini")" >&2
      env DYLD_PRINT_BINDINGS=1 DYLD_PRINT_LIBRARIES=1 \
        PHP_INI_SCAN_DIR="$check_dir/conf.d" \
        "$prefix/bin/php$version" -c "$check_dir/php.ini" -v \
        > "$diagnostic_log" 2>&1 || true
      tail -200 "$diagnostic_log" >&2
      return 1
    fi
  done
}

collect_paths() {
  local destination=$1
  local raw_paths="$destination.raw"
  local installed_port path tree

  : > "$destination"
  : > "$raw_paths"
  while read -r installed_port _; do
    "$port" -q contents "$installed_port" | sed 's/^  //' >> "$raw_paths"
  done < <("$port" -q installed active)

  for tree in \
    "$php_etc_dir" \
    "$scan_dir" \
    "$prefix/etc/openssl" \
    "$prefix/include/$php_version" \
    "$prefix/lib/$php_version" \
    "$prefix/share/autoconf"; do
    if [[ -d "$tree" ]]; then
      find "$tree" \( -type f -o -type l \) -print >> "$raw_paths"
    fi
  done

  for path in \
    "$prefix/bin/php" \
    "$prefix/bin/php-config" \
    "$prefix/bin/phpize" \
    "$prefix/bin/pear" \
    "$prefix/bin/pecl" \
    "$prefix/bin/autoconf" \
    "$prefix/bin/autoheader" \
    "$prefix/bin/autom4te" \
    "$prefix/bin/libtoolize" \
    "$prefix/bin/daemondo"; do
    [[ -e "$path" || -L "$path" ]] && printf '%s\n' "$path" >> "$raw_paths"
  done

  while IFS= read -r path; do
    case "$path" in
      "$prefix"/*) ;;
      *) echo "Skipping external package path: $path"; continue ;;
    esac
    if [[ ! -e "$path" && ! -L "$path" ]]; then
      echo "Registered package path is missing: $path" >&2
      exit 1
    fi
    if [[ ! -d "$path" || -L "$path" ]]; then
      printf '%s\n' "$path" >> "$destination"
    fi
  done < "$raw_paths"

  sort -u -o "$destination" "$destination"
}

package_paths() {
  local paths=$1
  local output=$2
  local relative_paths
  relative_paths="$build_dir/$(basename "$paths").relative"

  sed 's|^/|./|' "$paths" > "$relative_paths"
  sudo tar -C / -cf - -T "$relative_paths" | zstd -19 -T0 -o "$output"
  sudo chown "$(id -u):$(id -g)" "$output"
  shasum -a 256 "$output"
}

if [[ "$arch" = arm64 ]]; then
  # The upstream binary archive uses -O3 and fails EC curve checks. Force a
  # source build with our patched -O1 target before PHP depends on this port.
  sudo "$port" -N -s install --allow-failing openssl10
fi
if [[ "$version" = 53 ]]; then
  install_ports curl +gnutls -ssl
fi
install_ports "$php_version"
install_ports \
  "$php_version-cgi" \
  "$php_version-curl" \
  "$php_version-exif" \
  "$php_version-fpm" \
  "$php_version-gd" \
  "$php_version-gmp" \
  "$php_version-iconv" \
  "$php_version-intl" \
  "$php_version-mbstring" \
  "$php_version-opcache" \
  "$php_version-openssl" \
  "$php_version-pcntl" \
  "$php_version-soap" \
  "$php_version-sockets" \
  "$php_version-sqlite" \
  "$php_version-tidy" \
  "$php_version-xmlrpc" \
  "$php_version-xsl"
install_ports "$php_version-mysql" +mysqlnd
install_ports "$php_version-zip"

sudo ln -sf "$php_version" "$prefix/bin/php"
sudo ln -sf "php-cgi$version" "$prefix/bin/php-cgi"
sudo ln -sf "php-config$version" "$prefix/bin/php-config"
sudo ln -sf "phpize$version" "$prefix/bin/phpize"
sudo ln -sf "../sbin/php-fpm$version" "$prefix/bin/php-fpm"
sudo mkdir -p "$scan_dir"
if [[ ! -f "$php_etc_dir/php.ini" ]]; then
  sudo cp "$php_etc_dir/php.ini-production" "$php_etc_dir/php.ini"
fi
if [[ ! -f "$php_etc_dir/php-fpm.conf" ]]; then
  sudo cp "$php_etc_dir/php-fpm.conf.default" "$php_etc_dir/php-fpm.conf"
fi
echo 'date.timezone=UTC' | sudo tee -a "$php_etc_dir/php.ini" >/dev/null
echo '' | sudo tee "$pecl_file" >/dev/null
verify_php_runtime
openssl_module="$("$prefix/bin/php-config$version" --extension-dir)/openssl.so"
test -f "$openssl_module"
otool -L "$openssl_module" | tee "$openssl_dependency_log"
grep -Fq "$prefix/libexec/openssl10/lib/libssl" "$openssl_dependency_log"
grep -Fq "$prefix/libexec/openssl10/lib/libcrypto" "$openssl_dependency_log"
for curve in secp224r1 prime256v1 secp384r1 secp521r1; do
  "$prefix/libexec/openssl10/bin/openssl" ecparam -name "$curve" -check -noout
done

pear_ref=v1.9.5
pear_checksum=c45983a5065b8bd2e4fbb9191786aacd43a0d4736493e5008f6f844c13a14563
curl -fsSL --retry 3 -o "$build_dir/install-pear-nozlib.phar" \
  "https://raw.githubusercontent.com/pear/pearweb_phars/$pear_ref/install-pear-nozlib.phar"
echo "$pear_checksum  $build_dir/install-pear-nozlib.phar" | shasum -a 256 -c -
if ! sudo "$prefix/bin/php" "$build_dir/install-pear-nozlib.phar" \
  -d "$prefix/lib/$php_version" -b "$prefix/bin"; then
  pear_diagnostic_dir="$build_dir/pear-diagnostic"
  pear_diagnostic_log="$build_dir/pear-dyld.log"
  mkdir -p "$pear_diagnostic_dir/bin" "$pear_diagnostic_dir/lib"
  env DYLD_PRINT_BINDINGS=1 DYLD_PRINT_LIBRARIES=1 \
    "$prefix/bin/php" "$build_dir/install-pear-nozlib.phar" \
    -d "$pear_diagnostic_dir/lib" -b "$pear_diagnostic_dir/bin" \
    > "$pear_diagnostic_log" 2>&1 || true
  tail -200 "$pear_diagnostic_log" >&2
  exit 1
fi
for script in pear pecl; do
  sudo env HOME="$HOME" "$prefix/bin/$script" config-set php_ini "$pecl_file"
  sudo env HOME="$HOME" "$prefix/bin/$script" config-set php_bin "$prefix/bin/php"
done
# All three versions load OpenSSL as a shared module, so PECL needs the ini files.
if grep -Fq "exec \$PHP -C -n -q " "$prefix/bin/pecl"; then
  sudo sed -i '' 's/exec $PHP -C -n -q /exec $PHP -C -q /' \
    "$prefix/bin/pecl"
elif ! grep -Fq "exec \$PHP -C -q " "$prefix/bin/pecl"; then
  echo "Unexpected legacy PECL wrapper" >&2
  exit 1
fi
# PEAR 1.9 is needed for PHP 5.3, but its HTTP client cannot decode chunked
# responses. Request HTTP/1.0 for metadata and archives; HTTPS remains enabled.
for client in REST Downloader; do
  sudo sed -i '' 's|HTTP/1\.1|HTTP/1.0|g' \
    "$prefix/lib/$php_version/PEAR/$client.php"
done
if [[ -f "$HOME/.pearrc" ]]; then
  sudo cp "$HOME/.pearrc" "$php_etc_dir/.pearrc"
elif [[ -f /var/root/.pearrc ]]; then
  sudo cp /var/root/.pearrc "$php_etc_dir/.pearrc"
fi
test -f "$php_etc_dir/.pearrc"

# Retain the extensions shipped in the existing caches, not just PHP core.
# Attempt every independent port so one obsolete extension cannot hide the rest
# of the build failures. The final status still prevents validation/publication.
bundled_ports=(amf amqp APCu dbase enchant gearman igbinary imap memcache
  memcached mongo propro raphf http2 redis Twig xdebug xslcache)
if [[ "$version" != 53 ]]; then
  bundled_ports+=(mongodb)
fi
if [[ "$version" = 54 ]]; then
  bundled_ports+=(mailparse yaml)
fi
for extension in "${bundled_ports[@]}"; do
  if [[ "$extension" = amf || "$extension" = amqp || "$extension" = dbase ]]; then
    # These archives contain unpatched source bugs; rebuild only the extension.
    # Install AMQP's dependency from its binary archive first.
    if [[ "$extension" = amqp ]]; then
      install_ports rabbitmq-c
    fi
    install_command=(sudo "$port" -N -s install --allow-failing)
  else
    install_command=(install_ports)
  fi
  if ! "${install_command[@]}" "$php_version-$extension"; then
    echo "$php_version-$extension" >> "$build_failures"
  fi
done
# Ship Xdebug for setup-php to enable on demand, as in the published caches.
if [[ -f "$scan_dir/xdebug.ini" ]]; then
  sudo sed -i '' 's/^zend_extension=/;zend_extension=/' "$scan_dir/xdebug.ini"
fi

install_ports libtool
autoconf_source="$build_dir/autoconf-source"
autoconf_archive="$build_dir/autoconf-2.69.tar.xz"
curl -fsSL --retry 3 -o "$autoconf_archive" \
  https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz
echo "64ebcec9f8ac5b2487125a86a7760d2591ac9e1d3dbd59489633f9de62a57684  $autoconf_archive" \
  | shasum -a 256 -c -
mkdir -p "$autoconf_source"
tar -xJf "$autoconf_archive" -C "$autoconf_source" --strip-components=1
(
  cd "$autoconf_source"
  M4=/usr/bin/m4 PERL=/usr/bin/perl ./configure --prefix="$prefix"
  make -j"$(sysctl -n hw.ncpu)"
  sudo make install
)
test -x "$prefix/bin/glibtoolize"
sudo ln -sf glibtoolize "$prefix/bin/libtoolize"

base_paths="$build_dir/base-paths.txt"
all_paths="$build_dir/all-paths.txt"
imagick_paths="$build_dir/imagick-paths.txt"
collect_paths "$base_paths"
package_paths "$base_paths" \
  "$output_dir/$php_version$arch_suffix-cache.tar.zst"

imagick_variant=+ImageMagick7
[[ "$version" = 53 ]] && imagick_variant=+ImageMagick6
if install_ports "$php_version-imagick" "$imagick_variant"; then
  collect_paths "$all_paths"
  comm -13 "$base_paths" "$all_paths" > "$imagick_paths"
  grep -q "/imagick\.so$" "$imagick_paths"
  package_paths "$imagick_paths" \
    "$output_dir/$php_version-imagick$arch_suffix-cache.tar.zst"
else
  echo "$php_version-imagick" >> "$build_failures"
fi

file -L "$prefix/bin/php" | grep -q "$arch"
if [[ -s "$build_failures" ]]; then
  echo 'Failed extension builds:' >&2
  cat "$build_failures" >&2
  exit 1
fi
