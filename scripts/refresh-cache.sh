#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <53|54|55>" >&2
  exit 1
fi

version=$1
case "$version" in
53 | 54 | 55) ;;
*)
  echo "Unsupported PHP version: $version" >&2
  exit 1
  ;;
esac

: "${SOURCE_CACHE:?Set SOURCE_CACHE to the currently published PHP cache}"
: "${RUNTIME_ARCHIVE:?Set RUNTIME_ARCHIVE to the MacPorts runtime overlay}"

build_dir=${BUILD_DIR:-/tmp/builds}
report_dir=${REPORT_DIR:-/tmp/cache-comparison}
php_version="php$version"
preinstalled_dir=${PREINSTALLED_DIR:-/opt/local.preinstalled-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}-$version}
opt_local_state_file=${OPT_LOCAL_STATE_FILE:-}

snapshot_behavior() {
  local destination=$1
  local php_bin="/opt/local/bin/php$version"
  local extension
  local extension_type

  mkdir -p "$destination"
  : >"$destination/startup-warnings.txt"
  {
    "$php_bin" -v >"$destination/php-version.txt"
    "$php_bin" -m >"$destination/php-modules.txt"
    "$php_bin" --ini >"$destination/php-ini.txt"
    "$php_bin" -i | sed '/^Environment$/,$d' >"$destination/php-info.txt"
    # shellcheck disable=SC2016
    "$php_bin" -r '
    $extensions = array_unique(array_merge(get_loaded_extensions(), get_loaded_extensions(true)));
    sort($extensions);
    foreach ($extensions as $extension) {
        $version = phpversion($extension);
        echo $extension, "\t", ($version === false ? "" : $version), PHP_EOL;
    }
  ' >"$destination/extension-versions.txt"
    # shellcheck disable=SC2016
    "$php_bin" -r '
    $settings = ini_get_all();
    ksort($settings);
    foreach ($settings as $name => $values) {
        echo $name, "\t", $values["local_value"], "\t", $values["global_value"], PHP_EOL;
    }
  ' >"$destination/ini-settings.txt"
    # shellcheck disable=SC2016
    "$php_bin" -r '
    if (!extension_loaded("curl")) {
        echo "unavailable", PHP_EOL;
    } else {
        $curl = curl_version();
        ksort($curl);
        foreach ($curl as $name => $value) {
            echo $name, "\t", (is_array($value) ? implode(",", $value) : $value), PHP_EOL;
        }
    }
  ' >"$destination/curl-version.txt"

    awk '$0 != "curl" && $0 != "http"' "$destination/php-modules.txt" >"$destination/stable-php-modules.txt"
    awk -F '\t' '$1 != "curl" && $1 != "http"' "$destination/extension-versions.txt" >"$destination/stable-extension-versions.txt"
    awk -F '\t' '$1 !~ /^(curl|http)\./' "$destination/ini-settings.txt" >"$destination/stable-ini-settings.txt"

    : >"$destination/stable-extension-info.txt"
    : >"$destination/runtime-extension-info.txt"
    cut -f1 "$destination/extension-versions.txt" | while IFS= read -r extension; do
      case "$extension" in
      curl | http | iconv | zlib) extension_type=runtime ;;
      *) extension_type=stable ;;
      esac
      {
        echo "### $extension"
        "$php_bin" --ri "$extension"
        echo
      } >>"$destination/$extension_type-extension-info.txt"
    done
  } 2>"$destination/startup-warnings.txt"
  awk '/^PHP /' "$destination/startup-warnings.txt" | LC_ALL=C sort -u >"$destination/startup-messages.txt"
}

snapshot_static() {
  local destination=$1
  local artifact_list="$destination/php-artifact-files.txt"
  local file_path
  local checksum

  mkdir -p "$destination"
  : >"$artifact_list"
  for file_path in \
    "/opt/local/bin/php" \
    "/opt/local/bin/php$version" \
    "/opt/local/bin/php-cgi$version" \
    "/opt/local/sbin/php-fpm$version" \
    "/opt/local/bin/phpize" \
    "/opt/local/bin/phpize$version" \
    "/opt/local/bin/php-config" \
    "/opt/local/bin/php-config$version"; do
    [[ -f "$file_path" ]] && echo "$file_path" >>"$artifact_list"
  done
  find "/opt/local/lib/$php_version" -type f -name '*.so' >>"$artifact_list"
  find "/opt/local/etc/$php_version" -type f >>"$artifact_list"
  sort -u -o "$artifact_list" "$artifact_list"
  : >"$destination/php-artifacts.sha256"
  while IFS= read -r file_path; do
    checksum=$(shasum -a 256 "$file_path" | cut -d' ' -f1)
    printf '%s  %s\n' "$checksum" "${file_path#/opt/local/}" >>"$destination/php-artifacts.sha256"
  done <"$artifact_list"
  find /opt/local \( -type f -o -type l \) -print | sed 's|^/opt/local/||' | LC_ALL=C sort >"$destination/all-paths.txt"
}

