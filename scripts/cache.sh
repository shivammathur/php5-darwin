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

switch_version() {
  to_wait=()
  for tool in php phpize php-config; do
    sudo cp "$opt_bin/$tool$version" "$opt_bin/$tool" &
    to_wait+=($!)
  done
  wait "${to_wait[@]}"
  sudo ln -sf "$opt_bin"/* "$usr_bin"
}

setup_php() {
  get "$tmp_path.tar.zst" "$repo_url/releases/latest/download/$php_version.tar.zst" "$cds/public/$repo/raw/files/$php_version.tar.zst"
  zstd -dq "$tmp_path".tar.zst && tar xf "$tmp_path".tar -C /tmp
  sudo installer -verbose -pkg "$tmp_path"/"$php_version".mpkg -target /
  sudo cp -a "$tmp_path"/lib/* "$opt_lib"
  sudo cp "$php_etc_dir"/php.ini-production "$php_etc_dir"/php.ini
  echo '' | sudo tee "$pecl_file" >/dev/null 2>&1
  sudo chmod 777 "$ini_file" "$ini_file"-development "$ini_file"-production
  echo "date.timezone=UTC" | tee -a "$ini_file" "$ini_file"-development "$ini_file"-production
}

add_ext_to_ini() {
  ext_file=$1
  extension=$(basename "$ext_file" | cut -d'.' -f 1)
  if [ "$extension" != "xdebug" ]; then
    echo "extension=$extension.so" | sudo tee "$scan_dir/20-$extension.ini"
  fi
}

add_daemondo() {
  get "$opt_bin"/daemondo "$repo_url/releases/latest/download/daemondo" "$cds/public/$repo/raw/files/daemondo"
  sudo chmod a+x "$opt_bin"/daemondo
}

add_extensions() {
  ext_dir=$(php -i | grep -Ei "extension_dir => /" | sed -e "s|.*=> s*||")
  sudo mkdir -p "$ext_dir"
  sudo chmod 777 "$ext_dir"
  sudo cp -a "$tmp_path"/ext/*.so "$ext_dir"
  sudo cp -a "$tmp_path"/include/* "$opt_inc"
  for pkg in cgi fpm opcache; do
    sudo installer -verbose -pkg "$tmp_path"/"$php_version"-"$pkg".pkg -target /
  done
  to_wait=()
  for bin in "$tmp_path"/ext/*.so; do
    add_ext_to_ini "$bin" &
    to_wait+=($!)
  done
  wait "${to_wait[@]}"
  sudo mv "$scan_dir/opcache.ini" "$scan_dir/10-opcache.ini"
  sudo ln -sf "$opt_bin"/php-cgi"$version" "$usr_bin"/php-cgi
  sudo ln -sf "$opt_sbin"/php-fpm"$version" "$usr_bin"/php-fpm
  sudo sed -i "" "s/VERSION/$version/" "$tmp_path"/php-fpm.conf
  sudo cp "$tmp_path"/php-fpm.conf "$php_etc_dir"
}

add_pear() {
  sudo rm -rf "$(command -v pear)" "$(command -v pecl)"
  pecl_version='master'
  if [ "$version" = "53" ]; then
    pecl_version='v1.9.5'
  fi
  pear_repo="$github/pear/pearweb_phars"
  get /tmp/pear.phar "$pear_repo/raw/$pecl_version/install-pear-nozlib.phar"
  sudo php /tmp/pear.phar -d "$opt_lib"/"$php_version" -b "$opt_bin"
  for script in pear pecl; do
    sudo ln -sf "$opt_bin"/"$script" "$usr_bin"
    sudo "$script" config-set php_ini "$pecl_file"
    sudo "$script" config-set php_bin "$opt_bin/php"
  done
  echo '' | sudo tee /tmp/pecl_config >/dev/null 2>&1
}

add_imagick() {
  get "$tmp_path-imagick.tar.zst" "$repo_url/releases/latest/download/$php_version-imagick.tar.zst" "$cds/public/$repo/raw/files/$php_version-imagick.tar.zst"
  sudo mkdir -p /tmp/imagick
  sudo zstd -dq "$tmp_path-imagick.tar.zst" && sudo tar -xf "$tmp_path-imagick.tar" -C /tmp/imagick
  for pkg in /tmp/imagick/*.pkg; do
    sudo installer -pkg "$pkg" -target /
  done
}

package() {
  name=$1
  mkdir -p /tmp/builds
  (
    cd / || exit 1
    tar cf - ./opt | zstd -22 -T0 --ultra > /tmp/builds/"$name"-cache.tar.zst
  )
}

version=$1
php_version="php$version"
ini_file="/opt/local/etc/$php_version/php.ini"
scan_dir="/opt/local/var/db/$php_version"
pecl_file="$scan_dir/99-pecl.ini"
github="https://github.com"
cds="https://dl.cloudsmith.io"
repo="shivammathur/php5-darwin"
repo_url="$github/$repo"
php_etc_dir="/opt/local/etc/$php_version"
tmp_path="/tmp/$php_version"
opt_bin="/opt/local/bin"
opt_inc="/opt/local/include"
opt_lib="/opt/local/lib"
usr_bin="/usr/local/bin"
opt_sbin="/opt/local/sbin"
export TERM=xterm
sudo rm -rf /opt 2>/dev/null

if [ "$2" = "imagick" ]; then
  add_imagick
  package "$php_version-imagick"
else
  setup_php
  switch_version
  add_extensions
  add_daemondo
  add_pear
  package "$php_version"
fi
