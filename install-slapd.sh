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
sudo cp ${tempdir}/ldapaddperson /usr/sbin/ || { echo "Could not copy ${tempdir}/ldapaddperson to /usr/sbin/.  Aborting..."; exit 12; }
if [ `grep "s|<mail>|\$_MAIL|g" /usr/share/ldapscripts/runtime | wc -l` -eq 0 ]; then
	cat /usr/share/ldapscripts/runtime | sed "s/s|<user>|\$_USER|g/s|<user>|\$_USER|g\ns|<gn>|\$_GN|g\ns|<sn>|\$_SN|g\ns|<mail>|\$_MAIL|g/" > ${tempdir}/runtime || { echo "Could not copy modified version of /usr/share/ldapscripts/runtime to ${tempdir}/runtime.  Aborting..."; exit 13; }
	sudo cp ${tempdir}/runtime /usr/share/ldapscripts/ || { echo "Could not copy ${tempdir}/runtime to /usr/share/ldapscripts/.  Aborting..."; exit 14; }
fi
ldapscripts_sed="s/^_findentry.*$/_findentry \\\"\\\$USUFFIX,\\\$SUFFIX\\\" \\\"(\&(objectClass=inetOrgPerson)(uid=\\\$1))\\\"/"
cat /usr/sbin/ldapsetpasswd | sed "$ldapscripts_sed" | sed "s/ldapsetpasswd/ldapsetpersonpasswd/" | sed "s/POSIX user/inetOrgPerson/" > ${tempdir}/ldapsetpersonpasswd || { echo "Could not create ${tempdir}/ldapsetpersonpasswd by modifying /usr/sbin/ldapsetpasswd.  Aborting..."; exit 15; }
sudo cp ${tempdir}/ldapsetpersonpasswd /usr/sbin/ || { echo "Could not copy ${tempdir}/ldapsetpersonpasswd to /usr/sbin/.  Aborting..."; exit 16; }
cat /usr/sbin/ldapmodifyuser | sed "$ldapscripts_sed" | sed "s/ldapmodifyuser/ldapmodifyperson/" | sed "s/POSIX user/inetOrgPerson/" > ${tempdir}/ldapmodifyperson || { echo "Could not create ${tempdir}/ldapmodifyperson by modifying /usr/sbin/ldapmodifyuser.  Aborting..."; exit 17; }
sudo cp ${tempdir}/ldapmodifyperson /usr/sbin/ || { echo "Could not copy ${tempdir}/ldapmodifyperson to /usr/sbin/.  Aborting..."; exit 18; }
cat /usr/sbin/ldapdeleteuser | sed "$ldapscripts_sed" | sed "s/ldapdeleteuser/ldapdeleteperson/" | sed "s/POSIX user/inetOrgPerson/" > ${tempdir}/ldapdeleteperson || { echo "Could not create ${tempdir}/ldapdeleteperson by modifying /usr/sbin/ldapdeleteuser.  Aborting..."; exit 19; }
sudo cp ${tempdir}/ldapdeleteperson /usr/sbin/ || { echo "Could not copy ${tempdir}/ldapdeleteperson to /usr/sbin/.  Aborting..."; exit 20; }
sudo chmod a+x /usr/sbin/ldap* || { echo "Could not give global execute privileges to all ldapscripts scripts.  Aborting..."; exit 21; }


echo -e "\n\n[`date +%H:%M:%S`] LDAP Server installed successfully.  Goodbye.\n"
