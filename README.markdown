= Linode Ubuntu Linux Apache MySQL PHP Installation and Administration Utilities=

===  Security  ===
* Encrypted home directories
* Login via SSH authorized keys only
* Creates admin user, disables `root` login
* PAM Password QC
* Fail2ban
* Iptables Persistent
* Unattended Upgrades automatically updates all software.  Hack the program
  to use my `linode_reboot` script so the server reboot actually works
  (because Linodes can only be rebooted via the Linode Manager or API)
  and gives logged in users a 10 minute warning when reboots happen.
  (Unattended Upgrades version 0.76 just reboots withot warning.)

===  Web  ===
* MySQL
* Apache mpm-itk, with each site having its own user and group
* Memcache
* PHP built from source

===  Mail  ===
* Postfix with SASL authentication
* Dovecot IMAP server over SSL
* Sender Policy Framework (SPF)
* Domain Keys Identified Mail (DKIM)
* Procmail
* SpamAssassin
* Mutt

===  Misc  ===
* Puts `/etc` under Git version control and commits changes at each step
* Git, Mercurial, Subversion, CVS
* SQLite 2 and 3
* Network Time Protocol (NTP)

===  Administration Scripts Written in Bash  ===
* `linode_api`: command line interface for the Linode API
* `linode_reboot`: a stand-in for `shutdown -r` because Linodes can only
  be reboted via the Linode Manager / API.
* `dns.sh`: configures Linode's DNS servers using Linode's API
* `php-build.sh`: builds and installs PHP from the latest Git sources
* `install-utilities.sh`: puts our scripts into their places
* `write-alias.sh`: adds an entry to `/etc/aliases` and calls `newaliases`
* `generate-certificate.sh`: produces SSL/TLS certficates, keys and requests
* `append-postconf.sh`: appends a value to a Postfix configuration key
* `gpw`: generates strong, though not user memorable, passwords
* `adduser.local`: generates an SSH authorized key, sets up skeleton files
  and directories, configures the mail server and sends IMAP configuration
  instructions to the user.
* `new-domain.sh`:
	+ IPv4 and IPv6 put into network configuration, if needed
	+ TLS/SSL certificate creation
	+ Database creation
	+ User creation
	+ Web server virtual host
	+ Web server document root creation and initialization of a Git
     repository that has my Git Push Deploy capability built in.
	+ DKIM setup
	+ DNS setup, including DKIM and SPF data
	+ Postfix virtual alias


==  To Do  ==
* Investigate what of this can be done using Puppet or Chef
* Use `other_vhosts_access.log` as the log for each host and split the
  incoming entries on the fly instead of using `split-logfile`.
* Delete old spam and deleted messages.
* Log rotation (Apache virtual hosts, Procmail, etc).


==  Installation  ==
* In the Linode Manager:
	+ Create a new linode.
	+ Pick "Ubuntu 12.04 LTS 64bit" as the distribution.
	+ This process is known to work with the "3.2.X-x86_64" kernels.
	+ Boot it.

* On your local box:
<pre>
git clone git://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory.git
cd linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory
git checkout -b my12.04 12.04

# Go through ALL of the settings.
vim settings

cd ~/.ssh
ssh-keygen -t rsa -C <you>@<domain> -f <key name> \
chmod 600 <key name>*
cd -
cp ~/.ssh/<key name>.pub install/authorized_keys

git commit -am 'My settings.'

cd ..
scp -r linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory \
	root@<your linode's IP>:.
ssh root@<your linode's IP>
* Now, on the server, do the following:
cd linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory
~/certs

# This step will reboot the server.
./1st-step_timezone_iptables-persistent_unattended-upgrade_static-ip-address.sh
</pre>

* From your local box:
<pre>
ssh root@<your linode's IP>
</pre>

* Finally, on the server, call:
<pre>
cd linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory
./2nd-step_run-sub-scripts.sh
</pre>
