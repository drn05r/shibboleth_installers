#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$(mktemp -d /tmp/slapd_installer.XXXXXXXXXX)
if [ ! -f "${basedir}/settings.sh" ]; then
        echo "Cannot find ${basedir}/settings.sh.  Aborting..."
        exit 1;
fi
source $basedir/settings.sh
echo "+-----------------------+"
echo "| LDAP Server Installer |"
echo "+-----------------------+"
echo ""
echo "Installing and configuring LDAP server";
sudo apt-get update  || { echo "Failed to update APT package listing. Aborting..."; exit 2; }
sudo apt-get install -y debconf-utils ldap-utils
source $basedir/config.sh $tempdir

sudo su -c "echo slapd slapd/internal/adminpw password `echo "'"``echo ${ldap_admin_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo slapd slapd/password1 password `echo "'"``echo ${ldap_admin_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo slapd slapd/password2 password `echo "'"``echo ${ldap_admin_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo slapd shared/organization string `echo "'"``echo ${ldap_server}``echo "'"` | debconf-set-selections"
sudo su -c "echo slapd slapd/domain string `echo "'"``echo ${ldap_server}``echo "'"` | debconf-set-selections"
sudo env DEBIAN_FRONTEND=noninteractive apt-get -q -y install slapd || { echo "Failed to install LDAP APT packages. Aborting ..."; exit 3; }
echo "Restarting LDAP server"
sudo service slapd restart || { echo "Could not restart LDAP server. Aborting..."; exit 4; }
echo "Adding LDAP Organizational Units"
sudo ldapadd -x -D ${ldap_bind_dn} -f ${tempdir}/organizational_units.ldif -w "${ldap_admin_password}"
#echo "Configuring LDAP authentication"
#sudo apt-get install libnss-ldap
#sudo dpkg-reconfigure ldap-auth-config
#sudo auth-client-config -t nss -p lac_ldap
#sudo pam-auth-update
echo "Installing LDAP scripts"
sudo apt-get install -y ldapscripts
sudo cp ${tempdir}/ldapscripts.conf /etc/ldapscripts/
sudo cp ${tempdir}/runtime.debian /usr/share/ldapscripts/
sudo sh -c "echo -n '${ldap_admin_password}' > /etc/ldapscripts/ldapscripts.passwd"
sudo chmod 400 /etc/ldapscripts/ldapscripts.passwd
echo -e "\n\nLDAP Server installed successfully.  Goodbye.\n"
