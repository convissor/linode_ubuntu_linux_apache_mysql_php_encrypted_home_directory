#! /bin/bash

if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  new-domain.sh"
	echo ""
	echo "Configures the system to handle another domain."
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi


# CHECK THAT THE REPO IS CLEAN ============================

cd /etc
if [ -n "$(git status --porcelain)" ] ; then
	echo "Uncommitted changes exist in /etc."
	echo "Commit them first then call this script again."
	exit 1
fi


# GET SETTINGS ============================================

if [ -z "$repo_dir" ] ; then
	repo_dir="$(cd "$(dirname "$0")" && pwd)"
	source "$repo_dir/settings"
	source "$repo_dir/paths"
fi

user="$regular_user"

if [ "$1" == "settings" ] ; then
	if [ $is_main_server_for_domain -eq 1 ] ; then
		cert_name=$domain
		email_domain=$domain
	else
		cert_name=$host.$domain
		email_domain=$host.$domain
	fi
else
	echo -n "Username for the account that will administer the web site [$user]: "
	read -e
	if [ -n "$REPLY" ] ; then
		user="$REPLY"
	fi

	loop_again=1
	while [ $loop_again -eq 1 ] ; do
		echo -n "Web server's domain name (do NOT include 'www.'): "
		read -e
		if [ -z "$REPLY" ] ; then
			echo "ERROR: Get your head out of your shell, turtle! Enter the required data..."
			loop_again=1
		else
			loop_again=0
			domain=$REPLY
			cert_name=$domain
			email_domain=$domain
		fi
	done

	does_web_server_need_ssl=1
	echo -n "Does web server need SSL? (1 | 0) [$does_web_server_need_ssl]: "
	read -e
	if [ -n "$REPLY" ] ; then
		does_web_server_need_ssl=$REPLY
	fi

	if [[ ! -f "$ssl_cert_dir/$cert_name.key"
			&& $does_web_server_need_ssl -eq 1 ]]
	then
		self_sign_ssl_cert=0
		echo -n "Self sign the SSL certficate? (1 | 0) [$self_sign_ssl_cert]: "
		read -e
		if [ -n "$REPLY" ] ; then
			self_sign_ssl_cert=$REPLY
		fi
	fi

	echo -n "Does this domain need a database? [Y|n]: "
	read -e
	if [[ -z "$REPLY" || "$REPLY" == y || "$REPLY" == Y ]] ; then
		needs_db=1
	else
		needs_db=0
	fi

	echo -n "IPv4 address [$ipv4]: "
	read -e
	new_ip="$REPLY"
	if [[ -n "$new_ip" && "$new_ip" != "$ipv4" ]] ; then
		source "$repo_dir/include/hardcode-ip.sh"
		ipv4=$new_ip
	fi

	echo -n "IPv6 address [$ipv6]: "
	read -e
	new_ip="$REPLY"
	if [[ -n "$new_ip" && "$new_ip" != "$ipv6" ]] ; then
		source "$repo_dir/include/hardcode-ip.sh"
		ipv6=$new_ip
	fi
fi


web_server_name=www.$domain
echo "--------------------------------------------------------------"
echo "One full domain name must be the main 'brand' for the website."
echo "The other domain name will redirect to the main one."
echo "  1) alias = $domain  ->  main = $web_server_name"
echo "  2) alias = $web_server_name  ->  main = $domain"
echo -n "Which option do you want? (1 | 2) [1]: "
read -e
if [ "$REPLY" == 2 ] ; then
	web_server_name=$domain
fi

if [ ${web_server_name:0:4} == "www." ] ; then
	server_alias=$domain
else
	server_alias=www.$domain
fi

if [ "$1" == "settings" ] ; then
	server_alias+=" localhost"
fi

echo "The web server's main domain is $web_server_name."
echo -n "List other domains that will forward to the main domain (space separated) [$server_alias]: "
read -e
if [ -n "$REPLY" ] ; then
	server_alias=$REPLY
fi


