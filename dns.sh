#! /bin/bash

if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  dns.sh"
	echo ""
	echo "Uses Linode's API to configure the DNS server."
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi


# GET SETTINGS ============================================

if [ -z "$repo_dir" ] ; then
	repo_dir="$(cd "$(dirname "$0")" && pwd)"
	source "$repo_dir/settings"
	source "$repo_dir/paths"
fi

if [ "$dns_skip_questions" != "y" ] ; then
	loop_again=1
	while [ $loop_again -eq 1 ] ; do
		echo -n "Domain name to add DNS record for (do NOT include 'www.'): "
		read -e
		if [ -z "$REPLY" ] ; then
			echo "ERROR: Quit jumping around, bunny! Enter the required data..."
			loop_again=1
		else
			loop_again=0
			domain=$REPLY
		fi
	done

	echo -n "Mail server [$mail_server]: "
	read -e
	if [ -n "$REPLY" ] ; then
		mail_server=$REPLY
	fi

	echo -n "IPv4 address [$ipv4]: "
	read -e
	if [ -n "$REPLY" ] ; then
		ipv4=$REPLY
	fi

	echo -n "IPv6 address [$ipv6]: "
	read -e
	if [ -n "$REPLY" ] ; then
		ipv6=$REPLY
	fi
fi


# GET TO WORK =============================================

# See if DNS for this domain exists already.
response=`"$sbin_dir/linode_api" "domain.list"`
if [ $? -ne 0 ] ; then
	echo "ERROR: calling API had a problem."
	exit 1
fi
existing_id=`echo $response | sed -E "s/.*\"DomainID\":([0-9]+).*\"$domain\".*/\1/i"`

if [[ ${#existing_id} -lt 20 && ${#existing_id} -gt 0 ]] ; then
	# Yep, it exists.  Kill it.
	response=`"$sbin_dir/linode_api" "domain.delete" \
		"DomainID=$existing_id"`
	if [ $? -ne 0 ] ; then
		echo "ERROR: calling API had a problem."
		exit 1
	fi
fi

response=`"$sbin_dir/linode_api" "domain.create" \
	"Type=master&SOA_Email=postmaster%40$domain&Domain=$domain"`
if [ $? -ne 0 ] ; then
	echo "ERROR: calling API had a problem."
	exit 1
fi
id=`echo "$response" | sed -E 's/.*"DomainID"\s*:\s*([0-9]+).*/\1/gi'`

if [ -n "$ipv4" ] ; then
	response=`"$sbin_dir/linode_api" "domain.resource.create" \
		"Type=A&Name=$domain&Target=$ipv4&DomainID=$id"`
	if [ $? -ne 0 ] ; then
		echo "ERROR: calling API had a problem."
		exit 1
	fi
fi

if [ -n "$ipv6" ] ; then
	response=`"$sbin_dir/linode_api" "domain.resource.create" \
		"Type=AAAA&Name=$domain&Target=$ipv6&DomainID=$id"`
	if [ $? -ne 0 ] ; then
		echo "ERROR: calling API had a problem."
		exit 1
	fi
fi

response=`"$sbin_dir/linode_api" "domain.resource.create" \
	"Type=CNAME&Name=www&Target=$domain&DomainID=$id"`
if [ $? -ne 0 ] ; then
	echo "ERROR: calling API had a problem."
	exit 1
fi

response=`"$sbin_dir/linode_api" "domain.resource.create" \
	"Type=MX&Target=$mail_server&DomainID=$id"`
if [ $? -ne 0 ] ; then
	echo "ERROR: calling API had a problem."
	exit 1
fi

domain_dkim_key_dir="$dkim_key_dir/$domain"
dkim_file="$domain_dkim_key_dir/default.txt"
if [ -f "$dkim_file" ] ; then
	# Extract the value section from the DNS formatted file.
	dkim=`sed -E 's/^.*"([^"]+)".*$/\1/' < "$dkim_file"`
	if [ $? -ne 0 ] ; then
		echo "ERROR: reading dkim key had a problem."
		exit 1
	fi

	# Encode the value so it doesn't mess up the API URI.
	dkim="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$dkim")"
	if [ $? -ne 0 ] ; then
		echo "ERROR: encoding dkim key had a problem."
		exit 1
	fi

	response=`"$sbin_dir/linode_api" "domain.resource.create" \
		"Type=TXT&Target=$dkim&DomainID=$id"`
	if [ $? -ne 0 ] ; then
		echo "ERROR: calling API had a problem."
		exit 1
	fi
else
	echo "=========================="
	echo "NOTE: Since no DKIM key file exists at '$dkim_file',"
	echo "we will assume this domain will not be sending mail."
	echo "SPF will be marked accordingly and no DKIM record will be created."
	echo "=========================="
fi


if [ -f "$dkim_file" ] ; then
	# Only mail from analysisandsolutions.com is legitimate.
	spf="v=spf1 a:analysisandsolutions.com -all"
else
	# No mail is legitimate.
	spf="v=spf1 -all"
fi

# Encode the value so it doesn't mess up the API URI.
spf="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$spf")"
if [ $? -ne 0 ] ; then
	echo "ERROR: encoding spf value had a problem."
	exit 1
fi

response=`"$sbin_dir/linode_api" "domain.resource.create" \
	"Type=TXT&Target=$spf&DomainID=$id"`
if [ $? -ne 0 ] ; then
	echo "ERROR: calling API had a problem."
	exit 1
fi


ask_to_proceed "DNS record generation"
