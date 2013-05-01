#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$(mktemp -d /tmp/shib-idp_installer.XXXXXXXXXX)
downloads_dir="$HOME/shibboleth_downloads"
if [ ! -f "${basedir}/settings.sh" ]; then
        echo "Cannot find ${basedir}/settings.sh.  Aborting..."
        exit 1;
fi
source ${basedir}/settings.sh
source ${basedir}/config.sh $tempdir
echo "+----------------------------------------+"
echo "| Shibboleth Identity Provider Installer |"
echo "+----------------------------------------+"
echo ""
jdbc_file=`ls ${downloads_dir} | grep mysql-connector-java | grep "\.jar" | head -n 1` 
if [ -z "$jdbc_file" ]; then
	echo "You must put the JDBC connector (e.g. mysql-connector-java.x.y.z-bin.jar) in your home directory ($HOME)."
	exit 1
fi	
cd $tempdir

echo "[`date +%H:%M:%S`] Installing Prerequisites"
sudo apt-get update
sudo apt-get install -y openssl ntp apache2 unzip expect


echo "[`date +%H:%M:%S`] Installing Java"
sudo apt-get install -y openjdk-6-jre-headless
cp /etc/profile $tempdir
echo "$etc_profile_1" > $tempdir/java_home
sudo cp $tempdir/java_home /etc/profile.d/


echo "[`date +%H:%M:%S`] Installing Tomcat"
sudo apt-get install -y tomcat6
cp /etc/default/tomcat6 ${tempdir}
CATALINA_HOME="/usr/share/tomcat6"
sudo mkdir -p ${CATALINA_HOME}/shared/classes
sudo mkdir -p ${CATALINA_HOME}/server/classes
sudo chown -R tomcat6:tomcat6 ${CATALINA_HOME}/server ${CATALINA_HOME}/shared


echo "[`date +%H:%M:%S`] Installing Shibboleth Identity Provider"
cd $tempdir
shib_idp_download_url="http://shibboleth.net/downloads/identity-provider/"
shib_idp_folder="shibboleth-identityprovider-${shib_idp_version}"
shib_idp_zip="${shib_idp_folder}-bin.zip"
shib_idp_dowload_zip_url="${shib_idp_download_url}${shib_idp_version}/${shib_idp_zip}"
if [ ! -f ${downloads_dir}/${shib_idp_zip} ]; then
	sudo wget $shib_idp_dowload_zip_url -O ${downloads_dir}/${shib_idp_zip}
fi
cd $downloads_dir
if [ ! -d $shib_idp_folder ]; then 
	sudo unzip $shib_idp_zip
