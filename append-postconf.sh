#! /bin/bash

if [[ -z $2 || $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  append-postconf.sh <parameter> <value>"
	echo ""
	echo "Appends the given value to the requested Postfix config parameter."
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi

parameter=$1
value=$2

existing=`postconf -h $parameter`
postconf -e "$parameter = $existing, $value"
