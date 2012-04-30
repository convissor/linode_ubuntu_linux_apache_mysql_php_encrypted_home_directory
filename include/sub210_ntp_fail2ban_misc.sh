#! /bin/bash

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


# NTP / Network Time Protocol =============================

step="ntp"
apt-get -qq -y install ntp
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

ask_to_proceed "$step"


# FAIL2BAN ================================================

step="fail2ban"
apt-get -qq -y install fail2ban
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

file=/etc/fail2ban/jail.conf
# Increase lockout length from 10 minutes to 1 day.
sed -E "s/^bantime\s+=.*/bantime = 86400/g" -i "$file"

ask_to_proceed "$step"


# MISC ====================================================

step="misc tools"
apt-get -qq -y install dict dict-gcide \
	antiword links lynx mb2md poppler-utils tofrodos \
	htop python-software-properties traceroute \
	git-svn git-cvs gitk subversion subversion-tools cvs mercurial \
	sqlite3 sqlite3-doc sqlite sqlite-doc
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

ask_to_proceed "$step"