fi
sudo mv $shib_idp_folder /usr/local/src/ 
cd /usr/local/src/$shib_idp_folder
sudo chmod u+x install.sh
sudo mkdir /usr/share/tomcat6/endorsed/
sudo cp ./endorsed/*.jar /usr/share/tomcat6/endorsed/
cd /usr/local/src/
jdbc_file_type=`echo $jdbc_file | awk 'BEGIN{FS=".";ORS=""}{ print $NF }'`
if [ "$jdbc_file_type" != "jar" ]; then
	echo "JDBC file found '$jdbc_file' is not a JAR.  Aborting..."
	exit 1
fi
sudo cp ${downloads_dir}/${jdbc_file} /usr/local/src/${shib_idp_folder}/lib/
sudo cp ${tempdir}/expect.sh /usr/local/src/${shib_idp_folder}/
cd /usr/local/src/${shib_idp_folder}/
sudo chmod ug+x expect.sh
sudo ./expect.sh
sudo ln -s ${shib_idp_home}/logs /var/log/shibboleth
cp /etc/profile $tempdir
echo "$etc_profile_2" > $tempdir/idp_home
sudo cp $tempdir/idp_home /etc/profile.d/
sudo cp /etc/tomcat6/Catalina/localhost/idp.xml $tempdir
echo "$idp_xml" >> $tempdir/idp.xml
sudo cp $tempdir/idp.xml /etc/tomcat6/Catalina/localhost/
sudo chgrp tomcat6 /etc/tomcat6/Catalina/localhost/idp.xml


echo "[`date +%H:%M:%S`] Installing MySQL"
mysql_server_pkg=`apt-cache search mysql-server | grep -o "^mysql-server-[0-9][^ ]*"`
sudo su -c "echo ${mysql_server_pkg} mysql-server/root_password password `echo "'"``echo ${mysql_root_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo ${mysql_server_pkg} mysql-server/root_password_again password `echo "'"``echo ${mysql_root_password}``echo "'"` | debconf-set-selections" 
sudo apt-get install -y mysql-server mysql-client
mysql -u root -p${mysql_root_password} < ${tempdir}/mysql_setup.sql


echo "[`date +%H:%M:%S`] Setting up SSL certificates"
cd $tempdir
openssl genrsa -out ${server_for_ssl}.key 2048
openssl req -new -nodes -subj "${ssl_subject}" -key ${server_for_ssl}.key -out ${server_for_ssl}.csr
openssl x509 -req -days 3650 -in ${server_for_ssl}.csr -signkey ${server_for_ssl}.key -out ${server_for_ssl}.crt
sudo cp ${server_for_ssl}.key /etc/ssl/private/
sudo cp ${server_for_ssl}.crt /etc/ssl/certs/
 

echo "[`date +%H:%M:%S`] Setting up user authentication and configuring Tomcat"
sudo cp $tempdir/login.config ${shib_idp_home}/conf/
echo $etc_default_tomcat6 >> ${tempdir}/tomcat6
sudo cp ${tempdir}/tomcat6 /etc/default/
sudo cp ${tempdir}/server.xml /etc/tomcat6/


echo "[`date +%H:%M:%S`] Configuring Apache"
sudo cp ${server_for_ssl}.key /etc/ssl/private/
sudo cp ${server_for_ssl}.crt /etc/ssl/certs/
cat /etc/apache2/conf.d/security | sed "s/ServerTokens OS/ServerTokens Prod/" > $tempdir/security
sudo cp $tempdir/security /etc/apache2/conf.d/
sudo cp ${tempdir}/${server_for_ssl} /etc/apache2/sites-available/
sudo a2ensite ${server_for_ssl}
sudo a2enmod ssl
sudo a2enmod proxy_ajp 
cp /etc/apache2/ports.conf ${tempdir}
echo "$apache_ports_config" >> ${tempdir}/ports.conf
sudo cp ${tempdir}/ports.conf /etc/apache2/


echo "[`date +%H:%M:%S`] Configuring Shibboleth Identity Provider"
sudo chown root ${shib_idp_home}/credentials/idp.key
sudo chgrp tomcat6 ${shib_idp_home}/credentials/idp.{key,crt}
sudo chmod 440 ${shib_idp_home}/credentials/idp.key
sudo chmod 644 ${shib_idp_home}/credentials/idp.crt
sudo cat ${shib_idp_home}/conf/handler.xml | grep -v "</ph:ProfileHandlerGroup>" > ${tempdir}/handler.xml
echo "${handler_xml}" >> ${tempdir}/handler.xml
sudo cp ${tempdir}/handler.xml ${shib_idp_home}/conf/
sudo cat /usr/local/src/${shib_idp_folder}/src/main/webapp/WEB-INF/web.xml | sed "s@${web_xml_allowed_ips}@<param-value>127.0.0.1/32 ::1/128 ${shib_idp_allowed_ips}</param-value>@" > ${tempdir}/web.xml
sudo cp ${tempdir}/web.xml /usr/local/src/$shib_idp_folder/src/main/webapp/WEB-INF/
sudo cat /usr/local/src/$shib_idp_folder/src/installer/resources/conf-tmpl/relying-party.xml | sed "s@\\\$IDP_HOME\\\$@${shib_idp_home}@g" | sed "s@\\\$IDP_ENTITY_ID\\\$@https://${server_for_ssl}/idp/shibboleth@g" > ${tempdir}/relying-party.xml
sudo cp ${tempdir}/relying-party.xml ${shib_idp_home}/conf/
cd ${shib_idp_home}
sudo chown -R tomcat6 logs metadata  
sudo chgrp -R tomcat6 conf credentials logs metadata war lib
sudo chown tomcat6 conf/attribute-filter.xml
sudo chmod 664 conf/attribute-filter.xml
sudo chmod 750 lib war conf credentials
sudo chmod 775 logs metadata
sudo cp ${tempdir}/expect2.sh /usr/local/src/${shib_idp_folder}/
cd /usr/local/src/${shib_idp_folder}/
sudo chmod ug+x expect2.sh
sudo ./expect2.sh

sudo service tomcat6 restart
sleep 15
sudo service apache2 restart

echo -e "\n\n[`date +%H:%M:%S`] Shibboleth Identity Provider installed successfully.  Goodbye.\n"
