#! /bin/bash

if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  2nd-step_run-sub-scripts.sh"
	echo ""
	echo "Linode Ubuntu Configurer, Step 2 of 2."
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

if [ $is_main_server_for_domain -eq 1 ] ; then
	main_domain="$domain www.$domain"
	main_domain_comma=", $domain, www.$domain"
	cert_name=$domain
else
	main_domain=
	main_domain_comma=
	cert_name=$host.$domain
fi


# RUN THE SUB-SCRIPTS =====================================

source "$repo_dir/include/sub210_ntp_fail2ban_misc.sh"
source "$repo_dir/include/sub220_postfix_spf_dkim_procmail_dovecot_mutt.sh"
source "$repo_dir/include/sub230_ssh-public-key-auth_skel_adduser-local_non-root-users.sh"
source "$repo_dir/include/sub240_mysql_apache2-itk_php.sh"


# DOMAIN SPECIFIC CONFIGURATIIONS =========================

"$repo_dir/new-domain.sh" settings
if [ $? -ne 0 ] ; then
	echo "ERROR: new-domain.sh had a problem."
	exit 1
fi

echo ""
echo "CONGRATULATIONS!"
ask_to_proceed "ALL"
