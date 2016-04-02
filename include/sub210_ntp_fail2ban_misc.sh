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


# NTP / Network Time Protocol =============================

step="ntp"
step_header "$step"

apt-get -qq -y install ntp

cd /etc && git add --all && commit_if_needed "$step"

ask_to_proceed "$step"


# FAIL2BAN ================================================

step="fail2ban"
step_header "$step"

apt-get -qq -y install fail2ban

cd /etc && git add --all && commit_if_needed "$step"

file=/etc/fail2ban/jail.conf
# Increase lockout length from 10 minutes to 1 day.
sed -E "s/^bantime\s+=.*/bantime = 86400/g" -i "$file"

ask_to_proceed "$step"


# MISC ====================================================

step="misc tools"
step_header "$step"

apt-get -qq -y install \
	dict \
	dict-gcide \
	antiword \
	links \
	lynx \
	\
	mb2md \
	poppler-utils \
	tofrodos \
	htop \
	python-software-properties \
	traceroute \
	\
	git-svn \
	git-cvs \
	gitk \
	subversion \
	subversion-tools \
	cvs \
	mercurial \
	bzr \
	ppa-purge \
	\
	autoconf \
	autoconf-doc \
	autoconf2.13 \
	automake1.4 \
	re2c \
	build-essential \
	pkg-config \
	\
	sqlite3 \
	sqlite3-doc \
	sqlite \
	sqlite-doc

cd /etc && git add --all && commit_if_needed "$step"

ask_to_proceed "$step"


# CTAGS AND GIT HOOKS =====================================

step="universal ctags and related git hooks"
step_header "$step"

mkdir -p "$source_dir"

cd "$source_dir"
git clone https://github.com/universal-ctags/ctags.git universal-ctags
cd universal-ctags
./autogen.sh
./configure
make
make install

# Ensure the template directory is there.
mkdir -p /usr/share/git-core/templates/hooks

# Put our hooks in Git's default template directory.
# Then, whenever git init or clone are called, these files get copied into the new
# repository's hooks directory.
cp "$repo_dir/git-hooks/"* /usr/share/git-core/templates/hooks
chmod 755 /usr/share/git-core/templates/hooks/*

# Make calling "git ctags" execute our ctags script.
git config --system alias.ctags '!.git/hooks/ctags'

# Obtain and install my Ctags for SVN script.
cd "$source_dir"
git clone git://github.com/convissor/ctags_for_svn
ln -s "$source_dir/ctags_for_svn/ctags_for_svn.sh" "$bin_dir/ctags_for_svn.sh"

cd /etc && git add --all && commit_if_needed "$step"
ask_to_proceed "$step"


# VIM SETTINGS ========================================

cd
if [[ ! -d vim-settings ]] ; then
	git clone git://github.com/convissor/vim-settings.git
	cd vim-settings
else
	cd vim-settings
	# Ensure files have right permissions in case copied via thumb drive.
	git reset --hard HEAD
fi

if [[ ! -e ~/.vimrc ]] ; then
	./setup.sh
fi

cd
if [[ ! -e /etc/skel/vim-settings ]] ; then
	cp -R vim-settings /etc/skel
	cd /etc/skel
	ln -s vim-settings/.vim .vim
	ln -s vim-settings/.vimrc .vimrc
	echo "EDITOR=/usr/bin/vim" >> .profile
fi