group=${web_server_name//./-}
user_connection_info_dir="$connection_info_dir/$user"
user_connection_info_file="$user_connection_info_dir/$web_server_name.txt"
server_web_dir="$web_dir/$web_server_name"

if [ -d "$server_web_dir" ] ; then
	echo "This server had already been set up."
	exit 1
fi


# USER ====================================================

export NEW_USERS_DOMAIN=$email_domain

if [ ! -d "/home/$user" ] ; then
	echo ""
	echo "About to create a regular user ($user) to be the website's administrator..."
	echo -n "Person's full name:"
	read -e

	adduser --encrypt-home "$user" --gecos "$REPLY,,,,umask=0007"
	if [ $? -ne 0 ] ; then
		echo "ERROR: adduser $user had a problem."
		exit 1
	fi
fi

echo "Creating user account the web server will run as for this server..."

if (grep -qE "^$group:" /etc/passwd) ; then
	echo -n "WARNING: user '$group' already exists. Is this okay? [N|y]: "
	read -e
	if [[ "$REPLY" == y || "$REPLY" == Y ]] ; then
		echo "Okay. We'll use that user."
	else
		echo "ERROR: user '$group' already exists."
		exit 1
	fi
else
	adduser --no-create-home --disabled-login --shell /bin/false \
		--gecos "$web_server_name http user,,,,umask=0007" $group
	if [ $? -ne 0 ] ; then
		echo "ERROR: adduser $group had a problem."
		exit 1
	fi
fi

adduser "$user" $group
if [ $? -ne 0 ] ; then
	echo "ERROR: adduser $user to $group had a problem."
	exit 1
fi

ask_to_proceed "new domain user additions"


# MAIL ====================================================

domain_dkim_key_dir="$dkim_key_dir/$email_domain"

if [ ! -d "$domain_dkim_key_dir" ] ; then
	# DKIM ---------------------------------------

	source "$repo_dir/include/dkim.sh"

	service opendkim restart
	if [ $? -ne 0 ] ; then
		echo "ERROR: opendkim restart had a problem."
		exit 1
	fi


	# POSTFIX ------------------------------------

	if [ "$email_domain" != "$mail_server" ] ; then
		echo "$email_domain" >> "$postfix_dir/virtual_alias_domains" \
			&& echo "" >> "$postfix_virtual_alias_map" \
			&& echo "postmaster@$email_domain postmaster" >> "$postfix_virtual_alias_map" \
			&& echo "$user@$email_domain $user" >> "$postfix_virtual_alias_map" \
			&& postmap "$postfix_virtual_alias_map"
		if [ $? -ne 0 ] ; then
			echo "ERROR: virtual alias mapping had a problem."
			exit 1
		fi

		service postfix reload
		if [ $? -ne 0 ] ; then
			echo "ERROR: postfix reload had a problem."
			exit 1
		fi
	fi

	ask_to_proceed "new domain mail configuration"
fi


# DNS INFORMATION =========================================

# Only do when calling for additional domains.
# Initial server installation already did this step.
if [[ "$1" != "settings" ]] ; then
	dns_skip_questions=y
	source "$repo_dir/dns.sh"
	if [ $? -ne 0 ] ; then
		echo "ERROR: dns.sh had a problem."
		exit 1
	fi
fi

echo "-----------------------------------------------------"
echo "If this is the primary/only domain using $ipv4, set up Reverse DNS."
echo "Linode Manager | Linodes | machine | Remote Access ..."
echo "Public IP's | Reverse DNS"
echo "$ipv4 -> $email_domain"
echo "-----------------------------------------------------"


# MYSQL ===================================================

if [ $needs_db -eq 1 ] ; then
	db=${web_server_name//[.-]/_}
	if [ ${#db} -gt 64 ] ; then
		# Strip TLD.  Must do first, otherwise removes domain name.
		db=${db%_*}
		if [ ${#db} -gt 64 ] ; then
			if [ "${db:0:4}" = "www_" ] ; then
				# Strip standard sub-domain.
				# Don't do more math; domain components are < 64 chars.
				db=${db#*_}
			else
				# Sub-domain other than "www", probably significant, leave it.
				db=${db:0:64}
			fi
		fi
	fi

	regular_db_user=$db
	if [ ${#regular_db_user} -gt 16 ] ; then
		regular_db_user=${regular_db_user:0:16}
	fi
	# Note: gpw is my Generate Password utility.
	regular_db_pw=`gpw`

	admin_db_user="${regular_db_user:0:12}_adm"
	admin_db_pw=`gpw`
	admin_user_override=0

	# Place this in a loop in case the user mistypes the password
	# or other resolvable problems are encountered.
	loop_again=1
	while [ $loop_again -eq 1 ] ; do
		echo ""
		echo "The next step will ask for your existing MySQL root password..."
		# -------------------------------------
		result=`mysql --skip-column-names -u root -p mysql <<EOMY
CALL new_domain("$db", "$admin_db_user", "$admin_db_pw", "$regular_db_user", "$regular_db_pw", "$admin_user_override");
EOMY`
		# -------------------------------------
		if [ $? -ne 0 ] ; then
			loop_again=1
			echo ""
			echo "ERROR: MySQL choked."
			echo -n "Hit ENTER to try again or CTRL-C to stop execution..."
			read -e
		elif [ -n "$result" ] ; then
			loop_again=1
			echo ""
			echo "ERROR: $result"
			# Bash substring regular expression matching.
			if [[ "$result" =~ ^DATABASE ]] ; then
				echo -n "Pick a new database name [$db]: "
				read db
			elif [[ "$result" =~ ^REGULAR ]] ; then
				echo -n "Pick a new name for the domain's lower-privileged database user [$regular_db_user]: "
				read regular_db_user
			elif [[ "$result" =~ ^ADMIN ]] ; then
				echo -n "Should $admin_db_user also have access to $db? [N|y]: "
				read -e
				if [[ "$REPLY" == y || "$REPLY" == Y ]] ; then
					admin_user_override=1
				else
					admin_user_override=0
					echo -n "Pick a new name for the domain's admin database user [$admin_db_user]: "
					read admin_db_user
				fi
			else
				echo "ERROR: unexpected result"
				exit 1
			fi
		else
			loop_again=0
		fi
	done

	touch "$user_connection_info_file" \
		&& chmod 660 "$user_connection_info_file"
	if [ $? -ne 0 ] ; then
		echo "ERROR: touching connection info file had a problem."
		exit 1
	fi

	# -------------------------------------
	cat >> "$user_connection_info_file" <<EOMY
-----------------------------
Database: $db

Admin user: $admin_db_user
Admin password: $admin_db_pw
Command to connect: mysql -u $admin_db_user -p $db

Regular user: $regular_db_user
Regular password: $regular_db_pw
EOMY
	# -------------------------------------
	if [ $? -ne 0 ] ; then
		echo "ERROR: writing db connection information had a problem."
		exit 1
	fi

	ask_to_proceed "new domain mysql database and user creation"
fi


# TLS CERTIFICATE =========================================

# Only do when calling for additional domains.
# Initial server installation already did this step.
if [[ "$1" != "settings" && $does_web_server_need_ssl -eq 1 ]] ; then
	"$repo_dir/generate-certificate.sh" "$cert_name" "$self_sign_ssl_cert"
	if [ $? -ne 0 ] ; then
		echo "ERROR: generate-certificate.sh had a problem."
		exit 1
	fi

	ask_to_proceed "new domain certificate generation"
fi


# APACHE ==================================================

server_document_root="$server_web_dir/public_html"
server_web_log_dir="$web_log_dir/$web_server_name"

# Have directories and configuration files be owned by the site's admin
# rather than the user Apache CGI runs as.  Reduces problems of hijacking
# by preventing scripts from editing or calling chmod on them.
mkdir -p "$server_document_root" \
	&& chmod -R 2770 "$server_web_dir" \
	&& touch "$server_web_dir/php_errors.log" \
	&& echo "error_log = \"$server_web_dir/php_errors.log\"" \
		> "$server_document_root/.user.ini" \
	&& echo "<?php echo 'Welcome to $web_server_name!';" \
		> "$server_document_root/index.php" \
	&& touch "$server_document_root/.htaccess" \
	&& touch "$server_document_root/robots.txt" \
	&& touch "$server_document_root/favicon.ico" \
	&& chown -R $user:$group "$server_web_dir" \
	&& chmod 660 "$server_document_root"/* "$server_web_dir/php_errors.log" \
	&& chmod 640 "$server_document_root"/.[a-z]*
if [ $? -ne 0 ] ; then
	echo "ERROR: setting up document dir had a problem."
	exit 1
fi

cd "$server_web_dir" \
	&& git init --shared=group \
	&& git config receive.denyCurrentBranch ignore \
	&& chmod 770 .git \
	&& chmod -R o=- .git \
	&& cp -R "$repo_dir/install/backups" \
		"$repo_dir/install/utilities" . \
	&& chmod 770 backups utilities utilities/* \
	&& chmod 660 backups/.[a-z]* utilities/.[a-z]* \
	&& ln -s "../../utilities/post-update" \
		"$server_web_dir/.git/hooks/post-update" \
	&& ln -s "../../utilities/pre-receive" \
		"$server_web_dir/.git/hooks/pre-receive" \
	&& echo "php_errors.log" > .gitignore \
	&& git add .gitignore utilities public_html \
	&& git commit -am 'Website skeleton created by new-domain.sh.' \
	&& chown -R $user:$group .gitignore .git utilities backups
if [ $? -ne 0 ] ; then
	echo "ERROR: establishing git repository had a problem."
	exit 1
fi

mkdir -p "$server_web_log_dir" \
	&& chown -R root:$group "$server_web_log_dir" \
	&& chmod -R 2750 "$server_web_log_dir"
if [ $? -ne 0 ] ; then
	echo "ERROR: setting up log dir had a problem."
	exit 1
fi

# CHECK create log rotate

# -------------------------------------
cat > /etc/apache2/sites-available/$web_server_name-inc <<EOINC
ServerName $web_server_name
ServerAlias $server_alias

# Set SERVER_NAME to ServerName rather than HTTP_HOST sent by the browser.
UseCanonicalName On

ServerAdmin root@$email_domain
AssignUserId $group $group

ErrorLog $server_web_log_dir/error.log
CustomLog $server_web_log_dir/access.log combined

DocumentRoot $server_document_root
<Directory $server_document_root>
	AllowOverride All
	Options All
	Allow from all

	DirectoryIndex index.php index.html index.htm
</Directory>
EOINC
# -------------------------------------
if [ $? -ne 0 ] ; then
	echo "ERROR: creating apache include file had a problem."
	exit 1
fi

server_escaped=${web_server_name//./\\.}

# -------------------------------------
cat > /etc/apache2/sites-available/$web_server_name <<EOVHSTD
<VirtualHost *:80>
	Include sites-available/$web_server_name-inc

	# Ensure everyone uses the main domain name.
	RewriteEngine on
	RewriteCond %{HTTP_HOST} !^$server_escaped\$ [NC]
	RewriteCond %{HTTP_HOST} !^\$
	RewriteRule ^/(.*) http://%{SERVER_NAME}/\$1 [R=301,L]
</VirtualHost>
EOVHSTD
# -------------------------------------
if [ $? -ne 0 ] ; then
	echo "ERROR: creating apache virtual host file had a problem."
	exit 1
fi

if [ $does_web_server_need_ssl -eq 1 ] ; then
	if [ -f $ssl_cert_dir/$cert_name.crt ] ; then
		c=""
	else
		# Prevent "SSLCertificateFile: file does not exist or is empty"
		c="#"
		echo ""
		echo "WARNING: The SSL certificate is not in place yet."
		echo "Please install it at $ssl_cert_dir/$cert_name.crt"
		echo "Until then, <VirtualHost *:443> in"
		echo "/etc/apache2/sites-available/$web_server_name"
		echo "has been commented out.  Once you install the certificate,"
		echo "uncomment that block and call 'service apache2 reload'."
		echo -n "Press ENTER to continue..."
		read -e
	fi
	# -------------------------------------
	cat >> /etc/apache2/sites-available/$web_server_name <<EOVHSSL
$c<VirtualHost *:443>
$c	Include sites-available/$web_server_name-inc
$c
$c	# Ensure everyone uses the main domain name.
$c	RewriteEngine on
$c	RewriteCond %{HTTP_HOST} !^$server_escaped\$ [NC]
$c	RewriteCond %{HTTP_HOST} !^\$
$c	RewriteRule ^/(.*) https://%{SERVER_NAME}/\$1 [R=301,L]
$c
$c	SSLEngine On
$c	SSLCertificateFile $ssl_cert_dir/$cert_name.crt
$c	SSLCertificateKeyFile $ssl_cert_dir/$cert_name.key
$c
$c	SSLCertificateChainFile /etc/ssl/localcerts/startssl.sub.class1.server.ca.pem
$c	SSLCACertificateFile /etc/ssl/localcerts/startssl.ca.pem
$c</VirtualHost>
EOVHSSL
# -------------------------------------
fi

a2ensite $web_server_name
if [ $? -ne 0 ] ; then
	echo "ERROR: a2ensite had a problem."
	exit 1
fi

service apache2 reload
if [ $? -ne 0 ] ; then
	echo "ERROR: apache reload had a problem."
	exit 1
fi

# -------------------------------------
cat >> "$user_connection_info_file" <<EOMY
-----------------------------
Website document root: "$server_document_root"
Website log directory: "$server_web_log_dir"
Website include directory, if you want: "$server_web_dir"

php.ini customizations: "$server_document_root/.user.ini"
PHP error log: "$server_web_dir/php_errors.log"

Your website has been pre-configured to use Git.  Obtain the initial files
by calling:

    git clone ssh://$user@$domain$server_web_dir
    cd $server_web_dir
    # "prod" stands for "production" (ie: the web server the public sees).
    git remote rename origin prod

Now the really cool part is that we've set up the repository on our server
in a way that any changes you push to it are automatically deployed to the
live website.  This means that when you're ready to publish the changes that
have been committed to the local repository on your development box, all you
need to do to make them public is issue the following command from inside
that local repository:

    git push prod master

The deployment process even includes the ability to automatically run a
script on the server before the website's main files get updated and then
another script after the main files have been updated.  Those scripts
reside in the "utilities" directory.

We suggest running the following commands to create links that will make your
life easier:

    ln -s "$server_document_root" ~/$web_server_name
    ln -s "$server_web_log_dir" ~/$web_server_name-logs
EOMY
# -------------------------------------
if [ $? -ne 0 ] ; then
	echo "ERROR: writing apache connection information had a problem."
	exit 1
fi

ask_to_proceed "new domain apache creation"


# TELL THE USER WHERE STUFF IS ============================

# -------------------------------------
sendmail "$user" <<EONOTIFY
To: $user
From: root
Subject: website connection information

Hi:

Your account for $web_server_name has been created.

The database connection information and website directory locations can be
obtained by SSH'ing in to the server and issuing the following command:
    less "~/connection-info/$web_server_name.txt"

Now, this is VERY important.  Your home directory is encrypted for your
protection.  When you log in for the first time, make sure to run the
following command:
	ecryptfs-unwrap-passphrase ~/.ecryptfs/wrapped-passphrase
Then copy the result and store it in a safe place.  That passphrase is
the only way to decrypt your data in case something goes wrong.

Sincerely,

--Dan
EONOTIFY
# -------------------------------------
if [ $? -ne 0 ] ; then
	echo "ERROR: sending connection information had a problem."
	exit 1
fi

ask_to_proceed "new domain user notification"


# SAVE CHANGES ============================================

cd /etc && git add --all && commit_if_needed "new-domain.sh: $domain $user"

ask_to_proceed "all new domain steps are"
