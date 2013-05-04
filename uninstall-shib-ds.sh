#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$(mktemp -d /tmp/shib-ds_uninstaller.XXXXXXXXXX)
source ${basedir}/settings.sh
echo "+------------------------------------------+"
echo "| Shibboleth Discovery Service Uninstaller |"
echo "+------------------------------------------+"
echo ""
sudo rm -r ${shib_ds_home}
sudo rm -r /usr/local/src/shibboleth-discovery-service-${shib_ds_version}
sudo rm -r /var/log/shibboleth-ds
sudo rm /etc/profile.d/ds_home
sudo rm /etc/tomcat6/Catalina/localhost/ds.xml
sudo rm /etc/apache2/sites-enabled/${shib_ds_server}
sudo rm /etc/apache2/sites-available/${shib_ds_server}
sudo rm /var/www/sites.xml
hosts_line=`cat /etc/hosts | grep "^127.0.1.1"`
hosts_line_after=`echo ${hosts_line} | sed "s/${shib_ds_server}//g" | sed "s/  / /"`
cat /etc/hosts | sed "s/${hosts_line}/${hosts_line_after}/" > ${tempdir}/hosts
sudo cp ${tempdir}/hosts /etc/
sudo service tomcat6 restart
sleep 15
sudo service apache2 restart
echo -e "\n\nShibboleth Discovery Service uninstalled successfully.  Goodbye.\n"

