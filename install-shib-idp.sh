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
        exit 1
fi
if [ ! -d "${downloads_dir}" ]; then
        mkdir ${downloads_dir} || { echo "Could not create directory ${downloads_dir}.  Aborting..."; exit 2; }
fi
source ${basedir}/settings.sh
source ${basedir}/config.sh $tempdir
jdbc_file=`ls ${downloads_dir} | grep mysql-connector-java | grep "\.jar" | head -n 1` 
if [ -z "$jdbc_file" ]; then
	cd ${tempdir}
	wget http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${mysql_jdbc_version}.zip/from/http:/mysql.he.net/ -O mysql-connector-java-${mysql_jdbc_version}.zip || { echo "Could not download MySQL JDBC driver.  Aborting..."; exit 3; }
	unzip mysql-connector-java-${mysql_jdbc_version}.zip || { echo "Could not unzip MySQL JDBC driver.  Aborting..."; exit 4; }
	cp mysql-connector-java-${mysql_jdbc_version}/mysql-connector-java-${mysql_jdbc_version}-bin.jar ${downloads_dir} || { echo "Could not copy MySQL JDBC driver to ${downloads_dir}.  Aborting..."; exit 5; }
	jdbc_file=`ls ${downloads_dir} | grep mysql-connector-java | grep "\.jar" | head -n 1`
	if [ -z "$jdbc_file" ]; then
		echo "MySQL JDBC driver could not be found in ${downloads_dir}.  Aborting..."
		exit 6
	fi
fi	
cd ${tempdir}


echo "[`date +%H:%M:%S`] Installing Prerequisites"
sudo apt-get update || { echo "Could not run apt-get update.  Aborting..."; exit 7; }
sudo apt-get install -y openssl ntp apache2 unzip expect || { echo "Could not install prerequisite packages using apt-get.  Aborting..."; exit 8; }

if [ `grep ${shib_idp_server} /etc/hosts | grep "^127.0.1.1" | wc -l` -eq 0 ]; then
	echo "[`date +%H:%M:%S`] Adding Shibboleth Identity Provider hostname to local hosts file."
	cat /etc/hosts | sed "s/^\(127.0.1.1.*\)$/\1 ${shib_idp_server}/g" > ${tempdir}/hosts || { echo "Could not copy modified /etc/hosts to ${tempdir}.  Aborting..."; exit 9; } 
	sudo cp ${tempdir}/hosts /etc/ || { echo "Could not copy hosts file to /etc/hosts.  Aborting..."; exit 9; }
fi

if [ ! -f "${JAVA_HOME}/bin/java" ]; then
        echo "[`date +%H:%M:%S`] Installing Java"
        sudo apt-get install -y openjdk-6-jre-headless || { echo "Could not install Java using apt-get.  Aborting..."; exit 10; }
        sudo cp ${tempdir}/java_home /etc/profile.d/ || { echo "Could not copy file to /etc/profile.d/java_home.  Aborting..."; exit 11; }
fi


CATALINA_HOME="/usr/share/tomcat6"
if [ ! -d ${CATALINA_HOME} ]; then
        echo "[`date +%H:%M:%S`] Installing Tomcat"
        sudo apt-get install -y tomcat6 || { echo "Could not install Tomcat using apt-get.  Aborting..."; exit 12; }
        cp /etc/default/tomcat6 ${tempdir} || { echo "Could not copy /etc/default/tomcat6 to ${tempdir}.  Aborting..."; exit 13; }
        sudo mkdir -p ${CATALINA_HOME}/shared/classes || { echo "Could not create directory ${CATALINA_HOME}/shared/classes.  Aborting..."; exit 14; }
        sudo mkdir -p ${CATALINA_HOME}/server/classes || { echo "Could not create directory ${CATALINA_HOME}/server/classes.  Aborting..."; exit 15; }
        sudo chown -R tomcat6:tomcat6 ${CATALINA_HOME}/server ${CATALINA_HOME}/shared || { echo "Could not change ownership on ${CATALINA_HOME}/shared/classes and ${CATALINA_HOME}/server/classes.  Aborting..."; exit 16; }
fi


echo "[`date +%H:%M:%S`] Installing Shibboleth Identity Provider"
cd $tempdir
shib_idp_download_url="http://shibboleth.net/downloads/identity-provider/"
shib_idp_folder="shibboleth-identityprovider-${shib_idp_version}"
shib_idp_zip="${shib_idp_folder}-bin.zip"
shib_idp_download_zip_url="${shib_idp_download_url}${shib_idp_version}/${shib_idp_zip}"
if [ ! -f ${downloads_dir}/${shib_idp_zip} ]; then
	wget ${shib_idp_download_zip_url} -O ${downloads_dir}/${shib_idp_zip} || { echo "Could not download ${shib_idp_download_zip_url}.  Aborting..."; exit 17; }
