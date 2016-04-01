#! /bin/bash

if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  1st-step_iptables-persistent_static-ip-address_unattended-upgrade.sh"
	echo ""
	echo "Linode Ubuntu Configurer, Step 1 of 2."
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
else
	main_domain=
fi


# INSTALL OUR UTILITY SCRIPTS ==========================

"$repo_dir/install-utilities.sh"
if [ $? -ne 0 ] ; then
	echo "ERROR: utility installer had a problem."
	echo "You need to be running as root or via sudo."
	echo "If you're not, please try again while doing so."
	exit 1
fi


# TRACK ALL CONFIGURATION CHANGES =========================

step="git"
step_header "$step"

apt-get -qq -y install git-core git-doc
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi

cd /etc && git init && chmod 770 .git
if [ $? -ne 0 ] ; then
	echo "ERROR: git had a problem."
	exit 1
fi

git config --global user.name root
git config --global user.email root@$host.$domain

echo "mtab" >> .gitignore \
	&& git add --all \
	&& git commit -qam "$step"
if [ $? -ne 0 ] ; then
	echo "ERROR: git had a problem."
	exit 1
fi

ask_to_proceed "$step"


# TIMEZONE ================================================

step="timezone"
step_header "$step"

echo "$continent/$city" > /etc/timezone
if [ $? -ne 0 ] ; then
	echo "ERROR: $step write had a problem."
	echo "sudo should be used to run this script."
	echo "If you're not using sudo, please try again while doing so."
	exit 1
fi
dpkg-reconfigure -fnoninteractive tzdata
if [ $? -ne 0 ] ; then
	echo "ERROR: $step dpkg-reconfigure had a problem."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step mods"


# IPTABLES ================================================

echo ""
echo "Say NO when asked if you want to save the IP tables data."
echo -n "Press ENTER to continue..."
read -e

step="iptables-persistent"
step_header "$step"

apt-get -qq -y install iptables-persistent
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

dir=`dirname "$iptables_file"`
if [ ! -d "$dir" ] ; then
	mkdir -p "$dir"
	if [ $? -ne 0 ] ; then
		echo "ERROR: $step creating directory had a problem."
		exit 1
	fi
fi

# -------------------------------------
cat > "$iptables_file" <<EOIPT
*filter
# Drop inbound packets unless specifically allowed by subsequent rules.
:INPUT DROP [0:0]
:FORWARD DROP [0:0]

# Outbound packets are fine.
:OUTPUT ACCEPT

# Allow SSH,SMTP,HTTP,HTTPS,ESMTP,IMAPS.
-A INPUT -p tcp -m multiport --dports 22,25,80,443,587,993 -j ACCEPT

# Allow DNS.
# -A INPUT -p udp -m multiport --dports 53 -j ACCEPT

# Allow ping, etc.
-A INPUT -p icmp -j ACCEPT

# Allow traceroute responses without letting packets through.
-A INPUT -i eth0 -p udp -m udp --dport 33434:33534 -m state --state NEW -j REJECT

# Allow responses our outgoing transmissions.
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow everything on loopback adapater.
-A INPUT -i lo -j ACCEPT

COMMIT
EOIPT
# -------------------------------------
if [ $? -ne 0 ] ; then
	echo "ERROR: writing iptable rules had a problem."
	exit 1
fi

cp "$iptables_file" "$ip6tables_file"

/etc/init.d/iptables-persistent restart
if [ $? -ne 0 ] ; then
	echo "ERROR: $step restart had a problem."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# SOFTWARE UPGRADE ========================================

step="upgrade"
step_header "$step"

apt-get -qq update && apt-get -qq -y upgrade
if [ $? -ne 0 ] ; then
	echo "ERROR: update or upgrade had a problem."
	echo "sudo should be used to run this script."
	echo "If you're not using sudo, please try again while doing so."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# AUTOMATIC UPGRADES ======================================

step="unattended-upgrades"
step_header "$step"

apt-get -qq -y install unattended-upgrades
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

file=/etc/apt/apt.conf.d/50unattended-upgrades
# Uncomment all origins so all upgrades get installed automatically.
# NOTE: format of identifiers changed between 10.04 and 12.04.
sed -E 's@^/*(\s*"\$\{distro_id\}.*)@\1@g' -i "$file"
# Send an email listing packages upgraded or problems.
sed -E 's@^/*(\s*Unattended-Upgrade::Mail\s.*)@\1@g' -i "$file"
# Automatically restart the server if an upgrade requires it.
sed -E 's@^/*\s*Unattended-Upgrade::Automatic-Reboot.*@Unattended-Upgrade::Automatic-Reboot "true";@g' -i "$file"
# Ensure my reboot hack doesn't get overwritten, don't upgrade the upgrader!
sed -E "s@^/*(\s*Unattended-Upgrade::Package-Blacklist.*)@\1\\n\\t\"unattended-upgrades\";@g" -i "$file"

# Installer presently doesn't enable the package.  Do so manually.
# https://bugs.launchpad.net/bugs/1007835
file=/etc/apt/apt.conf.d/10periodic
grep -q "APT::Periodic::Unattended-Upgrade" "$file"
if [ $? -eq 0 ] ; then
	# Something is in there.  Make sure it's enabled.
	sed -E 's@^/*(\s*APT::Periodic::Unattended-Upgrade\s+)"[0-9]+"@\1"1"@g' -i "$file"
else
	# Nothing is in there.  Add it.
	echo 'APT::Periodic::Unattended-Upgrade "1";' >> "$file"
fi

# Add a few minutes of delay before a reboot required by unattended upgrades.
# Hard coding it like this is not ideal, but is the only option available.
file=/usr/bin/unattended-upgrade
sed "s@\"/sbin/reboot\"])@\"$sbin_dir/linode_reboot\", \"10\"]) # Local change!@g" -i "$file"

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# FIX RESOLV.CONF =========================================

# LINODE QUIRK: /etc/resolv.conf should be symlink.
# Linode's Ubuntu 12.04 image has a mistake, leading to the following error:
# resolvconf: Error: /etc/resolv.conf isn't a symlink, not doing anything.
# Fix it by making sure resolv.conf is a symbolic link, like 12.04 expects.
# https://help.ubuntu.com/12.04/serverguide/network-configuration.html#name-resolution

step="fix resolv.conf"
step_header "$step"

if [ ! -L /etc/resolv.conf ] ; then
	if [ -f /etc/resolv.conf ] ; then
		mv /etc/resolv.conf /run/resolvconf/resolv.conf
	fi
	ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
fi

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# NETWORK CONFIGURATION ===================================

step="networking"
step_header "$step"

echo "$host" > /etc/hostname
hostname -F /etc/hostname

file=/etc/default/dhcpcd
if [ -f "$file" ] ; then
	sed -E "s/^SET_HOSTNAME(.*)/#SET_HOSTNAME\1/g" -i "$file"
fi

if [ -n "$ipv4" ] ; then
	new_ip=$ipv4
	source "$repo_dir/include/hardcode-ip.sh"
fi
if [ -n "$ipv6" ] ; then
	new_ip=$ipv6
	source "$repo_dir/include/hardcode-ip.sh"
fi

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# RESTART =================================================

echo ""
echo "Restart is required.  See you later!"
echo -n "Press ENTER to continue..."
read -e

"$sbin_dir/linode_reboot"
