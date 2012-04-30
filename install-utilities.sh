#! /bin/bash

if [[ -n "$1" ]] ; then
	echo "Usage:  install-utilities.sh"
	echo ""
	echo "Installs our utility scripts:"
	echo "  adduser.local"
	echo "  adduser.links"
	echo "  gpw"
	echo "  linode_api"
	echo "  linode_reboot"
	echo "  new-domain-procedure.sql"
	echo "  nm"
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


# DECLARE FUNCTION ========================================

function replace_tokens() {
	search=$1
	replace=$2

	sed "s@$search@$replace@g" -i "$bin_dir/nm" \
		&& sed "s@$search@$replace@g" -i "$adduser_script" \
		&& sed "s@$search@$replace@g" -i "$adduser_links_script" \
		&& sed "s@$search@$replace@g" -i "$sbin_dir/linode_api" \
		&& sed "s@$search@$replace@g" -i "$sbin_dir/linode_reboot"
	if [ $? -ne 0 ] ; then
		echo "ERROR: replacing text in adduser scripts had a problem."
		exit 1
	fi
}


# GET TO WORK =============================================

cp "$repo_dir/install/adduser.local" "$adduser_script" \
	&& chmod 754 "$adduser_script"
if [ $? -ne 0 ] ; then
	echo "ERROR: ."
	exit 1
fi

cp "$repo_dir/install/adduser.links" "$adduser_links_script" \
	&& chmod 755 "$adduser_links_script"
if [ $? -ne 0 ] ; then
	echo "ERROR: saving adduser link script had a problem."
	exit 1
fi

cp "$repo_dir/install/gpw" "$bin_dir" \
	&& chmod 755 "$bin_dir/gpw"
if [ $? -ne 0 ] ; then
	echo "ERROR: installing generate password script had a problem."
	exit 1
fi

cp "$repo_dir/install/nm" "$bin_dir" \
	&& chmod 755 "$bin_dir/nm"
if [ $? -ne 0 ] ; then
	echo "ERROR: installing new mail script had a problem."
	exit 1
fi

replace_tokens REPLACE_MAIL_DIR "$mail_dir"
replace_tokens REPLACE_TRANSFER_DIR "$transfer_dir"
replace_tokens REPLACE_HOST "$host"
replace_tokens REPLACE_DOMAIN "$domain"
replace_tokens REPLACE_CONNECTION_INFO_DIR "$connection_info_dir"
replace_tokens REPLACE_SSH_AUTH_KEY_DIR "$ssh_auth_key_dir"
replace_tokens REPLACE_MAIL_SKEL_DIR "$mail_skel_dir"
replace_tokens REPLACE_POSTFIX_MYDOMAIN_MAP "$postfix_mydomain_map"
replace_tokens REPLACE_POSTFIX_VIRTUAL_ALIAS_MAP "$postfix_virtual_alias_map"


cp "$repo_dir/install/linode_api" "$repo_dir/install/linode_reboot" \
		"$sbin_dir" \
	&& chmod 750 "$sbin_dir"/linode_*
if [ $? -ne 0 ] ; then
	echo "ERROR: installing linode_api scripts had a problem."
	exit 1
fi

replace_tokens REPLACE_API_KEY "$api_key"
replace_tokens REPLACE_API_SCRIPT "$sbin_dir/linode_api"
replace_tokens REPLACE_LINODE_ID $linode_id


mkdir -p -m 755 "$procmail_dir" \
	&& cp "$repo_dir/install/rc.spamassassin" "$procmail_dir" \
	&& chmod 644 "$procmail_dir/rc.spamassassin"
if [ $? -ne 0 ] ; then
	echo "ERROR: copying $step procmail recipe had a problem."
	exit 1
fi


cd /etc && git add --all && git commit -qam "install-utilities.sh"


# Place this in a loop in case the user mistypes the password.
loop_again=1
while [ $loop_again -eq 1 ] ; do
	echo ""
	echo "The next step will ask for your existing MySQL root password..."

	mysql -u root -p mysql < "$repo_dir/install/new-domain-procedure.sql"
	if [ $? -ne 0 ] ; then
		echo "ERROR: executing mysql-setup.sql had a problem."
		echo -n "Hit ENTER to try again or CTRL-C to stop execution..."
		read -e
		loop_again=1
	else
		loop_again=0
	fi
done


echo "Installing the utility scripts is DONE"
