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
sudo rm /etc/profile.d/idp_home
sudo rm /etc/tomcat6/Catalina/localhost/idp.xml
sudo rm /etc/apache2/sites-enabled/${shib_idp_server}
sudo rm /etc/apache2/sites-available/${shib_idp_server}
hosts_line=`cat /etc/hosts | grep "^127.0.1.1"` 
hosts_line_after=`echo ${hosts_line} | sed "s/${shib_idp_server}//g" | sed "s/  / /"`
cat /etc/hosts | sed "s/${hosts_line}/${hosts_line_after}/" > ${tempdir}/hosts
sudo cp ${tempdir}/hosts /etc/
mysql -u root -p${mysql_root_password} -e "DROP DATABASE shibboleth; DROP USER 'shibboleth'@'localhost'; FLUSH PRIVILEGES;"
sudo service tomcat6 restart
sleep 15
sudo service apache2 restart
echo -e "\n\nShibboleth Identity Provider uninstalled successfully.  Goodbye.\n"
