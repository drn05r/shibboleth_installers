#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$(mktemp -d /tmp/shib-idp_installer.XXXXXXXXXX)
downloads_dir="$HOME/shibboleth_downloads"
echo "+----------------------------------------+"
echo "| Shibboleth Identity Provider Installer |"
echo "+----------------------------------------+"
echo ""
if [ ! -f "${basedir}/settings.sh" ]; then
        echo "Cannot find ${basedir}/settings.sh.  Aborting..."
        exit 1;
fi
if [ ! -d "${downloads_dir}" ]; then
        mkdir ${downloads_dir}
fi
source ${basedir}/settings.sh
source ${basedir}/config.sh $tempdir
jdbc_file=`ls ${downloads_dir} | grep mysql-connector-java | grep "\.jar" | head -n 1` 
if [ -z "$jdbc_file" ]; then
	cd ${tempdir}
	wget http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${mysql_jdbc_version}.zip/from/http:/mysql.he.net/ -O mysql-connector-java-${mysql_jdbc_version}.zip
	unzip mysql-connector-java-${mysql_jdbc_version}.zip
	cp mysql-connector-java-${mysql_jdbc_version}/mysql-connector-java-${mysql_jdbc_version}-bin.jar ${downloads_dir}
	jdbc_file=`ls ${downloads_dir} | grep mysql-connector-java | grep "\.jar" | head -n 1`
fi	
cd $tempdir

echo "[`date +%H:%M:%S`] Installing Prerequisites"
sudo apt-get update
sudo apt-get install -y openssl ntp apache2 unzip expect

if [ `grep ${shib_idp_server} /etc/hosts | grep "^127.0.1.1" | wc -l` -eq 0 ]; then
	echo "[`date +%H:%M:%S`] Adding Shibboleth Identity Provider hostname to local hosts file."
	cat /etc/hosts | sed "s/^\(127.0.1.1.*\)$/\1 ${shib_idp_server}/g" > ${tempdir}/hosts
	sudo cp ${tempdir}/hosts /etc/
fi

if [ ! -f "${JAVA_HOME}/bin/java" ]; then
        echo "[`date +%H:%M:%S`] Installing Java"
        sudo apt-get install -y openjdk-6-jre-headless
        sudo cp ${tempdir}/java_home /etc/profile.d/
fi


CATALINA_HOME="/usr/share/tomcat6"
if [ ! -d ${CATALINA_HOME} ]; then
        echo "[`date +%H:%M:%S`] Installing Tomcat"
        sudo apt-get install -y tomcat6
        cp /etc/default/tomcat6 ${tempdir}
        sudo mkdir -p ${CATALINA_HOME}/shared/classes
        sudo mkdir -p ${CATALINA_HOME}/server/classes
        sudo chown -R tomcat6:tomcat6 ${CATALINA_HOME}/server ${CATALINA_HOME}/shared
fi


echo "[`date +%H:%M:%S`] Installing Shibboleth Identity Provider"
cd $tempdir
shib_idp_download_url="http://shibboleth.net/downloads/identity-provider/"
shib_idp_folder="shibboleth-identityprovider-${shib_idp_version}"
shib_idp_zip="${shib_idp_folder}-bin.zip"
shib_idp_download_zip_url="${shib_idp_download_url}${shib_idp_version}/${shib_idp_zip}"
if [ ! -f ${downloads_dir}/${shib_idp_zip} ]; then
	wget ${shib_idp_download_zip_url} -O ${downloads_dir}/${shib_idp_zip}
fi
cd $downloads_dir
if [ ! -d $shib_idp_folder ]; then 
	unzip $shib_idp_zip
fi
sudo mv $shib_idp_folder /usr/local/src/ 
cd /usr/local/src/$shib_idp_folder
sudo chmod u+x install.sh
if [ ! -d /usr/share/tomcat6/endorsed/ ]; then
        sudo mkdir /usr/share/tomcat6/endorsed/
