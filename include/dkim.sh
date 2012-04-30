if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  do not call this script directly"
	echo ""
	echo "Generates the DKIM key for the given domain."
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi

mkdir -p -m 750 "$domain_dkim_key_dir"
if [ $? -ne 0 ] ; then
	echo "ERROR: setting up dkim key dir had a problem."
	exit 1
fi

opendkim-genkey -D "$domain_dkim_key_dir" -d $email_domain
if [ $? -ne 0 ] ; then
	echo "ERROR: dkim genkey had a problem."
	exit 1
fi

chmod 640 "$domain_dkim_key_dir"/*
if [ $? -ne 0 ] ; then
	echo "ERROR: chmod dkim files had a problem."
	exit 1
fi

echo "$email_domain" >> "$dkim_dir/Domain"
echo "default._domainkey.$email_domain $email_domain:default:$domain_dkim_key_dir/default.private" >> "$dkim_dir/KeyTable"
echo "$email_domain default._domainkey.$email_domain" >> "$dkim_dir/SigningTable"
