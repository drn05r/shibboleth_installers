#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$(mktemp -d /tmp/shib-idp_uninstaller.XXXXXXXXXX)
source ${basedir}/settings.sh
echo "+------------------------------------------+"
echo "| Shibboleth Identity Provider Uninstaller |"
echo "+------------------------------------------+"
echo ""
sudo rm -r ${shib_idp_home}
sudo rm -r /usr/local/src/shibboleth-identityprovider-${shib_idp_version}
sudo rm -r /etc/tomcat6/Catalina/localhost/*
sudo rm /etc/profile.d/idp_home
sudo apt-get -y purge tomcat6
sudo rm /etc/apache2/sites-enabled/${server_for_ssl}
sudo rm /etc/apache2/sites-available/${server_for_ssl}
sudo cat /etc/apache2/ports.conf | sed "s/Listen 8443//" > ${tempdir}/ports.conf
sudo cp ${tempdir}/ports.conf /etc/apache2/
sudo service apache2 restart
mysql -u root -p${mysql_root_password} -e "DROP DATABASE shibboleth; DROP USER 'shibboleth'@'localhost'; FLUSH PRIVILEGES;"
echo -e "\n\nShibboleth Identity Provider uninstalled successfully.  Goodbye.\n"
