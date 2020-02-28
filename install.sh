curl -o /tmp/php.tar.xz -sSL https://github.com/shivammathur/php5-darwin/releases/latest/download/php"$1".tar.xz
sudo tar -C /usr/local -xf /tmp/php.tar.xz
sudo chmod 777 /usr/local/php5/post-install
sudo /usr/local/php5/post-install
for tool in pear peardev pecl php php-config phpize; do
  sudo ln -sf /usr/local/php5/bin/"$tool" /usr/local/bin/"$tool"
done