fi
cd $downloads_dir
if [ ! -d $shib_idp_folder ]; then 
	unzip $shib_idp_zip || { echo "Could not unzip ${shib_idp_zip}.  Aborting..."; exit 18; }
fi
sudo mv $shib_idp_folder /usr/local/src/ || { echo "Could not move ${shib_idp_folder} directory to /usr/local/src/.  Aborting..."; exit 19; }
cd /usr/local/src/$shib_idp_folder
sudo chmod u+x install.sh || { echo "Could not give user execute privileges to /usr/local/src/${shib_idp_folder}/install.sh.   Aborting..."; exit 20; }
if [ ! -d /usr/share/tomcat6/endorsed/ ]; then
        sudo mkdir /usr/share/tomcat6/endorsed/ || { echo "Could not create directory /usr/share/tomcat6/endorsed/.  Aborting..."; exit 21; }
fi
sudo cp ./endorsed/*.jar /usr/share/tomcat6/endorsed/ || { echo "Could not copy JAR files to /usr/share/tomcat6/endorsed/.  Aborting..."; exit 22; }
cd /usr/local/src/
sudo cp ${downloads_dir}/${jdbc_file} /usr/local/src/${shib_idp_folder}/lib/ || { echo "Could not copy file ${downloads_dir}/${jdbc_file} to /usr/local/src/${shib_idp_folder}/lib/.  Aborting..."; exit 23; }
sudo cp ${tempdir}/expect_idp.sh /usr/local/src/${shib_idp_folder}/ || { echo "Could not copy file ${tempdir}/expect_idp.sh to /usr/local/src/${shib_idp_folder}/.  Aborting..."; exit 24; }
cd /usr/local/src/${shib_idp_folder}/
sudo chmod ug+x expect_idp.sh || { echo "Could not give user and group execute privileges to expect_idp.sh.  Aborting..."; exit 25; }
sudo ./expect_idp.sh || { echo "Could not successfully execute expect_idp.sh.   Aborting..."; exit 26; }
sudo ln -s ${shib_idp_home}/logs /var/log/shibboleth-idp  || { echo "Could not create symlink /var/log/shibboleth-idp -> ${shib_idp_home}/logs.  Aborting..."; exit 27; }
sudo cp $tempdir/idp_home /etc/profile.d/ || { echo "Could not copy file to /etc/profile.d/idp_home.  Aborting..."; exit 28; }
sudo cp $tempdir/idp.xml /etc/tomcat6/Catalina/localhost/ || { echo "Could not copy file idp.xml to /etc/tomcat6/Catalina/localhost/.  Aborting..."; exit 29; }
sudo chgrp tomcat6 /etc/tomcat6/Catalina/localhost/idp.xml || { echo "Could not change group to tomcat6 for /etc/tomcat6/Catalina/localhost/idp.xml.  Aborting..."; exit 30; }


echo "[`date +%H:%M:%S`] Installing MySQL"
mysql_server_pkg=`apt-cache search mysql-server | grep -o "^mysql-server-[0-9][^ ]*"`
sudo su -c "echo ${mysql_server_pkg} mysql-server/root_password password `echo "'"``echo ${mysql_root_password}``echo "'"` | debconf-set-selections"
sudo su -c "echo ${mysql_server_pkg} mysql-server/root_password_again password `echo "'"``echo ${mysql_root_password}``echo "'"` | debconf-set-selections" 
sudo apt-get install -y mysql-server mysql-client || { echo "Could not install MySQL using apt-get.  Aborting..."; exit 31; }
mysql -u root -p${mysql_root_password} < ${tempdir}/mysql_setup.sql || { echo "Could not setup database, user and table in MySQL.  Aborting..."; exit 32; }


if [ ! -f /etc/ssl/certs/${shib_idp_server}.crt ]; then
        echo "[`date +%H:%M:%S`] Setting up SSL certificates"
        cd $tempdir
        openssl genrsa -out ${shib_idp_server}.key 2048 || { echo "Could not generate ${shib_idp_server}.key using OpenSSL.  Aborting..."; exit 33; }
        openssl req -new -nodes -subj "${shib_idp_ssl_subject}" -key ${shib_idp_server}.key -out ${shib_idp_server}.csr || { echo "Could not generate ${shib_idp_server}.csr using OpenSSL.  Aborting..."; exit 34; }
        openssl x509 -req -days 3650 -in ${shib_idp_server}.csr -signkey ${shib_idp_server}.key -out ${shib_idp_server}.crt  || { echo "Could not generate ${shib_idp_server}.crt using OpenSSL.  Aborting..."; exit 34; }
        sudo cp ${shib_idp_server}.key /etc/ssl/private/ || { echo "Could not copy file ${shib_idp_server}.key to /etc/ssl/private/.  Aborting..."; exit 35; }
        sudo cp ${shib_idp_server}.crt /etc/ssl/certs/ || { echo "Could not copy file ${shib_idp_server}.crt to /etc/ssl/certs/.  Aborting..."; exit 36; }
fi
 

echo "[`date +%H:%M:%S`] Setting up user authentication and configuring Tomcat"
sudo cp ${tempdir}/login.config ${shib_idp_home}/conf/ || { echo "Could not copy file ${tempdir}/login.config to ${shib_idp_home}/conf/.  Aborting..."; exit 37; }
if [ `grep "$etc_default_tomcat6" /etc/default/tomcat6 | wc -l` -lt 1 ]; then
        cat /etc/default/tomcat6 | grep -v "^JAVA_OPTS" > ${tempdir}/tomcat6 || { echo "Could not copy file /etc/default/tomcat6 to ${tempdir}.  Aborting..."; exit 38; }
        echo $etc_default_tomcat6 >> ${tempdir}/tomcat6 || { echo "Could not copy add additional configuration to ${tempdir}/tomcat6.  Aborting..."; exit 39; }
        sudo cp ${tempdir}/tomcat6 /etc/default/ || { echo "Could not copy file ${tempdir}/tomcat6 to /etc/default/.  Aborting..."; exit 40; }
        sudo cp ${tempdir}/server.xml /etc/tomcat6/ || { echo "Could not copy file ${tempdir}/server.xml to /etc/tomcat6/.  Aborting..."; exit 41; }
fi


if [ ! -f /etc/apache2/sites-enabled/${shib_idp_server} ]; then
        echo "[`date +%H:%M:%S`] Configuring Apache"
        cat /etc/apache2/conf.d/security | sed "s/ServerTokens OS/ServerTokens Prod/" > $tempdir/security || { echo "Could not copy a modified version of /etc/apache2/conf.d/security to ${tempdir}.  Aborting..."; exit 42; }
        sudo cp ${tempdir}/security /etc/apache2/conf.d/ || { echo "Could not copy file ${tempdir}/security to /etc/apache2/conf.d/.  Aborting..."; exit 43; }
        sudo cp ${tempdir}/${shib_idp_server} /etc/apache2/sites-available/ || { echo "Could not copy file ${tempdir}/${shib_idp_server} to /etc/apache2/sites-available/.  Aborting..."; exit 44; }
        sudo a2ensite ${shib_idp_server} || { echo "Could not enable site ${shib_idp_server} in Apache.  Aborting..."; exit 45; }
        sudo a2enmod ssl || { echo "Could not enable module ssl for Apache.  Aborting..."; exit 46; }
        sudo a2enmod proxy_ajp || { echo "Could not enable module proxy_ajp for Apache.  Aborting..."; exit 47; }
        if [ `grep "^Listen 8443" /etc/apache2/ports.conf | wc -l` -eq 0 ]; then
                cp /etc/apache2/ports.conf ${tempdir} || { echo "Could not copy file /etc/apache2/ports.conf to ${tempdir}.  Aborting..."; exit 48; }
                echo "Listen 8443" >> ${tempdir}/ports.conf || { echo "Could not add 'Listen 8443' to ${tempdir}/ports.conf.  Aborting..."; exit 49; }
                sudo cp ${tempdir}/ports.conf /etc/apache2/ || { echo "Could not copy modified ${tempdir}/ports.conf to /etc/apache2/.  Aborting..."; exit 50; }
        fi
	if [ `grep "^NameVirtualHost \*:443" /etc/apache2/ports.conf | wc -l` -eq 0 ]; then
		cp /etc/apache2/ports.conf ${tempdir} || { echo "Could not copy file /etc/apache2/ports.conf to ${tempdir}.  Aborting..."; exit 51; }
                echo "NameVirtualHost *:443" >> ${tempdir}/ports.conf || { echo "Could not add 'NameVirtualHost *:443' to ${tempdir}/ports.conf.  Aborting..."; exit 52; }
                sudo cp ${tempdir}/ports.conf /etc/apache2/ || { echo "Could not copy modified ${tempdir}/ports.conf to /etc/apache2/.  Aborting..."; exit 53; }
        fi
fi


echo "[`date +%H:%M:%S`] Configuring Shibboleth Identity Provider"
sudo chown root ${shib_idp_home}/credentials/idp.key || { echo "Could not change owner of ${shib_idp_home}/credentials/idp.key to root.  Aborting..."; exit 54; }
sudo chgrp tomcat6 ${shib_idp_home}/credentials/idp.{key,crt} || { echo "Could not chnage owner of ${shib_idp_home}/credentials/idp.{key,crt} to tomcat6.  Aborting..."; exit 55; }
sudo chmod 440 ${shib_idp_home}/credentials/idp.key || { echo "Could change permissions on ${shib_idp_home}/credentials/idp.key to 440.  Aborting..."; exit 56; }
sudo chmod 644 ${shib_idp_home}/credentials/idp.crt || { echo "Could change permissions on ${shib_idp_home}/credentials/idp.crt to 644.  Aborting..."; exit 57; }
sudo cat ${shib_idp_home}/conf/handler.xml | grep -v "</ph:ProfileHandlerGroup>" > ${tempdir}/handler.xml  || { echo "Could not copy modified ${shib_idp_home}/conf/handler.xml to ${tempdir}."; exit 58; }
echo "${handler_xml}" >> ${tempdir}/handler.xml || { echo "Could not add additional configuration to ${tempdir}/handler.xml.  Aborting..."; exit 59; }
sudo cp ${tempdir}/handler.xml ${shib_idp_home}/conf/ || { echo "Could not copy modified ${tempdir}/handler.xml to ${shib_idp_home}/conf/.  Aborting..."; exit 60; }
sudo cat /usr/local/src/${shib_idp_folder}/src/main/webapp/WEB-INF/web.xml | sed "s@${web_xml_allowed_ips}@<param-value>127.0.0.1/32 ::1/128 ${allowed_ips}</param-value>@" > ${tempdir}/web.xml  || { echo "Could not copy modified /usr/local/src/${shib_idp_folder}/src/main/webapp/WEB-INF/web.xml to ${tempdir}."; exit 61; }
sudo cp ${tempdir}/web.xml /usr/local/src/$shib_idp_folder/src/main/webapp/WEB-INF/ || { echo "Could not copy modified ${tempdir}/web.xml to /usr/local/src/${shib_idp_folder}/src/main/webapp/WEB-INF/."; exit 62; }
sudo cp ${tempdir}/relying-party.xml ${shib_idp_home}/conf/ || { echo "Could not copy modified ${tempdir}/relying-party.xml to ${shib_idp_home}/conf/.  Aborting..."; exit 63; }
sudo cp ${tempdir}/attribute-resolver.xml ${shib_idp_home}/conf/ || { echo "Could not copy modified ${tempdir}/attribute-resolver.xml to ${shib_idp_home}/conf/.  Aborting..."; exit 64; }
sudo cp ${tempdir}/attribute-filter.xml ${shib_idp_home}/conf/ || { echo "Could not copy modified ${tempdir}/sttribute-filter.xml to ${shib_idp_home}/conf/.  Aborting..."; exit 65; }
cd ${shib_idp_home}
sudo chown -R tomcat6 logs metadata || { echo "Could not change owner of logs and metadata in ${shib_idp_home} to tomcat6.  Aborting..."; exit 66; }
sudo chgrp -R tomcat6 conf credentials logs metadata war lib || { echo "Could not change group of conf, credentials, logs, metadata, war and lib in ${shib_idp_home} to tomcat6.  Aborting..."; exit 67; }
sudo chown tomcat6 conf/attribute-filter.xml || { echo "Could not change owner of ${shib_idp_home}/conf/attribute-filter.xml to tomcat6.  Aborting..."; exit 68; }
sudo chmod 664 conf/attribute-filter.xml || { echo "Could change permissions on ${shib_idp_home}/conf/attribute-filter.xml to 664.  Aborting..."; exit 69; }
sudo chmod 750 lib war conf credentials || { echo "Could not change permissions on lib, war, conf and credentials in ${shib_idp_home} to tomcat 750.  Aborting..."; exit 70; }
sudo chmod 775 logs metadata || { echo "Could not change permissions on logs and metadata in ${shib_idp_home} to tomcat 775.  Aborting..."; exit 71; }

sudo cp ${tempdir}/expect_idp2.sh /usr/local/src/${shib_idp_folder}/ || { echo "Could not copy ${tempdir}/expect_idp2.sh to /usr/local/src/${shib_idp_folder}/  Aborting..."; exit 72; }
cd /usr/local/src/${shib_idp_folder}/
sudo chmod ug+x expect_idp2.sh || { echo "Could not give user and group execute privileges to expect_idp2.sh.  Aborting..."; exit 73; } 
sudo ./expect_idp2.sh  || { echo "Could not successfully execute expect_idp2.sh.  Aborting..."; exit 74; }

sudo service tomcat6 restart || { echo "Could not restart Tomcat.  Aborting..."; exit 74; }
echo "[`date +%H:%M:%S`] Sleeping for 30 seconds to allow Tomcat to initialise before restarting Apache."
sleep 30
sudo service apache2 restart || { echo "Could not restart Apache.  Aborting..."; exit 75; }

echo -e "\n\n[`date +%H:%M:%S`] Shibboleth Identity Provider installed successfully.  Goodbye.\n"
