#! /bin/bash -e

if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  this script is called by 2nd-step_run-sub-scripts.sh"
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi


# GET SETTINGS ============================================

if [ -z "$repo_dir" ] ; then
	# Get _parent_ directory.
	repo_dir="$(dirname "$(cd "$(dirname "$0")" && pwd)")"
	source "$repo_dir/settings"
	source "$repo_dir/paths"
fi


# MYSQL ===================================================

step="mysql"
step_header "$step"

apt-get -qq -y install mysql-client mysql-server

cd /etc && git add --all && commit_if_needed "$step"

file=/etc/mysql/my.cnf

replace="[client]\\ndefault-character-set = utf8"
sed s/\\[client\\]/"$replace"/g -i "$file"

replace="[mysqld]\\ncharacter-set-server = utf8\\ncollation-server = utf8_bin\\ndefault-storage-engine = InnoDB\\ninnodb_file_per_table = 1\\n"
sed s/\\[mysqld\\]/"$replace"/g -i "$file"

service mysql restart

cd /etc && git add --all && commit_if_needed "$step mods"

# Place this in a loop in case the user mistypes the password.
loop_again=1
set +e
while [ $loop_again -eq 1 ] ; do
	echo ""
	echo "The next step will ask for your existing MySQL root password..."

	# Remove privileges from empty users and the test database.
	cat > mysql -u root -p mysql <<EOPRIV
DELETE FROM user WHERE User = '';
DELETE FROM db WHERE Db LIKE 'test%';
FLUSH PRIVILEGES;
EOPRIV
	if [ $? -ne 0 ] ; then
		echo "ERROR: executing empty/test removal had a problem."
		echo -n "Hit ENTER to try again or CTRL-C to stop execution..."
		read -e
		loop_again=1
	else
		loop_again=0
	fi
done
set -e

# NOTE: our mysql-setup.sql is put in place by install-utilities.sh.

ask_to_proceed "$step"


# APACHE HTTPD ============================================

step="apache"
step_header "$step"

apt-get -qq -y install apache2-mpm-itk apache2-doc apache2-utils \
	libapache2-mod-xsendfile

cd /etc && git add --all && commit_if_needed "$step"

a2enmod actions rewrite ssl

# Disable default site.
a2dissite default

# Prevent POODLE attacks.
file=/etc/apache2/mods-available/ssl.conf
sed s/"SSLProtocol.*"/"SSLProtocol All -SSLv2 -SSLv3"/g -i "$file"

file=/etc/apache2/ports.conf
echo "NameVirtualHost *:443" >> "$file"

# -------------------------------------
cat > /etc/apache2/conf.d/my-customizations <<EOACD
# MY CUSTOMIZATIONS

# Disable access to the entire file system.
# Each site's configuration will permit access to what it needs.
<Directory />
	Options None
	AllowOverride None
	Deny from all
	Satisfy all
</Directory>

ScriptAlias /local-bin /usr/local/bin
AddHandler application/x-httpd-php php inc
Action application/x-httpd-php /local-bin/php-cgi

# Let PHP CGI scripts work, block access to everything else.
<Directory /usr/local/bin>
	<Files "php-cgi">
		Allow from all
	</Files>
	Options None
	AllowOverride None
	Deny from all
	Satisfy all
</Directory>

# Block .git directories and files that start with a dot.
# Prevents access to .git, .user.ini, etc.
<DirectoryMatch .*/\.git>
	Deny from all
	Satisfy all
</DirectoryMatch>
<FilesMatch ^\..*>
	Deny from all
	Satisfy all
</FilesMatch>

# Block PHP include files.
<FilesMatch \.inc$>
	Deny from all
	Satisfy all
</FilesMatch>

# Block execution of scripts in WordPress' internal directories.
<DirectoryMatch /(wp-content|wp-includes)/>
	<FilesMatch \.php$>
		Deny from all
		Satisfy all
	</FilesMatch>
</DirectoryMatch>

ServerSignature Off
ServerTokens Product
EOACD
# -------------------------------------

service apache2 restart

cd /etc && git add --all && commit_if_needed "$step mods"

ask_to_proceed "$step"


# MEMCACHE ================================================

step="memcache"
step_header "$step"

apt-get -qq -y install memcached

cd /etc && git add --all && commit_if_needed "$step"

ask_to_proceed "$step"


# PHP =====================================================

