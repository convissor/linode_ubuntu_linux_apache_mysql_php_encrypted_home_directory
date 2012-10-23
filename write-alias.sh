#! /bin/bash -e

if [[ -z $2 || $1 == "-h" || $1 == "--help" ]] ; then
	echo "Usage:  write-alias.sh <from> <to>"
	echo ""
	echo "Adds an alias to /etc/aliases and calls newaliases."
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi

from=$1
to=$2


# GET SETTINGS ============================================

if [ -z "$repo_dir" ] ; then
	repo_dir="$(cd "$(dirname "$0")" && pwd)"
	source "$repo_dir/paths"
fi


# CHECK THAT THE REPO IS CLEAN ============================

cd /etc
if [ -n "$(git status --porcelain)" ] ; then
	echo "Uncommitted changes exist in /etc."
	echo "Commit them first then call this script again."
	exit 1
fi


# GET TO WORK =============================================

if [ ! -f "$aliases_file" ] ; then
	touch "$aliases_file"
fi

grep -Eq "^$from:" "$aliases_file"
if [ $? -ne 0 ] ; then
	# Add it.
	echo "$from: $to" >> "$aliases_file"
else
	# Replace it.
	sed -E "s/^$from:.*/$from: $to/g" -i "$aliases_file"
fi

newaliases

git commit -qam "write-alias.sh $from $to"
