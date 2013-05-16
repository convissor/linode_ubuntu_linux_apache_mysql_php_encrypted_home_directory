#! /bin/bash

if [[ -z $1 || $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  generate-certificate.sh <name> [self_sign_ssl_cert]"
	echo "  @param string name  the server name/domain to generate the key for"
	echo "  @param bool self_sign_ssl_cert  self sign the certificate (1|0)?"
	echo "         If paramter is not provided, script asks what to do."
	echo ""
	echo "Generates SSL/TLS certificates or certificate signing requests"
	echo "and RSA keys needed for them."
	echo ""
	echo "NOTE: a free certificate from StartSSL (amazingly!) covers both"
	echo "the main domain and one sub-domain of your choosing.  For example:"
	echo "CN=www.example.org"
	echo "X509v3 Subject Alternative Name DNS:www.example.org, DNS:example.org"
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi

name=$1


# GET SETTINGS ============================================

if [ -z "$repo_dir" ] ; then
	repo_dir="$(cd "$(dirname "$0")" && pwd)"
	source "$repo_dir/paths"
fi


# FUNCTIONS ===============================================

function explain_startssl() {
	echo ""
	cat $name.csr
	echo "Submit the signing request, above, to https://www.startssl.com/"
	echo "Save the resulting certificate as '$ssl_cert_dir/$name.crt'."
	echo "DO THIS NOW! (via screen or separate shell login)"
	echo -n "Press ENTER to continue..."
	read -e
}

function finish_process() {
	chmod 400 $name.*
	cd /etc && git add --all && git commit -qam "generate-certificate.sh $name"
}


# GET TO WORK =============================================

if [[ ! -d $ssl_cert_dir ]] ; then
	mkdir -p -m 700 "$ssl_cert_dir"
	if [ $? -ne 0 ] ; then
		echo "ERROR: mkdir had a problem."
		exit 1
	fi
fi

if [ ! -f "$ssl_cert_dir/startssl.ca.pem" ] ; then
	cp "$repo_dir/install/startssl.ca.pem" \
			"$repo_dir/install/startssl.sub.class1.server.ca.pem" \
			"$ssl_cert_dir"
	if [ $? -ne 0 ] ; then
		echo "ERROR: copying ssl CA files had a problem."
		exit 1
	fi
fi

cd "$ssl_cert_dir"
if [ $? -ne 0 ] ; then
	echo "ERROR: cd had a problem."
	exit 1
fi

if [ -f "$name.key" ] ; then
	echo "This certificate already exists."
	echo -n "Do you want to resubmit that signing request? [Y|n] "
	read -e
	if [[ -z $REPLY || $REPLY == y || $REPLY == Y ]] ; then
		explain_startssl
		finish_process
		service postfix reload
		service apache2 reload
		exit
	else
		echo "Okay.  No action will be taken.  Exiting now."
		exit 1
	fi
else
	touch $name.key
fi

chmod 600 $name.*

if [ -z $2 ] ; then
	echo -n "Should this SSL certificate be self signed? [Y|n] "
	read -e
	if [[ -z $REPLY || $REPLY == y || $REPLY == Y ]] ; then
		self_sign_ssl_cert=1
	else
		self_sign_ssl_cert=0
	fi
else
	self_sign_ssl_cert=$2
fi


# req = X.509 Certificate Signing Request (CSR) Management.
# -nodes   Don't encrypt the private key.
# -x509    Creates a self signed certificate.
# -newkey  Create a new certificate request and a new private key.

if [ $self_sign_ssl_cert -eq 1 ] ; then
	openssl req -x509 -days 3650 -newkey rsa:2048 -nodes -keyout $name.key -out $name.crt
	if [ $? -ne 0 ] ; then
		echo "ERROR: key generation had a problem."
		exit 1
	fi

	# openssl verify $name.crt
	# openssl x509 -noout -text -in $name.crt
else
	openssl req -newkey rsa:2048 -nodes -keyout $name.key -out $name.csr
	if [ $? -ne 0 ] ; then
		echo "ERROR: key generation had a problem."
		exit 1
	fi

	# openssl req -noout -verify -key $name.key -in $name.csr
	# openssl req -noout -text -in $name.csr
	# openssl x509 -noout -text -in $name.crt

	explain_startssl
fi

finish_process
