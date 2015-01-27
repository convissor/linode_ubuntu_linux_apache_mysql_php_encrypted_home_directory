#! /bin/bash

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
	if [ $? -ne 0 ] ; then
		echo "ERROR: problem making '$php_src_dir' directory."
		echo "sudo should be used to run this script."
		echo "If you're not using sudo, please try again while doing so."
		exit 1
	fi

	cd "$php_src_dir"
	if [ $? -ne 0 ] ; then
		echo "ERROR: could not cd into '$php_src_dir'."
		exit 1
	fi

	git clone http://git.php.net/repository/php-src.git .
	if [ $? -ne 0 ] ; then
		echo "ERROR: git clone had a problem."
		exit 1
	fi

	git checkout -b PHP-5.5 origin/PHP-5.5
	if [ $? -ne 0 ] ; then
		echo "ERROR: git checkout had a problem."
		exit 1
	fi
else
	new_install=0

	cd "$php_src_dir"
	if [ $? -ne 0 ] ; then
		echo "ERROR: could not cd into '$php_src_dir'."
		exit 1
	fi

	touch .touch
	if [ $? -ne 0 ] ; then
		echo "ERROR: sudo must be used to run this script."
		exit 1
	fi
	rm .touch

	if [ -f Makefile ] ; then
		make clean
		if [ $? -ne 0 ] ; then
			echo "ERROR: make clean had a problem."
			exit 1
		fi
	fi

	./vcsclean
	if [ $? -ne 0 ] ; then
		echo "ERROR: vcsclean had a problem."
		exit 1
	fi

	git checkout -- .
	if [ $? -ne 0 ] ; then
		echo "ERROR: git checkout had a problem."
		exit 1
	fi

	git checkout PHP-5.5
	if [ $? -ne 0 ] ; then
		echo "ERROR: git checkout had a problem."
		exit 1
	fi

	git pull --rebase
	if [ $? -ne 0 ] ; then
		echo "ERROR: git pull had a problem."
		exit 1
	fi
fi

./buildconf --force
if [ $? -ne 0 ] ; then
	echo "ERROR: buildconf had a problem."
	exit 1
fi

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

if [ $? -ne 0 ] ; then
	echo "ERROR: configure had a problem."
	exit 1
fi

make
if [ $? -ne 0 ] ; then
	echo "ERROR: make had a problem."
	echo "  If you get \"virtual memory exhausted: Cannot allocate memory\","
	echo "  make sure your swap space is running."
	exit 1
fi

make install
if [ $? -ne 0 ] ; then
	echo "ERROR: make install had a problem."
	echo "sudo should be used to run this script."
	echo "If you're not using sudo, please try again while doing so."
	exit 1
fi

if [ $new_install -eq 1 ] ; then
	pecl install memcache
	if [ $? -ne 0 ] ; then
		echo "ERROR: pecl install memcache had a problem."
		exit 1
	fi

	grep -q memcache.so "$php_config_file_path/php.ini"
	if [ $? -ne 0 ] ; then
		echo "extension = memcache.so" >> "$php_config_file_path/php.ini"
	fi
else
	pecl upgrade memcache
	if [ $? -ne 0 ] ; then
		echo "ERROR: pecl upgrade memcache had a problem."
		exit 1
	fi
fi