step="build-dep php5"
step_header "$step"

# The following list of dependencies comes from these two commands:
# Note: add-apt-repository is in the python-software-properties package.
#
# add-apt-repository -y ppa:ondrej/php5 && apt-get -qq update
# apt-get --assume-no build-dep php5 > phpdeps54.block
#
# I removed apache2-prefork-dev, firebird-dev, firebird2.5-common
# firebird2.5-common-doc, libfbclient2

apt-get -qq -y install \
  aspell aspell-en autoconf automake autotools-dev \
  binutils bison build-essential chrpath comerr-dev cpp cpp-4.6 debhelper \
  dh-apparmor dictionaries-common diffstat dpkg-dev \
  flex fontconfig-config \
  freetds-common freetds-dev g++ g++-4.6 gcc gcc-4.6 gettext hardening-wrapper \
  html2text intltool-debian krb5-multidev libapr1-dev libaprutil1-dev \
  libaspell-dev libaspell15 libbison-dev libbz2-dev libc-client2007e \
  libc-client2007e-dev libc-dev-bin libc6-dev libcroco3 libct4 \
  libcurl4-openssl-dev libdb-dev libdb5.1-dev libdpkg-perl libenchant-dev \
  libenchant1c2a libevent-core-2.0-5 libevent-dev libevent-extra-2.0-5 \
  libevent-openssl-2.0-5 libevent-pthreads-2.0-5 libexpat1-dev \
  libfl-dev libfontconfig1 libfontconfig1-dev libfreetype6-dev libgcrypt11-dev \
  libgd2-xpm libgd2-xpm-dev libgettextpo0 libglib2.0-bin libglib2.0-data \
  libglib2.0-dev libgmp-dev libgmp3-dev libgmpxx4ldbl libgnutls-dev \
  libgnutls-openssl27 libgnutlsxx27 libgomp1 libgpg-error-dev libgssrpc4 \
  libhunspell-1.3-0 libib-util libicu-dev libicu48 libidn11-dev libjpeg-dev \
  libjpeg-turbo8 libjpeg-turbo8-dev libjpeg8 libjpeg8-dev libkadm5clnt-mit8 \
  libkadm5srv-mit8 libkdb5-6 libkrb5-dev libldap2-dev libltdl-dev libltdl7 \
  libmagic-dev libmcrypt-dev libmcrypt4 libmhash-dev libmhash2 libmpc2 \
  libmpfr4 libmysqlclient-dev libodbc1 libonig-dev libonig2 libp11-kit-dev \
  libpam0g-dev libpcre3-dev libpcrecpp0 libperl-dev libperl5.14 libpng12-dev \
  libpq-dev libpq5 libpspell-dev libpthread-stubs0 libpthread-stubs0-dev \
  libqdbm-dev libqdbm14 libquadmath0 librecode-dev librecode0 librtmp-dev \
  libsasl2-dev libsensors4 libsensors4-dev libsnmp-base libsnmp-dev \
  libsnmp-perl libsnmp15 libsqlite3-dev libssl-dev libstdc++6-4.6-dev \
  libsybdb5 libtasn1-3-dev libtidy-0.99-0 libtidy-dev libtool libunistring0 \
  libwrap0-dev libx11-dev libxau-dev libxcb1-dev libxdmcp-dev libxml2-dev \
  libxmltok1 libxmltok1-dev libxpm-dev libxpm4 libxslt1-dev libxslt1.1 \
  linux-libc-dev m4 make mlock netcat-traditional odbcinst odbcinst1debian2 \
  pkg-config po-debconf quilt re2c ttf-dejavu-core unixodbc unixodbc-dev \
  uuid-dev x11proto-core-dev x11proto-input-dev x11proto-kb-dev \
  xorg-sgml-doctools xtrans-dev zlib1g-dev

cd /etc && git add --all && commit_if_needed "$step"

ask_to_proceed "$step"

step="php compile"
step_header "$step"

mkdir -m 755 "$php_config_file_path"

# -------------------------------------
cat > "$php_config_file_path/php.ini" <<EOINI
include_path = ".:/usr/local/lib/php"
date.timezone = $continent/$city
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
log_errors = On
display_errors = Off
short_open_tag = On
output_buffering = Off
EOINI
# -------------------------------------

"$repo_dir/php-build.sh"

cd /etc && git add --all && commit_if_needed "$step mods"

ask_to_proceed "$step"
