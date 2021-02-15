version=$1
php_version="php$version"
ini_file="/opt/local/etc/php$version/php.ini"
github="https://github.com"
repo="$github/shivammathur/php5-darwin"
php_etc_dir="/opt/local/etc/php$version"
tmp_path="/tmp/php$version"
opt_bin="/opt/local/bin"
opt_inc="/opt/local/include"
opt_sbin="/opt/local/sbin"
opt_lib="/opt/local/lib"
usr_bin="/usr/local/bin"
export TERM=xterm

get() {
  file_path=$1
  shift
  links=("$@")
  for link in "${links[@]}"; do
    status_code=$(sudo curl -w "%{http_code}" -o "$file_path" -sL "$link")
    [ "$status_code" = "200" ] && break
  done
}

switch_version() {
  to_wait=()
  for tool in php phpize php-config; do
    sudo mv "$opt_bin/$tool$version" "$opt_bin/$tool" &
    to_wait+=($!)
  done
  wait "${to_wait[@]}"
  sudo ln -sf "$opt_bin"/* "$usr_bin"
}

setup_php() {
  get "$tmp_path.tar.zst" "$repo/releases/latest/download/$php_version.tar.zst" "https://dl.bintray.com/shivammathur/php/$php_version.tar.zst"
  zstd -dq "$tmp_path".tar.zst && tar xf "$tmp_path".tar -C /tmp
  sudo installer -pkg "$tmp_path"/"$php_version".mpkg -target /
  sudo cp -a "$tmp_path"/lib/* "$opt_lib"
  sudo cp "$php_etc_dir"/php.ini-development "$php_etc_dir"/php.ini
  sudo chmod 777 "$ini_file"
  echo "date.timezone=UTC" >>"$ini_file"
}

add_ext_to_ini() {
  ext_file=$1
  extension=$(basename "$ext_file" | cut -d'.' -f 1)
  if [ "$extension" != "xdebug" ]; then
    echo "extension=$extension.so" >>"$ini_file"
  fi
}

add_daemondo() {
  get "$opt_bin"/daemondo "$repo"/releases/latest/download/daemondo
  sudo chmod a+x "$opt_bin"/daemondo
  sudo ln -sf "$opt_bin"/daemondo "$usr_bin"
}

add_extensions() {
  ext_dir=$(php -i | grep -Ei "extension_dir => /" | sed -e "s|.*=> s*||")
  sudo mkdir -p "$ext_dir"
  sudo chmod 777 "$ext_dir"
  sudo cp -a "$tmp_path"/ext/*.so "$ext_dir"
  sudo cp -a "$tmp_path"/include/* "$opt_inc"
  to_wait=()
  for pkg in cgi fpm opcache; do
    sudo installer -pkg "$tmp_path"/"$php_version"-"$pkg".pkg -target / &
    to_wait+=($!)
  done
  wait "${to_wait[@]}"
  for bin in "$tmp_path"/ext/*.so; do
    add_ext_to_ini "$bin" &
    to_wait+=($!)
  done
  wait "${to_wait[@]}"
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
  sudo curl -o /tmp/pear.phar -sL "$pear_repo/raw/$pecl_version/install-pear-nozlib.phar"
  sudo php /tmp/pear.phar -d "$opt_lib"/"$php_version" -b "$usr_bin"
  for script in pear pecl; do
    sudo "$script" config-set php_ini "$ini_file"
    sudo "$script" config-set php_bin "$opt_bin/php"
  done
  echo '' | sudo tee /tmp/pecl_config >/dev/null 2>&1
}

setup_php
switch_version
add_extensions
add_daemondo
add_pear