fi
sudo cp ./endorsed/*.jar /usr/share/tomcat6/endorsed/
cd /usr/local/src/
jdbc_file_type=`echo $jdbc_file | awk 'BEGIN{FS=".";ORS=""}{ print $NF }'`
if [ "$jdbc_file_type" != "jar" ]; then
	echo "JDBC file found '$jdbc_file' is not a JAR.  Aborting..."
	exit 1
fi
sudo cp ${downloads_dir}/${jdbc_file} /usr/local/src/${shib_idp_folder}/lib/
sudo cp ${tempdir}/expect_idp.sh /usr/local/src/${shib_idp_folder}/
cd /usr/local/src/${shib_idp_folder}/
sudo chmod ug+x expect_idp.sh
sudo ./expect_idp.sh
sudo ln -s ${shib_idp_home}/logs /var/log/shibboleth-idp
sudo cp $tempdir/idp_home /etc/profile.d/
sudo cp $tempdir/idp.xml /etc/tomcat6/Catalina/localhost/
sudo chgrp tomcat6 /etc/tomcat6/Catalina/localhost/idp.xml


echo "[`date +%H:%M:%S`] Installing MySQL"
mysql_server_pkg=`apt-cache search mysql-server | grep -o "^mysql-server-[0-9][^ ]*"`
sudo su -c "echo ${mysql_server_pkg} mysql-server/root_password password `echo "'"``echo ${mysql_root_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo ${mysql_server_pkg} mysql-server/root_password_again password `echo "'"``echo ${mysql_root_password}``echo "'"` | debconf-set-selections" 
sudo apt-get install -y mysql-server mysql-client
mysql -u root -p${mysql_root_password} < ${tempdir}/mysql_setup.sql


if [ ! -f /etc/ssl/certs/${shib_idp_server}.crt ]; then
        echo "[`date +%H:%M:%S`] Setting up SSL certificates"
        cd $tempdir
        openssl genrsa -out ${shib_idp_server}.key 2048
        openssl req -new -nodes -subj "${shib_idp_ssl_subject}" -key ${shib_idp_server}.key -out ${shib_idp_server}.csr
        openssl x509 -req -days 3650 -in ${shib_idp_server}.csr -signkey ${shib_idp_server}.key -out ${shib_idp_server}.crt
        sudo cp ${shib_idp_server}.key /etc/ssl/private/
        sudo cp ${shib_idp_server}.crt /etc/ssl/certs/
fi
 

echo "[`date +%H:%M:%S`] Setting up user authentication and configuring Tomcat"
sudo cp $tempdir/login.config ${shib_idp_home}/conf/
if [ `grep "$etc_default_tomcat6" /etc/default/tomcat6 | wc -l` -lt 1 ]; then
        cat /etc/default/tomcat6 | grep -v "^JAVA_OPTS" > ${tempdir}/tomcat6
        echo $etc_default_tomcat6 >> ${tempdir}/tomcat6
        sudo cp ${tempdir}/tomcat6 /etc/default/
        sudo cp ${tempdir}/server.xml /etc/tomcat6/
fi


if [ ! -f /etc/apache2/sites-enabled/${shib_idp_server} ]; then
        echo "[`date +%H:%M:%S`] Configuring Apache"
        cat /etc/apache2/conf.d/security | sed "s/ServerTokens OS/ServerTokens Prod/" > $tempdir/security
        sudo cp ${tempdir}/security /etc/apache2/conf.d/
        sudo cp ${tempdir}/${shib_idp_server} /etc/apache2/sites-available/
        sudo a2ensite ${shib_idp_server}
        sudo a2enmod ssl
        sudo a2enmod proxy_ajp
        if [ `grep "^Listen 8443" /etc/apache2/ports.conf | wc -l` -eq 0 ]; then
                cp /etc/apache2/ports.conf ${tempdir}
                echo "Listen 8443" >> ${tempdir}/ports.conf
                sudo cp ${tempdir}/ports.conf /etc/apache2/
        fi
	if [ `grep "^NameVirtualHost \*:443" /etc/apache2/ports.conf | wc -l` -eq 0 ]; then
		cp /etc/apache2/ports.conf ${tempdir}
                echo "NameVirtualHost *:443" >> ${tempdir}/ports.conf
                sudo cp ${tempdir}/ports.conf /etc/apache2/
        fi
fi


echo "[`date +%H:%M:%S`] Configuring Shibboleth Identity Provider"
sudo chown root ${shib_idp_home}/credentials/idp.key
sudo chgrp tomcat6 ${shib_idp_home}/credentials/idp.{key,crt}
sudo chmod 440 ${shib_idp_home}/credentials/idp.key
sudo chmod 644 ${shib_idp_home}/credentials/idp.crt
sudo cat ${shib_idp_home}/conf/handler.xml | grep -v "</ph:ProfileHandlerGroup>" > ${tempdir}/handler.xml
echo "${handler_xml}" >> ${tempdir}/handler.xml
sudo cp ${tempdir}/handler.xml ${shib_idp_home}/conf/
sudo cat /usr/local/src/${shib_idp_folder}/src/main/webapp/WEB-INF/web.xml | sed "s@${web_xml_allowed_ips}@<param-value>127.0.0.1/32 ::1/128 ${allowed_ips}</param-value>@" > ${tempdir}/web.xml
sudo cp ${tempdir}/web.xml /usr/local/src/$shib_idp_folder/src/main/webapp/WEB-INF/
sudo cp ${tempdir}/relying-party.xml ${shib_idp_home}/conf/
sudo cp ${tempdir}/attribute-resolver.xml ${shib_idp_home}/conf/
sudo cp ${tempdir}/attribute-filter.xml ${shib_idp_home}/conf/
cd ${shib_idp_home}
sudo chown -R tomcat6 logs metadata  
sudo chgrp -R tomcat6 conf credentials logs metadata war lib
sudo chown tomcat6 conf/attribute-filter.xml
sudo chmod 664 conf/attribute-filter.xml
sudo chmod 750 lib war conf credentials
sudo chmod 775 logs metadata
sudo cp ${tempdir}/expect_idp2.sh /usr/local/src/${shib_idp_folder}/
cd /usr/local/src/${shib_idp_folder}/
sudo chmod ug+x expect_idp2.sh
sudo ./expect_idp2.sh

sudo service tomcat6 restart
echo "[`date +%H:%M:%S`] Sleeping for 30 seconds to allow Tomcat to initialise before restarting Apache."
sleep 30
sudo service apache2 restart

echo -e "\n\n[`date +%H:%M:%S`] Shibboleth Identity Provider installed successfully.  Goodbye.\n"
