#! /bin/bash -e

if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  php-build.sh"
	echo ""
	echo "Obtains PHP's source code, then builds and installs it."
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi

# GET SETTINGS ============================================

if [ -z "$repo_dir" ] ; then
	repo_dir="$(cd "$(dirname "$0")" && pwd)"
	source "$repo_dir/paths"
fi


# GET TO WORK =============================================

if [ ! -d "$php_src_dir" ] ; then
	new_install=1

	mkdir -p "$php_src_dir"

	cd "$php_src_dir"

	git clone http://git.php.net/repository/php-src.git .

	git checkout -b PHP-5.6 origin/PHP-5.6
else
	new_install=0

	cd "$php_src_dir"

	touch .touch
	rm .touch

	if [ -f Makefile ] ; then
		make clean
	fi

	./vcsclean

	git checkout -- .

	git checkout PHP-5.6

	git pull --rebase
fi

./buildconf --force

	#--enable-bcmath \
./configure \
	--prefix=/usr/local \
	--with-config-file-path=$php_config_file_path \
	--with-pear \
	--with-layout=GNU \
	--with-bz2 \
	--with-curl \
	--with-gd \
	--with-jpeg-dir=/usr/lib \
	--enable-mbstring \
	--with-mcrypt \
	--with-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
	--with-openssl \
	--enable-soap \
	--with-tidy \
	--with-xsl \
	--with-zlib

make
make install

if [ $new_install -eq 1 ] ; then
	pecl install memcache

	set +e
	grep -q memcache.so "$php_config_file_path/php.ini"
	if [ $? -ne 0 ] ; then
		set -e
		echo "extension = memcache.so" >> "$php_config_file_path/php.ini"
	fi
	set -e
else
	pecl upgrade memcache
fi
