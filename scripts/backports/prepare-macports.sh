#!/usr/bin/env bash
# Prepare the verified branch source for every bundled PHP subport.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/backports/common.sh
. "$here/common.sh"
ports=${PORTS_ROOT:?} reports=${REPORT_DIR:?} minor=${PHP_VERSION:?}
short=${minor/./} source=${SOURCE_ARCHIVE:?}
case "$minor" in 5.3|5.4|5.5) ;; *) fail "Unsupported PHP version: $minor" ;; esac
verify_sha256 "$source" "${SOURCE_SHA256:?}"
source_dir="$BACKPORT_TASK_DIR/source"
mkdir "$source_dir"
# The resolver and activation step checked the archive paths and digest.
tar -xzf "$source" -C "$source_dir"
root="$source_dir/${SOURCE_ROOT:?}"
[[ -d "$root" ]] || fail 'Source root missing'
(
  cd "$root"
  find . -type f -exec shasum -a 256 {} +
) > "$reports/original-files.sha256"
original_files=$(wc -l < "$reports/original-files.sha256" | tr -d '[:space:]')
prefix=${MACPORTS_PREFIX:-/opt/local}
autoconf=269
[[ "$minor" != 5.3 ]] || autoconf=213
export PATH="$prefix/bin:$prefix/sbin:$PATH"
export PHP_AUTOCONF="$prefix/bin/autoconf$autoconf" PHP_AUTOHEADER="$prefix/bin/autoheader$autoconf"
(cd "$root" && bash buildconf --force) > "$reports/buildconf.log" 2>&1
configure="$root/configure"
[[ -f "$configure" && "$(file_size "$configure")" -gt 1048576 ]] || fail 'Incomplete generated configure'
! grep -q 'command not found' "$reports/buildconf.log" || fail 'Bootstrap dependency missing'
bash -n "$configure"
# Git exports omit the generated parsers found in release tarballs.
: > "$reports/generated-parsers.jsonl"
for stem in zend_language_parser zend_ini_parser; do
  parser_prefix=zend
  [[ "$stem" != zend_ini_parser ]] || parser_prefix=ini_
  for suffix in .c .h; do
    [[ ! -e "$root/Zend/$stem$suffix" ]] || fail 'Unexpected pre-generated parser'
  done
  (cd "$root/Zend" && "$BACKPORT_BISON" -y -p "$parser_prefix" -v -d "$stem.y" -o "$stem.c")
  for suffix in .c .h; do
    jq -nc --arg path "Zend/$stem$suffix" --arg sha "$(sha256 "$root/Zend/$stem$suffix")" \
      '{path: $path, sha256: $sha}' >> "$reports/generated-parsers.jsonl"
  done
done
(cd "$root" && shasum -a 256 -c "$reports/original-files.sha256") > "$reports/original-files-check.log"
# Normalize only the derived archive root for MacPorts' extension build paths.
prepared_root="php-$PHP_FULL_VERSION"
mv "$root" "$source_dir/$prepared_root"
root="$source_dir/$prepared_root"
configure="$root/configure"
extension=bz2
[[ "$minor" != 5.5 ]] || extension=xz
name="php-$PHP_FULL_VERSION-backport-${SOURCE_SHA256:0:16}.tar.$extension"
archive="$source_dir/$name"
if [[ "$extension" = bz2 ]]; then
  tar -cjf "$archive" -C "$source_dir" "$prepared_root"
else
  tar -cJf "$archive" -C "$source_dir" "$prepared_root"
fi
hash=$(sha256 "$archive")
subdir="backport-php$short-${SOURCE_SHA256:0:16}"
dist="$prefix/var/macports/distfiles/$subdir"
mkdir -p "$dist"
cp "$archive" "$dist/$name"
chmod 755 "$dist"
chmod 644 "$dist/$name"
# Rebase FPM configuration context, preserving MacPorts' requested settings.
fpm="$root/sapi/fpm/php-fpm.conf.in"
cp "$fpm" "$reports/php-fpm.conf.in"
replace_once "$reports/php-fpm.conf.in" ';pid = run/php-fpm.pid' ';pid = run/@PHP@/php-fpm.pid'
replace_once "$reports/php-fpm.conf.in" ';error_log = log/php-fpm.log' 'error_log = log/@PHP@/php-fpm.log'
replace_once "$reports/php-fpm.conf.in" ';syslog.ident = php-fpm' 'syslog.ident = @PHP@-fpm'
replace_once "$reports/php-fpm.conf.in" "; Send FPM to background. Set to 'no' to keep FPM in foreground for debugging." \
  $'; Send FPM to background. Set to \'no\' to keep FPM in foreground for debugging\n; or for use with launchd.'
