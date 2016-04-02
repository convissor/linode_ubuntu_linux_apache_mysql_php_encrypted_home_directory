if [[ $1 == "-h" || $1 == "--help" || $1 == "help" ]] ; then
	echo "Usage:  do not call this script directly"
	echo ""
	echo "Configures a network interface to use a static IP address."
	echo "NOTE: addresses are added, not replaced."
	echo ""
	echo "Author: Daniel Convissor <danielc@analysisandsolutions.com>"
	echo "License: http://www.analysisandsolutions.com/software/license.htm"
	echo "http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory"
	exit 1
fi

if [ -z "$new_ip" ] ; then
	echo "ERROR: the '\$new_ip' was not set"
	exit 1
fi

set +e
grep -q "$new_ip" "$interfaces_file"
if [ $? -eq 0 ] ; then
	set -e
	echo "NOTE: '$new_ip' was already configured."
	return
fi
set -e


if [[ "$new_ip" == *":"* ]] ; then
	inet=inet6
	netmask=$ipv6_netmask
	gateway=$ipv6_gateway
	dns=$ipv6_dns
else
	inet=inet
	netmask=$ipv4_netmask
	gateway=$ipv4_gateway
	dns=$ipv4_dns
fi


echo "" >> /etc/hosts
echo "$new_ip  $host.$domain $host $main_domain" >> /etc/hosts


initial_declaration="iface $network_interface $inet dhcp"
set +e
grep -q "$initial_declaration" "$interfaces_file"
if [ $? -eq 0 ] ; then
	set -e
	new_iface=$network_interface

	# Get rid of DHCP for this interface.
	sed "s/$initial_declaration//g" -i "$interfaces_file"
else
	auto=`grep "auto $network_interface" "$interfaces_file"`
	set -e
	last_iface=${auto##*:}
	if [ "$last_iface" == "auto $network_interface" ] ; then
		count=1
	else
		count=$((last_iface + 1))
	fi
	new_iface="$network_interface:$count"

	sed "s/$auto/$auto $new_iface/g" -i "$interfaces_file"
fi

# NOTE: putting dns-nameservers here is new in 12.04 / Precise.
# -------------------------------------
cat >> "$interfaces_file" <<EOIF
iface $new_iface $inet static
 address $new_ip
 netmask $netmask
 gateway $gateway
 dns-nameservers $dns
EOIF
# -------------------------------------


# The other commands shown below here have problems.
/etc/init.d/networking stop && start networking

# /etc/init.d/networking restart
# Running /etc/init.d/networking restart is deprecated because it may
# not enable again some interfaces

# service networking restart
# stop: Unknown instance:

# service networking stop
# stop: Unknown instance:

# /etc/init.d/networking start
# Rather than invoking init scripts through /etc/init.d, use the service(8)
# utility, e.g. service networking start
# Since the script you are attempting to invoke has been converted to an
# Upstart job, you may also use the start(8) utility, e.g. start networking
