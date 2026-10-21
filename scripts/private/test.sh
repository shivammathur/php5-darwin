#!/usr/bin/env bash
# PHP expressions below intentionally use literal dollar signs.
# shellcheck disable=SC2016
set -euo pipefail
umask 022
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
[[ "$(uname -m)" = "$EXPECTED_ARCHITECTURE" ]]
command -v zstd >/dev/null || brew install zstd
[[ ! -d /opt/local ]] || sudo mv /opt/local "$PRIVATE_TASK_DIR/opt-local.preinstalled"
export PHP5_CACHE_DIR="$PACKAGE_DIR"
export PATH="/opt/local/bin:/usr/local/bin:$PATH"
version=${PHP_VERSION/./}
bash "$repo/scripts/install.sh" "$version"
actual=$(/opt/local/bin/php -r 'echo PHP_VERSION;')
[[ "$actual" = "$PHP_FULL_VERSION" ]]
/opt/local/bin/php --ini
/opt/local/bin/php -v > "$REPORT_DIR/php-version.txt" 2>&1
/opt/local/bin/php -m > "$REPORT_DIR/php-modules.txt" 2>&1
cat "$REPORT_DIR/php-version.txt" "$REPORT_DIR/php-modules.txt"
if grep -Ei '(^PHP (Warning|Fatal|Notice|Deprecated)|PHP Startup:)' "$REPORT_DIR/php-version.txt" "$REPORT_DIR/php-modules.txt"; then exit 1; fi
/opt/local/bin/php "$here/smoke.php"
/opt/local/bin/php-config --version
/opt/local/bin/phpize --version
"/opt/local/bin/php-cgi$version" -v
sudo "/opt/local/sbin/php-fpm$version" -t
bash "$repo/scripts/validate-extensions.sh" "$version"
bash "$repo/scripts/validate-imap.sh" "$version"
AUDIT_DIR="$REPORT_DIR/audit-base" bash "$repo/scripts/audit-dependencies.sh" /opt/local "$EXPECTED_ARCHITECTURE"
sudo "$(command -v python3)" "$repo/scripts/audit-runtime.py"
bash "$repo/scripts/validate-pecl.sh" "$version"
bash "$repo/scripts/install.sh" "$version" imagick
/opt/local/bin/php -r 'if (!extension_loaded("imagick")) { throw new Exception("Imagick missing"); } $i=new Imagick(); $i->newImage(2,2,"white"); if ($i->getImageWidth()!==2) { throw new Exception("Imagick failed"); }'
AUDIT_DIR="$REPORT_DIR/audit-imagick" bash "$repo/scripts/audit-dependencies.sh" /opt/local "$EXPECTED_ARCHITECTURE"
sudo "$(command -v python3)" "$repo/scripts/audit-runtime.py"
