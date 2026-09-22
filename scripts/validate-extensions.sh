#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
version=${1:?Specify 53, 54, or 55}
case "$version" in
  53|54|55) ;;
  *) exit 1 ;;
esac

# Inventory of the published PHP 5 caches. Keep this independent of the build
# list so dropping a build port cannot silently reduce downstream compatibility.
extensions=(amf amqp apcu curl dbase enchant exif gd gearman gmp http iconv
  igbinary imap intl mbstring memcache memcached mongo mysql mysqli openssl
  pcntl pdo_mysql pdo_sqlite propro raphf redis soap sockets sqlite3 tidy twig
  xmlrpc xsl xslcache zip 'Zend OPcache')
if [[ "$version" = 53 ]]; then
  extensions+=(sqlite)
else
  extensions+=(mongodb)
fi
if [[ "$version" = 54 ]]; then
  extensions+=(mailparse yaml)
fi

php -r "if (strpos(PHP_VERSION, '${version:0:1}.${version:1:1}.') !== 0) { throw new Exception('Wrong PHP version'); }"
for extension in "${extensions[@]}"; do
  php -r "if (!extension_loaded('$extension')) { throw new Exception('$extension not loaded'); }"
done
extension_dir="$(php-config --extension-dir)"
# dlopen can defer binding until a function is called. Catch removed PHP APIs
# even when a module loads and its basic smoke test does not exercise that path.
exports=$(nm -gU "$(command -v php)" "$extension_dir"/*.so | awk 'NF == 3 {print $3}' | sort -u)
imports=$(nm -u "$extension_dir"/*.so | awk '$1 ~ /^_{1,2}(php_|zend_|ZVAL_|zval_|safe_emalloc|emalloc|efree|ecalloc|erealloc|estrdup|estrndup)/ {print $1}' | sort -u)
missing=$(comm -23 <(printf '%s\n' "$imports") <(printf '%s\n' "$exports"))
failed=false
if [[ -n "$missing" ]]; then
  printf 'Unresolved PHP API symbols:\n%s\n' "$missing" >&2
  failed=true
fi
# Isolate checks so a crashing module cannot hide failures in other extensions.
for extension in amf igbinary apcu dbase amqp redis http; do
  if ! php -d apc.enable_cli=1 "$(dirname "$0")/tests/legacy-extensions.php" "$extension"; then
    echo "$extension behavior check failed" >&2
    failed=true
  fi
done
# Xdebug must be bundled, but disabled by default.
php -r 'if (extension_loaded("xdebug")) { throw new Exception("Xdebug enabled by default"); }'
output=$(php -n -d "zend_extension=$extension_dir/xdebug.so" \
  -r 'if (!extension_loaded("xdebug")) { throw new Exception("Xdebug not loadable"); }' 2>&1)
if [[ -n "$output" ]]; then
  printf '%s\n' "$output" >&2
  exit 1
fi
[[ "$failed" = false ]]