replace_once "$reports/php-fpm.conf.in" ';daemonize = yes' 'daemonize = no'
fpm_patch="$ports/lang/php/files/patch-php$short-sapi-fpm-php-fpm.conf.in.diff"
if diff -u -L a/sapi/fpm/php-fpm.conf.in -L b/sapi/fpm/php-fpm.conf.in \
  "$fpm" "$reports/php-fpm.conf.in" > "$reports/fpm-context.patch"; then
  fail 'FPM patch has no changes'
else
  [[ $? = 1 ]] || fail 'Could not generate FPM patch'
fi
rm -f "$fpm_patch"
cp "$reports/fpm-context.patch" "$fpm_patch"
portfile="$ports/lang/php/Portfile"
# ICU 68 changes FALSE to false before ICU 71 applies; only rebase context.
replace_once "$ports/lang/php/files/patch-php55-ext-intl-icu-71.diff" $' \t\treturn FALSE;' $' \t\treturn false;'
cat >> "$portfile" <<PORT

# Use the exact verified backport source for every PHP subport.
if {\${subport_branch} eq "$minor"} {
    revision 999999
    master_sites {}
    dist_subdir $subdir
    distfiles $name
    worksrcdir $prepared_root
    checksums sha256 $hash size $(file_size "$archive")
    patch.pre_args-append --fuzz=0
}
PORT
jq -n --arg sha "$SOURCE_SHA256" --arg root "$SOURCE_ROOT" --argjson files "$original_files" \
  --arg autoconf "$autoconf" --slurpfile parsers "$reports/generated-parsers.jsonl" \
  --arg name "$name" --arg prepared_root "$prepared_root" --arg prepared_sha "$hash" --argjson bytes "$(file_size "$archive")" \
  --arg configure_sha "$(sha256 "$configure")" --argjson configure_bytes "$(file_size "$configure")" \
  --arg fpm_sha "$(sha256 "$fpm_patch")" --arg portfile_sha "$(sha256 "$portfile")" \
  '{original_sha256: $sha, root: $root, original_files: $files, original_files_unchanged: true,
    autoconf: $autoconf, bison: "2.6.4", generated_parsers: $parsers,
    prepared_source: {name: $name, root: $prepared_root, sha256: $prepared_sha, bytes: $bytes},
    configure: {sha256: $configure_sha, bytes: $configure_bytes},
    fpm_patch_sha256: $fpm_sha, portfile_sha256: $portfile_sha}' > "$reports/source-bootstrap.json"
# Install non-PHP dependencies first, then force PHP ports to compile.
replacement=$(cat <<'BUILD'
  local target=$1
  if [[ "$target" = "$php_version" || "$target" = "$php_version-"* ]]; then
    local dependency
    for dependency in "$@"; do
      [[ "$dependency" = "$php_version" || "$dependency" = "$php_version-"* ]] || continue
      sudo "$port" -N install --allow-failing "depof:$dependency"
    done
    sudo "$port" -N -s install --allow-failing "$@"
  else
    sudo "$port" -N install --allow-failing "$@"
  fi
BUILD
)
# shellcheck disable=SC2016
replace_once "$BUILD_REPOSITORY/scripts/build-native-cache.sh" '  sudo "$port" -N install --allow-failing "$@"' "$replacement"
# shellcheck disable=SC2016
replace_once "$BUILD_REPOSITORY/scripts/build-native-cache.sh" 'install_command=(sudo "$port" -N -s install --allow-failing)' 'install_command=(install_ports)'
