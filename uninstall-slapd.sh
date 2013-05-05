#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$(mktemp -d /tmp/slapd_uninstaller.XXXXXXXXXX)
source ${basedir}/settings.sh
echo "+-------------------------+"
echo "| LDAP Server Uninstaller |"
echo "+-------------------------+"
echo ""
sudo apt-get purge slapd
sudo rm -r /etc/ldap
sudo rm -r /var/lib/ldap 
echo -e "\n\nShibboleth Identity Provider uninstalled successfully.  Goodbye.\n"

