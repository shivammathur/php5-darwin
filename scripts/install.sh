#!/usr/bin/env bash

get() {
  file_path=$1
  shift
  links=("$@")
  for link in "${links[@]}"; do
    status_code=$(sudo curl -w "%{http_code}" -o "$file_path" -sL "$link")
    [ "$status_code" = "200" ] && break
    echo "Failed to fetch $link"
  done
}

setup_php() {
  get "$tmp_path.tar.zst" "$repo_url/releases/latest/download/$php_version-cache.tar.zst" "$cds/public/$repo/raw/files/$php_version-cache.tar.zst"
  zstd -dq "$tmp_path".tar.zst && sudo tar xf "$tmp_path".tar -C /
  sudo ln -sf "$opt_bin"/* "$usr_bin"
  sudo ln -sf "$opt_bin"/php-cgi"$version" "$usr_bin"/php-cgi
  sudo ln -sf "$opt_sbin"/php-fpm"$version" "$usr_bin"/php-fpm
}

add_imagick() {
  get "$tmp_path-imagick.tar.zst" "$repo_url/releases/latest/download/$php_version-imagick-cache.tar.zst" "$cds/public/$repo/raw/files/$php_version-imagick-cache.tar.zst"
  sudo zstd -dq "$tmp_path-imagick.tar.zst" && sudo tar -xf "$tmp_path-imagick.tar" -C /
}

configure_pecl() {
  for script in pear pecl; do
    sudo "$script" config-set php_ini "$pecl_file"
    sudo "$script" config-set php_bin "$opt_bin/php"
  done
}

version=$1
php_version="php$version"
scan_dir="/opt/local/var/db/$php_version"
pecl_file="$scan_dir/99-pecl.ini"
github="https://github.com"
cds="https://dl.cloudsmith.io"
repo="shivammathur/php5-darwin"
repo_url="$github/$repo"
tmp_path="/tmp/$php_version"
opt_bin="/opt/local/bin"
opt_sbin="/opt/local/sbin"
usr_bin="/usr/local/bin"
export TERM=xterm

if [ "$2" = "imagick" ]; then
  add_imagick
else
  setup_php
  configure_pecl
fi
