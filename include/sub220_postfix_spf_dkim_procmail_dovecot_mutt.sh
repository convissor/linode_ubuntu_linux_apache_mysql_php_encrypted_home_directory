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

if [ $is_main_server_for_domain -eq 1 ] ; then
	main_domain_comma=", $domain, www.$domain"
	email_domain=$domain
	cert_name=$domain
else
	main_domain_comma=
	email_domain=$host.$domain
	cert_name=$host.$domain
fi


# TLS CERTIFICATE =========================================

# Generate certificate before setting up mail server, avoid these errors:
# warning: cannot get RSA certificate from file <file>: disabling TLS support

# If you already have certificates, move them into place.
if [ -d ~/certs ] ; then
	mkdir -p -m 700 "$ssl_cert_dir" \
		&& mv ~/certs/* "$ssl_cert_dir" \
		&& chmod 400 "$ssl_cert_dir"/*
	if [ $? -ne 0 ] ; then
		echo "ERROR: copying certificates had a problem."
		exit 1
	fi
fi

# Generate the certificate if necessary.
"$repo_dir/generate-certificate.sh" "$cert_name" "$self_sign_ssl_cert"
if [ $? -ne 0 ] ; then
	echo "ERROR: generate-certificate.sh had a problem."
	exit 1
fi

ask_to_proceed "server TLS certificate generation"


# MAIL ====================================================

# POSTFIX -------------------------------------------------
# Install postfix before procmail to keep changesets clean.
#
# /etc/postfix/main.cf = main configuration file, "postconf" edits this file
# /etc/postfix/master.cf = daemon service configuration file
#
# smtp_*  configures how postfix sends outgoing mail
# smtpd_*  configures how postfix receives incoming mail

echo ""
echo "When Postfix asks, say 'No configuration'."
echo -n "Press ENTER to continue..."
read -e

step="postfix"
step_header "$step"

apt-get -qq -y install postfix
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step"

# IP addresses of trusted SMTP clients.  IPv6 must be in brackets.
mynetworks="127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"
if [ -n "$ipv4" ] ; then
	mynetworks+=" $ipv4"
fi
if [ -n "$ipv6" ] ; then
	mynetworks+=" [$ipv6]"
fi

# NOTE: read debian configuration database by calling: debconf-show postfix
# -------------------------------------
debconf-set-selections <<EOPFDC
postfix postfix/root_address string $admin_name
postfix postfix/root_address seen true
# IP addresses of trusted SMTP clients. IPv6 must be in brackets.
postfix postfix/mynetworks string $mynetworks
postfix postfix/mynetworks seen true
# This server's name.
postfix postfix/mailname string $mail_server
postfix postfix/mailname seen true
postfix postfix/recipient_delim string +
postfix postfix/recipient_delim seen true
postfix postfix/main_mailer_type select Internet Site
postfix postfix/main_mailer_type seen true
postfix postfix/mailbox_limit string 0
postfix postfix/mailbox_limit seen true
postfix postfix/procmail boolean true
postfix postfix/procmail seen true
postfix postfix/protocols select all
postfix postfix/protocols seen true
postfix postfix/chattr boolean true
postfix postfix/chattr seen true
EOPFDC
# -------------------------------------
dpkg-reconfigure -fnoninteractive postfix

# Domains to serve mail for where recipients must have accounts on
# this machine or be listed in local_recipient_maps.
# Set this manually because it gets ignored by dpkg reconfigure.
postconf -e "mydestination = $host.$domain, $host, localhost.$domain, localhost$main_domain_comma"

postconf -e "myhostname = $mail_server"
if [ $? -ne 0 ] ; then
	echo "ERROR: postconf had a problem."
	exit 1
fi

postconf -e "virtual_alias_domains = $postfix_dir/virtual_alias_domains"
postconf -e "virtual_alias_maps = hash:$postfix_virtual_alias_map"
touch "$postfix_dir/virtual_alias_domains"
touch "$postfix_virtual_alias_map"
postmap "$postfix_virtual_alias_map"

# Use encrypted means of communication between servers when possible.
postconf -e "smtp_tls_security_level = may"
postconf -e "smtpd_tls_security_level = may"

# Prevent POODLE attacks.
postconf -e "smtpd_tls_mandatory_protocols = !SSLv2,!SSLv3"

postconf -e "smtpd_tls_cert_file=$ssl_cert_dir/$cert_name.crt"
postconf -e "smtpd_tls_key_file=$ssl_cert_dir/$cert_name.key"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination"

service postfix restart
if [ $? -ne 0 ] ; then
	echo "ERROR: $step restart had a problem."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# SPF / Sender Policy Framework ---------------------------
# https://help.ubuntu.com/community/Postfix/SPF
# http://en.wikipedia.org/wiki/Sender_Policy_Framework
# http://www.openspf.org/FAQ/Common_mistakes

step="postfix-policyd-spf-python"
step_header "$step"

apt-get -qq -y install postfix-policyd-spf-python
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

# -------------------------------------
cat >> "$postfix_dir/master.cf" <<EOPFM
policy-spf  unix  -       n       n       -       -       spawn
  user=nobody argv=/usr/bin/policyd-spf
EOPFM
# -------------------------------------

postconf -e "policy-spf_time_limit = 3600s"
"$repo_dir/append-postconf.sh" smtpd_recipient_restrictions "check_policy_service unix:private/policy-spf"

service postfix reload
if [ $? -ne 0 ] ; then
	echo "ERROR: $step posfix reload had a problem."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# DKIM / DomainKeys Identified Mail -----------------------
# /usr/share/doc/opendkim/examples/opendkim.conf.sample.gz
# man opendkim
# http://www.pmabox.com/blog/47-sign-emails-with-opendkim-postfix-in-ubuntu-1004-64x
# http://www.designaesthetic.com/2010/12/19/dkim-with-linodes-dns-manager/
# http://blog.tjitjing.com/index.php/2012/03/guide-to-install-opendkim-for-multiple-domains-with-postfix-and-debian.html

step="opendkim"
step_header "$step"

apt-get -qq -y install opendkim
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

mkdir -p "$dkim_dir/keys" \
	&& touch "$dkim_dir/Domain" \
	&& touch "$dkim_dir/KeyTable" \
	&& touch "$dkim_dir/SigningTable" \
	&& chown -R root:opendkim "$dkim_dir" \
	&& chmod -R 2750 "$dkim_dir"
if [ $? -ne 0 ] ; then
	echo "ERROR: setting up opendkim dir and files had a problem."
	exit 1
fi

domain_dkim_key_dir="$dkim_key_dir/$email_domain"
if [ ! -d "$domain_dkim_key_dir" ] ; then
	source "$repo_dir/include/dkim.sh"
fi

dns_skip_questions=y
source "$repo_dir/dns.sh"
if [ $? -ne 0 ] ; then
	echo "ERROR: dns.sh had a problem."
	exit 1
fi

echo "" >> "$dkim_conf"
echo "# MY CUSTOMIZATIONS" >> "$dkim_conf"
echo "" >> "$dkim_conf"
echo "Domain file:$dkim_dir/Domain" >> "$dkim_conf"
echo "KeyTable file:$dkim_dir/KeyTable" >> "$dkim_conf"
echo "SigningTable file:$dkim_dir/SigningTable" >> "$dkim_conf"
echo "ADSPNoSuchDomain yes" >> "$dkim_conf"
echo "" >> "$dkim_conf"
echo "# NOTE: these options changed between v2.0.2 and v2.5.2" >> "$dkim_conf"
echo "#ADSPDiscard yes" >> "$dkim_conf"
echo "ADSPAction discard" >> "$dkim_conf"

# The following settings must match in /etc/default/opendkim and
# /etc/postfix/main.cf and you must RESTART opendkim and postfix, otherwise:
# "warning: connect to Milter service inet:localhost:8891: Connection refused"
echo 'SOCKET="inet:8891@localhost"' >> "$dkim_default"

postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = inet:localhost:8891"
postconf -e "non_smtpd_milters = inet:localhost:8891"

# Restart was imperfect.  Stop and start to make sure things work.
service opendkim stop
service opendkim start
if [ $? -ne 0 ] ; then
	echo "ERROR: $step start had a problem."
	exit 1
fi

service postfix restart
if [ $? -ne 0 ] ; then
	echo "ERROR: $step posfix restart had a problem."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# PROCMAIL ------------------------------------------------
# Install postfix before procmail to keep changesets clean.

step="procmail"
step_header "$step"

apt-get -qq -y install procmail
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi

# -------------------------------------
cat > /etc/procmailrc <<EOPRC
HOME=$mail_dir/\${LOGNAME}

PMDIR=\${HOME}/.procmail
LOGFILE=\${HOME}/procmail.log

# Directory names need slashes on the ends to be treated as maildir format.
ORGMAIL=\${HOME}/Maildir/
DEFAULT=\${ORGMAIL}
SPAM_BOX=\${DEFAULT}.Spam/
DEV_NULL=/dev/null

INFINITY=9223372036854775807  # 64-bit
# INFINITY=2147483647         # 32-bit

# NOTE: these must be defined separately or recipies won't work.
SP=" "
TA="	"  # This is a tab.  Be careful.
WS=\$SP\$TA
EOPRC
# -------------------------------------

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# SPAMASSASSIN --------------------------------------------

step="spamassassin"
step_header "$step"

apt-get -qq -y install spamassassin
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step"

file=/etc/spamassassin/local.cf
# -------------------------------------
cat >> "$file" <<EOSA

#
# MY CUSTOMIZATIONS
#
# http://us.spamassassin.org/doc/Mail_SpamAssassin_Conf.html

# Rewrite existing headers; don't turn messages into attachments.
report_safe 0

# Put test results into both passing (ham) and failing (spam) emails.
add_header all Report _REPORT_

score UNWANTED_LANGUAGE_BODY 5.0
EOSA

file=/etc/default/spamassassin
# Enable the daemon.
sed -E "s/^ENABLED\s*=\s*0/ENABLED=1/g" -i "$file"
# Enable automatic rule updates.
sed -E "s/^CRON\s*=\s*0/CRON=1/g" -i "$file"

# Disable these because we're already doing it in Postfix.
file=/etc/spamassassin/init.pre
sed -E "s/^\s*(loadplugin Mail::SpamAssassin::Plugin::SPF)/#\1/g" -i "$file"
file=/etc/spamassassin/v312.pre
sed -E "s/^\s*(loadplugin Mail::SpamAssassin::Plugin::DKIM)/#\1/g" -i "$file"

# Enable TextCat so can use "ok_languages" preferences, otherwise get error:
# spamd[3]: config: failed to parse, now a plugin, skipping, in "user_prefs": ok_languages en
file=/etc/spamassassin/v310.pre
sed -E "s/^#\s*(loadplugin Mail::SpamAssassin::Plugin::TextCat)/\1/g" -i "$file"

sa-update && service spamassassin start
if [ $? -ne 0 ] ; then
	echo "ERROR: $step start had a problem."
	exit 1
fi

# NOTE: install-utilities.sh puts procmail recipe for spamassassin in place.

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# DOVECOT ------------------------------------------------
# Email clients authenticate to Dovecot.
# Dovecot turns that into a SASL authentication session with Postfix.
# NOTE: File and option names changed between 10.04 and 12.04.
# http://wiki2.dovecot.org/HowTo/PostfixAndDovecotSASL

step="dovecot"
step_header "$step"

apt-get -qq -y install dovecot-common dovecot-imapd
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

file=/etc/dovecot/conf.d/10-ssl.conf
sed -E "s@^#?ssl\s*=.*@ssl = required@g" -i "$file" \
	&& sed -E "s@^#?ssl_cert\s*=.*@ssl_cert = <$ssl_cert_dir/$cert_name.crt@g" -i "$file" \
	&& sed -E "s@^#?ssl_key\s*=.*@ssl_key = <$ssl_cert_dir/$cert_name.key@g" -i "$file" \
	&& sed -E "s@^#?ssl_cipher_list\s*=.*@ssl_cipher_list = TLSv1@g" -i "$file"
if [ $? -ne 0 ] ; then
	echo "ERROR: edit $step $file had a problem."
	exit 1
fi

file=/etc/dovecot/conf.d/10-mail.conf
sed -E "s@^#?mail_location\s*=.*@mail_location = maildir:$mail_dir/%u/Maildir@g" -i "$file"
if [ $? -ne 0 ] ; then
	echo "ERROR: edit $step $file had a problem."
	exit 1
fi

file=/etc/dovecot/conf.d/10-auth.conf
sed -E "s@^auth_mechanisms\s*=.*@auth_mechanisms = plain login@g" -i "$file"
if [ $? -ne 0 ] ; then
	echo "ERROR: edit $step $file had a problem."
	exit 1
fi

file="$repo_dir/install/dovecot.10-master.conf.diff"
cd /etc/dovecot/conf.d && git apply "$file"
if [ $? -ne 0 ] ; then
	echo "ERROR: $step applying $file had a problem."
	exit 1
fi

service dovecot restart
if [ $? -ne 0 ] ; then
	echo "ERROR: $step restart had a problem."
	exit 1
fi

postconf -e "smtpd_sasl_type = dovecot"
# NOTE: smtpd_sasl_path is relative to /var/spool/postfix
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_sasl_security_options = noanonymous"
postconf -e "broken_sasl_auth_clients = yes"

"$repo_dir/append-postconf.sh" smtpd_recipient_restrictions permit_sasl_authenticated
if [ $? -ne 0 ] ; then
	echo "ERROR: $step append postconf had a problem."
	exit 1
fi

# A map of local users permitted to send emails using <user>@$domain.
touch "$postfix_mydomain_map" \
	&& chmod 644 "$postfix_mydomain_map" \
	&& postmap "$postfix_mydomain_map"
if [ $? -ne 0 ] ; then
	echo "ERROR: $step creating mydomain map had a problem."
	exit 1
fi

# NOTE: smtpd_sasl_path is relative to /var/spool/postfix
# -------------------------------------
cat >> "$postfix_dir/master.cf" <<EOPFMSASL
submission inet n - - - - smtpd
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_sasl_security_options=noanonymous
  -o smtpd_sasl_local_domain=\$myhostname
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_login_maps=hash:$postfix_virtual_alias_map,hash:$postfix_mydomain_map
  -o smtpd_sender_restrictions=reject_sender_login_mismatch
  -o smtpd_recipient_restrictions=reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject
EOPFMSASL
if [ $? -ne 0 ] ; then
	echo "ERROR: $step editing postfix/master.cf had a problem."
	exit 1
fi

service postfix reload
if [ $? -ne 0 ] ; then
	echo "ERROR: postfix reload had a problem."
	exit 1
fi

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"


# MUTT ----------------------------------------------------

step="mutt"
step_header "$step"

apt-get -qq -y install mutt
if [ $? -ne 0 ] ; then
	echo "ERROR: $step install had a problem."
	exit 1
fi
cd /etc && git add --all && git commit -qam "$step"

# -------------------------------------
cat >> /etc/Muttrc <<EOMRC

#
# MY CUSTOMIZATIONS
#

set mbox_type = "Maildir";
set folder = "$mail_dir/\$USER/Maildir";
set spoolfile = "$mail_dir/\$USER/Maildir";
set record = "+.Sent Messages";
set postponed = "+.Drafts";
set trash = "+.Deleted Messages";

set sort = date;
set delete = yes;
set keep_flagged = yes;
set move = no;

set markers = no;

set fast_reply = yes;
set forward_format = "Fwd: %s";

set alias_file = "~/.mutt/alias";
source ~/.mutt/alias
EOMRC
# -------------------------------------

mkdir -m 750 /etc/skel/.mutt
touch /etc/skel/.mutt/alias

cd /etc && git add --all && git commit -qam "$step mods"

ask_to_proceed "$step"
