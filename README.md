# PHP5 for darwin

<a href="https://github.com/shivammathur/php5-darwin" title="php5 install scripts for darwin"><img alt="Build status" src="https://github.com/shivammathur/php5-darwin/workflows/Test/badge.svg"></a>
<a href="https://github.com/shivammathur/php5-darwin/blob/main/LICENSE" title="license"><img alt="LICENSE" src="https://img.shields.io/badge/license-MIT-428f7e.svg"></a>
<a href="https://github.com/shivammathur/php5-darwin/releases/latest" title="builds"><img alt="PHP Versions Supported" src="https://img.shields.io/badge/php-5.3, 5.4 and 5.5-8892BF.svg"></a>

> Scripts to install end of life PHP versions.

PHP versions in this project have reached end of life and should not be used except for testing backward-compatibility.

## Usage

### PHP 5.3
```bash
curl -sSL https://github.com/shivammathur/php5-darwin/releases/latest/download/install.sh | bash -s 53
```

### PHP 5.4
```bash
curl -sSL https://github.com/shivammathur/php5-darwin/releases/latest/download/install.sh | bash -s 54
```

### PHP 5.5
```bash
curl -sSL https://github.com/shivammathur/php5-darwin/releases/latest/download/install.sh | bash -s 55
```

## SAPI
- cli
- cgi
- fpm

## License

- This project is released under the [MIT license](http://choosealicense.com/licenses/mit/). Please see the [license file](LICENSE) for more information.
- This project uses builds from [macports](https://github.com/macports/macports-ports "macports/macports-ports") and their LICENSE can be found [here](MACPORTS_LICENSE).
- Macports build of php-fpm uses `daemondo` binary for launching services. It is redistributed with the PHP builds and its LICENSE can be found [here](DAEMONDO_LICENSE).