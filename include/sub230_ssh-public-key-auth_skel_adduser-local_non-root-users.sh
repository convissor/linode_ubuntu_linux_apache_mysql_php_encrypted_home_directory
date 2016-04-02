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


# USERS ===================================================

# PASSWORD STRENGTH ---------------------------------------

step="libpam-passwdqc"
step_header "$step"

apt-get -qq -y install libpam-passwdqc

cd /etc && git add --all && commit_if_needed "$step"


# SSH KEY AUTH --------------------------------------------

step="login via ssh keys only"
step_header "$step"

chmod 751 /home

# Put our pre-existing public key file in place so we don't get locked out.
if [ ! -d "$ssh_auth_key_dir" ] ; then
	mkdir -m 751 "$ssh_auth_key_dir" \
		&& mkdir -m 700 "$ssh_auth_key_dir/root" \
		&& cp "$repo_dir/install/authorized_keys" "$ssh_auth_key_dir/root" \
		&& chmod 600 "$ssh_auth_key_dir/root/authorized_keys" \
		&& mkdir -m 700 "$ssh_auth_key_dir/$admin_user" \
		&& cp "$repo_dir/install/authorized_keys" "$ssh_auth_key_dir/$admin_user" \
		&& chown -R $admin_user:$admin_user "$ssh_auth_key_dir/$admin_user" \
		&& chmod 600 "$ssh_auth_key_dir/$admin_user/authorized_keys"
fi

# Put authorized_keys outside of the encrypted home directories.
file=/etc/ssh/sshd_config
sed -E "s/^#?\s*PasswordAuthentication\s+(yes|no)/PasswordAuthentication no/g" -i "$file"
sed -E "s@^#?\s*AuthorizedKeysFile\s+.*@AuthorizedKeysFile \"$ssh_auth_key_dir/%u/authorized_keys\"@g" -i "$file"


# -------------------------------------
cat >> "$etc_profile" <<EOPROFILE

# MY CUSTOMIZATIONS

# An encrypted home directory does not get decrypted when using SSH
# public key authentication.
if [ -f "\$HOME/Access-Your-Private-Data.desktop" ] ; then
	echo "Enter your password to decrypt your home directory..."
	ecryptfs-mount-private
	if [ \$? -ne 0 ] ; then
		echo "OOPS! Decrypting your home directory didn't work."
		echo "Perhaps you didn't put in the right password."
		echo "You can try again by calling:  ecryptfs-mount-private"
	fi
	cd "\$HOME"
fi
EOPROFILE
# -------------------------------------

service ssh reload

cd /etc && git add --all && commit_if_needed "$step"


# SKELETON FILES --------------------------------

step="skeleton files"
step_header "$step"

mkdir -p "$mail_skel_dir/Maildir/cur" \
         "$mail_skel_dir/Maildir/new" \
         "$mail_skel_dir/Maildir/tmp" \
         "$mail_skel_dir/Maildir/.Deleted Messages/cur" \
         "$mail_skel_dir/Maildir/.Deleted Messages/new" \
         "$mail_skel_dir/Maildir/.Deleted Messages/tmp" \
         "$mail_skel_dir/Maildir/.Drafts/cur" \
         "$mail_skel_dir/Maildir/.Drafts/new" \
         "$mail_skel_dir/Maildir/.Drafts/tmp" \
         "$mail_skel_dir/Maildir/.Sent Messages/cur" \
         "$mail_skel_dir/Maildir/.Sent Messages/new" \
         "$mail_skel_dir/Maildir/.Sent Messages/tmp" \
         "$mail_skel_dir/Maildir/.Spam/cur" \
         "$mail_skel_dir/Maildir/.Spam/new" \
         "$mail_skel_dir/Maildir/.Spam/tmp" \
         "$mail_skel_dir/.spamassassin"

touch "$mail_skel_dir/procmail.log"

cat > "$mail_skel_dir/.procmailrc" <<EOUPRC
VERBOSE=off
LOGABSTRACT=all
#TRAP='echo ^^Last handled by \$INCLUDERC'

# Put me before rc.vacation but after everything else.
INCLUDERC=$procmail_dir/rc.spamassassin
EOUPRC

cat > "$mail_skel_dir/.spamassassin/user_prefs" <<EOSAUP
# http://us.spamassassin.org/doc/Mail_SpamAssassin_Conf.html
# System default configuration is in /etc/spamassassin/local.cf.

# Put the score at start of subjects for spam messages.
# But there's a bug right now that prevents it from working:
# https://bugs.launchpad.net/ubuntu/+source/spamassassin/+bug/1006447
# https://issues.apache.org/SpamAssassin/show_bug.cgi?id=6651
rewrite_header Subject _SCORE(0)_ |

# Which languages are legitimate for you.  See documentation for choices.
ok_languages en
EOSAUP

mkdir -m 700 /etc/skel/.ssh

# Allow dots in file names.  Fix the regex too (Debian bug 630750).
echo 'NAME_REGEX="^[a-z][-a-z0-9_.]*\$?$"' >> /etc/adduser.conf
# Tighter file permissions.
sed "s/DIR_MODE\s*=.*/DIR_MODE=0700/g" -i /etc/adduser.conf
chmod 640 /etc/skel/.bash* /etc/skel/.profile

# -------------------------------------
cat >> "$etc_profile" <<EOPROFILE

MAIL="$mail_dir/\$USER/Maildir"

if [ -f "\$HOME/.need-to-make-links" ] ; then
	"$adduser_links_script"
fi
EOPROFILE
# -------------------------------------

touch /etc/skel/.need-to-make-links

# NOTE: install-utilities.sh puts adduser scripts in place.

cd /etc && git add --all && commit_if_needed "$step"


# SOFTWARE FOR ENCRYPTING HOME DIRECTORIES ----------------

step="ecryptfs-utils"
step_header "$step"

apt-get -qq -y install ecryptfs-utils

mkdir -p /home/.ecryptfs \
	&& chmod 751 /home/.ecryptfs


# ADMIN USER ----------------------------------------------

step="admin user"
step_header "$step"

echo ""
echo "About to create a new administrative user account."
echo -n "Press ENTER to continue..."
read -e

# Create admin user with encrypted home directory.
adduser "$admin_user" --encrypt-home

# Give them the ability to sudo and manage the system.
adduser "$admin_user" sudo

cd /etc && git add --all && commit_if_needed "$step pre-alias"

# Send root email to the admin user.
"$repo_dir/write-alias.sh" root "$root_emails_to"

# Forward admin email to another server, if desired.
if [ -n "$admin_email_fwd" ] ; then
	"$repo_dir/write-alias.sh" "$admin_user" "$admin_email_fwd"
fi

# Disable root access.
passwd -l root

file=/etc/ssh/sshd_config
sed -E "s/^#?\s*PermitRootLogin\s+(yes|no)/PermitRootLogin no/g" -i "$file"

service ssh reload

cd /etc && git add --all && commit_if_needed "$step final"

echo ""
echo "ATTENTION: the 'root' account has been disabled."
echo "Future logins must SSH in as '$admin_user' using public key auth."
echo "Test it NOW to make sure you can get in, BEFORE logging out of your"
echo "current SSH session."
echo -n "Press ENTER to continue..."
read -e

ask_to_proceed "$step"