snapshot() {
  snapshot_behavior "$1"
  snapshot_static "$1"
}

compare_file() {
  local name=$1
  local baseline=${2:-old}
  if ! diff -u "$report_dir/$baseline/$name" "$report_dir/new/$name" >"$report_dir/$name.diff"; then
    comparison_status=1
  fi
}

mkdir -p "$build_dir" "$report_dir/source" "$report_dir/new"
{
  shasum -a 256 "$SOURCE_CACHE"
  shasum -a 256 "$RUNTIME_ARCHIVE"
} >"$report_dir/input-checksums.txt"
zstd -dc "$SOURCE_CACHE" | tar -tf - >"$report_dir/source-cache-paths.txt"
if grep -Ev '^\./opt/?$|^\./opt/local(/|$)' "$report_dir/source-cache-paths.txt"; then
  echo "Published cache contains a path outside /opt/local" >&2
  exit 1
fi
tar -tzf "$RUNTIME_ARCHIVE" >"$report_dir/runtime-paths.txt"
if grep -Ev '^\./opt/?$|^\./opt/local(/|$)' "$report_dir/runtime-paths.txt"; then
  echo "Runtime overlay contains a path outside /opt/local" >&2
  exit 1
fi

if [[ -d /opt/local ]]; then
  test ! -e "$preinstalled_dir"
  sudo mv /opt/local "$preinstalled_dir"
  [[ -n "$opt_local_state_file" ]] && printf 'present\n' >"$opt_local_state_file"
elif [[ -n "$opt_local_state_file" ]]; then
  printf 'absent\n' >"$opt_local_state_file"
fi
zstd -dc "$SOURCE_CACHE" | sudo tar -xf - -C /
test -x "/opt/local/bin/php$version"
snapshot "$report_dir/source"
sudo tar -xzf "$RUNTIME_ARCHIVE" -C /
snapshot "$report_dir/new"

comparison_status=0
for name in \
  php-version.txt \
  stable-php-modules.txt \
  php-ini.txt \
  stable-extension-versions.txt \
  stable-extension-info.txt \
  stable-ini-settings.txt; do
  compare_file "$name" source
done
compare_file php-artifacts.sha256 source

comm -13 "$report_dir/source/startup-messages.txt" "$report_dir/new/startup-messages.txt" >"$report_dir/new-startup-messages.txt"
comm -23 "$report_dir/source/startup-messages.txt" "$report_dir/new/startup-messages.txt" >"$report_dir/resolved-startup-messages.txt"
if [[ -s "$report_dir/new-startup-messages.txt" ]]; then
  comparison_status=1
fi

comm -23 "$report_dir/source/all-paths.txt" "$report_dir/new/all-paths.txt" >"$report_dir/missing-paths.txt"
comm -13 "$report_dir/source/all-paths.txt" "$report_dir/new/all-paths.txt" >"$report_dir/added-paths.txt"
if [[ -s "$report_dir/missing-paths.txt" ]]; then
  comparison_status=1
fi
diff -u "$report_dir/source/php-info.txt" "$report_dir/new/php-info.txt" >"$report_dir/php-info.diff" || true
diff -u "$report_dir/source/runtime-extension-info.txt" "$report_dir/new/runtime-extension-info.txt" >"$report_dir/runtime-extension-info.diff" || true
diff -u "$report_dir/source/curl-version.txt" "$report_dir/new/curl-version.txt" >"$report_dir/curl-version.diff" || true
if cmp -s "$report_dir/source/curl-version.txt" "$report_dir/new/curl-version.txt"; then
  echo "The curl runtime did not change" >&2
  comparison_status=1
fi

{
  echo "PHP $version cache comparison"
  echo "Published stable extensions: $(wc -l <"$report_dir/source/stable-extension-versions.txt")"
  echo "New modules: $(wc -l <"$report_dir/new/extension-versions.txt")"
  echo "New startup messages: $(wc -l <"$report_dir/new-startup-messages.txt")"
  echo "Resolved startup messages: $(wc -l <"$report_dir/resolved-startup-messages.txt")"
  echo "Published cache paths: $(wc -l <"$report_dir/source/all-paths.txt")"
  echo "New paths: $(wc -l <"$report_dir/new/all-paths.txt")"
  echo "Missing paths: $(wc -l <"$report_dir/missing-paths.txt")"
  echo "Stable comparison status: $comparison_status"
} | tee "$report_dir/summary.txt"

(
  cd /
  tar cf - ./opt/local | zstd -22 -T0 --ultra >"$build_dir/$php_version-cache.tar.zst"
)

exit "$comparison_status"
