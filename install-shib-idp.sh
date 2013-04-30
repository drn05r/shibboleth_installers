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

echo "Installing Prerequisites"
sudo apt-get update
sudo apt-get install -y openssl ntp apache2 unzip expect


echo "Installing Java"
sudo apt-get install -y openjdk-6-jre-headless
cp /etc/profile $tempdir
echo "$etc_profile_1" >> $tempdir/profile
sudo cp $tempdir/profile /etc/
eval "$etc_profile_1"


echo "Installing Tomcat"
sudo apt-get install -y tomcat6
sudo cat /etc/tomcat6/server.xml | sed -e 's/autoDeploy="true"/autoDeploy="false"/' > $tempdir/server.xml
echo "$tomcat_server_xml_1" >> $tempdir/server.xml
sudo mv $tempdir/server.xml /etc/tomcat6/server.xml


echo "Installing Shibboleth IdP"
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
sudo cp ${tempdir}/expect.sh
cd /usr/local/src/${shib_idp_folder}/
sudo chmod ug+x expect.sh
sudo ./expect.sh
sudo ln -s /opt/shibboleth-idp/logs /var/log/shibboleth
cp /etc/profile $tempdir
echo "$etc_profile_2" >> $tempdir/profile
sudo cp $tempdir/profile /etc/
cp /etc/tomcat6/Catalina/localhost/idp.xml $tempdir
echo "$idp_xml" >> $tempdir/idp.xml
sudo cp $tempdir/idp.xml /etc/tomcat6/Catalina/localhost/


echo "Installing MySQL"
mysql_server_pkg=`apt-cache search mysql-server | grep -o "^mysql-server-[0-9][^ ]*"`
sudo su -c "echo ${mysql_server_pkg} mysql-server/root_password password `echo "'"``echo ${mysql_root_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo ${mysql_server_pkg} mysql-server/root_password_again password `echo "'"``echo ${mysql_root_password}``echo "'"` | debconf-set-selections" 
sudo apt-get install -y mysql-server mysql-client
mysql -u root -p${mysql_root_password} < ${tempdir}/mysql_setup.sql


echo "Setting up SSL certificates"
cd $tempdir
openssl genrsa -out ${server_for_ssl}.key 2048
openssl req -new -nodes -subj "${ssl_subject}" -key ${server_for_ssl}.key -out ${server_for_ssl}.csr
openssl x509 -req -days 3650 -in ${server_for_ssl}.csr -signkey ${server_for_ssl}.key -out ${server_for_ssl}.crt
sudo cp ${server_for_ssl}.key /etc/ssl/private/
sudo cp ${server_for_ssl}.crt /etc/ssl/certs/
 

echo "Setting up User Authentication"
cp /opt/shibboleth-idp/conf/login.config $tempdir
echo "$shib_idp_login_config" >> $tempdir/login.config
sudo cp $tempdir/login.config /opt/shibboleth-idp/conf/
cp /etc/tomcat6/server.xml $tempdir
echo "$tomcat_server_xml_2" >> $tempdir/server.xml
sudo cp $tempdir/server.xml


echo "Configuring Apache"
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
sudo service apache2 restart


echo "Configuring Shibboleth Identity Provider"
sudo chown root /opt/shibboleth-idp/credentials/idp.key
sudo chgrp tomcat6 /opt/shibboleth-idp/credentials/idp.{key,crt}
sudo chmod 440 /opt/shibboleth-idp/credentials/idp.key
sudo chmod 644 /opt/shibboleth-idp/credentials/idp.crt

