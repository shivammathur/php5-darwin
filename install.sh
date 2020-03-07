export TERM=xterm
curl -o /tmp/php$1.tar.xz -sSL https://github.com/shivammathur/php5-darwin/releases/download/0.0.2RC1/php"$1".tar.xz
sudo tar xf /tmp/php$1.tar.xz -C /tmp
sudo installer -pkg /tmp/php$1/php$1.mpkg -target /
sudo cp /opt/local/etc/php$1/php.ini-development /opt/local/etc/php$1/php.ini
sudo mv /opt/local/bin/php$1 /opt/local/bin/php
sudo mv /opt/local/bin/phpize$1 /opt/local/bin/phpize
sudo mv /opt/local/bin/php-config$1 /opt/local/bin/php-config
sudo ln -sf /opt/local/bin/* /usr/local/bin
ext_dir=$(php -d "date.timezone=UTC" -i | grep -Ei "extension_dir => /" | sed -e "s|.*=> s*||")
ini_file=/opt/local/etc/php"$1"/php.ini
sudo chmod 777 "$ini_file"
echo "date.timezone=UTC" >>"$ini_file"
sudo mkdir -p $ext_dir
sudo cp -a /tmp/php$1/ext/*.so $ext_dir
sudo cp -a /tmp/php$1/lib/* /opt/local/lib
for bin in /tmp/php$1/ext/*.so; do
  extension=$(basename $bin | cut -d'.' -f 1)
  echo "extension=$extension.so" >>"$ini_file"
done
sudo installer -pkg /tmp/php$1/php$1-opcache.pkg -target /
pecl_version='master'
if [ "$1" = "53" ]; then
  pecl_version='v1.9.5'
fi
sudo curl -o /tmp/pear.phar -sSL https://github.com/pear/pearweb_phars/raw/$pecl_version/install-pear-nozlib.phar
sudo php /tmp/pear.phar -d /opt/local/lib/php$1 -b /usr/local/bin