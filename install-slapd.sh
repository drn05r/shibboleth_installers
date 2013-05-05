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
echo "[`date +%H:%M:%S`] Installing and configuring prerequisites";
sudo apt-get update || { echo "Could not update APT package listing.  Aborting..."; exit 2; }
sudo apt-get install -y debconf-utils ldap-utils || { echo "Could not install prerequisites with apt-get.  Aborting..."; exit 3; }
source $basedir/config.sh $tempdir
sudo su -c "echo slapd slapd/internal/adminpw password `echo "'"``echo ${ldap_admin_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo slapd slapd/password1 password `echo "'"``echo ${ldap_admin_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo slapd slapd/password2 password `echo "'"``echo ${ldap_admin_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo slapd shared/organization string `echo "'"``echo ${ldap_server}``echo "'"` | debconf-set-selections"
sudo su -c "echo slapd slapd/domain string `echo "'"``echo ${ldap_server}``echo "'"` | debconf-set-selections"


echo "[`date +%H:%M:%S`] Installing LDAP server";
sudo env DEBIAN_FRONTEND=noninteractive apt-get -q -y install slapd || { echo "Could not install LDAP server using apt-get. Aborting ..."; exit 4; }
echo "[`date +%H:%M:%S`] Restarting LDAP server"
sudo service slapd restart || { echo "Could not restart LDAP server. Aborting..."; exit 5; }
echo "[`date +%H:%M:%S`] Adding LDAP Organizational Units"
sudo ldapadd -x -D ${ldap_bind_dn} -f ${tempdir}/organizational_units.ldif -w "${ldap_admin_password}" || { echo "Could not add organizational units using ldapadd.  Aborting..."; exit 6; }


echo "[`date +%H:%M:%S`] Installing LDAP scripts"
sudo apt-get install -y ldapscripts || { echo "Could not install ldapscripts package using apt-get. Aborting ..."; exit 7; }
sudo cp ${tempdir}/ldapscripts.conf /etc/ldapscripts/ || { echo "Could not copy ${tempdir}/ldapscripts.conf to /etc/ldapscripts/.  Aborting..."; exit 8; }
sudo cp ${tempdir}/runtime.debian /usr/share/ldapscripts/ || { echo "Could not copy ${tempdir}/runtime.debian to /usr/share/ldapscripts/.  Aborting..."; exit 9; }
sudo sh -c "echo -n '${ldap_admin_password}' > /etc/ldapscripts/ldapscripts.passwd" || { echo "Could not write password out to /etc/ldapscripts/ldapscripts.passwd.  Aborting..."; exit 10; }
sudo chmod 400 /etc/ldapscripts/ldapscripts.passwd || { echo "Could not set permissions for /etc/ldapscripts/ldapscripts.passwd to 400.  Aborting..."; exit 11; }
echo -e "\n\n[`date +%H:%M:%S`] LDAP Server installed successfully.  Goodbye.\n"
