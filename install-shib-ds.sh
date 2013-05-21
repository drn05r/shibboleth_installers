#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$(mktemp -d /tmp/shib-ds_installer.XXXXXXXXXX)
downloads_dir="$HOME/shibboleth_downloads"
echo "+----------------------------------------+"
echo "| Shibboleth Discovery Service Installer |"
echo "+----------------------------------------+"
echo ""
if [ ! -f "${basedir}/settings.sh" ]; then
        echo "Cannot find ${basedir}/settings.sh.  Aborting..."
        exit 1;
fi
source ${basedir}/settings.sh
source ${basedir}/config.sh $tempdir
if [ ! -d "${downloads_dir}" ]; then
        mkdir ${downloads_dir} || { echo "Could not create directory ${downloads_dir}.  Aborting..."; exit 2; }
fi


echo "[`date +%H:%M:%S`] Installing Prerequisites"
sudo apt-get update || { echo "Could not run apt-get update.  Aborting..."; exit 3; }
sudo apt-get install -y openssl ntp apache2 unzip expect tomcat6 || { echo "Could not install prerequisite packages using apt-get.  Aborting..."; exit 4; }


if [ `grep ${shib_ds_server} /etc/hosts | grep "^127.0.1.1" | wc -l` -eq 0 ]; then
        echo "[`date +%H:%M:%S`] Adding Shibboleth Discovery Service hostname to local hosts file."
        cat /etc/hosts | sed "s/^\(127.0.1.1.*\)$/\1 ${shib_ds_server}/g" > ${tempdir}/hosts || { echo "Could not copy modified /etc/hosts to ${tempdir}.  Aborting..."; exit 5; }
        sudo cp ${tempdir}/hosts /etc/ || { echo "Could not copy hosts file to /etc/hosts.  Aborting..."; exit 6; }
fi


if [ ! -f "${JAVA_HOME}/bin/java" ]; then
	echo "[`date +%H:%M:%S`] Installing Java"
	sudo apt-get install -y openjdk-6-jre-headless || { echo "Could not install Java using apt-get.  Aborting..."; exit 7; }
	sudo cp $tempdir/java_home /etc/profile.d/ || { echo "Could not copy file to /etc/profile.d/java_home.  Aborting..."; exit 8; }
fi


CATALINA_HOME="/usr/share/tomcat6"
if [ ! -d ${CATALINA_HOME} ]; then 
	echo "[`date +%H:%M:%S`] Installing Tomcat"
	sudo apt-get install -y tomcat6 || { echo "Could not install Tomcat using apt-get.  Aborting..."; exit 9; }
	cp /etc/default/tomcat6 ${tempdir} || { echo "Could not copy /etc/default/tomcat6 to ${tempdir}.  Aborting..."; exit 10; }
	sudo mkdir -p ${CATALINA_HOME}/shared/classes || { echo "Could not create directory ${CATALINA_HOME}/shared/classes.  Aborting..."; exit 11; }
	sudo mkdir -p ${CATALINA_HOME}/server/classes || { echo "Could not create directory ${CATALINA_HOME}/server/classes.  Aborting..."; exit 12; }
	sudo chown -R tomcat6:tomcat6 ${CATALINA_HOME}/server ${CATALINA_HOME}/shared || { echo "Could not change ownership on ${CATALINA_HOME}/shared/classes and ${CATALINA_HOME}/server/classes.  Aborting..."; exit 13; }
fi


echo "[`date +%H:%M:%S`] Installing Shibboleth Discovery Service"
cd $tempdir
shib_ds_download_url="http://shibboleth.net/downloads/centralized-discovery-service/"
shib_ds_folder="shibboleth-discovery-service-${shib_ds_version}"
shib_ds_zip="${shib_ds_folder}-bin.zip"
shib_ds_download_zip_url="${shib_ds_download_url}${shib_ds_version}/${shib_ds_zip}"
if [ ! -f ${downloads_dir}/${shib_ds_zip} ]; then
	wget $shib_ds_download_zip_url -O ${downloads_dir}/${shib_ds_zip} || { echo "Could not download ${shib_ds_download_zip_url}.  Aborting..."; exit 14; }
fi
cd $downloads_dir
if [ ! -d $shib_ds_folder ]; then 
	 unzip $shib_ds_zip || { echo "Could not unzip ${shib_ds_zip}.  Aborting..."; exit 15; }
fi
sudo mv $shib_ds_folder /usr/local/src/ || { echo "Could not move ${shib_ds_folder} directory to /usr/local/src/.  Aborting..."; exit 16; }
cd /usr/local/src/$shib_ds_folder
sudo chmod u+x install.sh || { echo "Could not give user execute privileges to /usr/local/src/${shib_ds_folder}/install.sh.   Aborting..."; exit 17; }
if [ ! -d /usr/share/tomcat6/endorsed/ ]; then
	sudo mkdir /usr/share/tomcat6/endorsed/ || { echo "Could not create directory /usr/share/tomcat6/endorsed/.  Aborting..."; exit 18; }
fi
sudo cp ./lib/endorsed/*.jar /usr/share/tomcat6/endorsed/ || { echo "Could not copy JAR files to /usr/share/tomcat6/endorsed/.  Aborting..."; exit 19; }
cd /usr/local/src/
sudo cp ${tempdir}/expect_ds.sh /usr/local/src/${shib_ds_folder}/ || { echo "Could not copy file ${tempdir}/expect_ds.sh to /usr/local/src/${shib_ds_folder}/.  Aborting..."; exit 20; }
cd /usr/local/src/${shib_ds_folder}/
sudo chmod ug+x expect_ds.sh || { echo "Could not give user and group execute privileges to expect_ds.sh.  Aborting..."; exit 21; }
sudo ./expect_ds.sh  || { echo "Could not successfully execute expect_ds.sh.   Aborting..."; exit 22; }
sudo ln -s ${shib_ds_home}/logs /var/log/shibboleth-ds || { echo "Could not create symlink /var/log/shibboleth-ds -> ${shib_ds_home}/logs.  Aborting..."; exit 23; }
sudo cp $tempdir/ds_home /etc/profile.d/ || { echo "Could not copy file to /etc/profile.d/ds_home.  Aborting..."; exit 24; }
sudo cp $tempdir/ds.xml /etc/tomcat6/Catalina/localhost/ || { echo "Could not copy file ds.xml to /etc/tomcat6/Catalina/localhost/.  Aborting..."; exit 25; }
sudo chgrp tomcat6 /etc/tomcat6/Catalina/localhost/ds.xml  || { echo "Could not change group to tomcat6 for /etc/tomcat6/Catalina/localhost/ds.xml.  Aborting..."; exit 26; }

if [ ! -f /etc/ssl/certs/${shib_ds_server}.crt ]; then
	echo "[`date +%H:%M:%S`] Setting up SSL certificates"
	cd $tempdir
	openssl genrsa -out ${shib_ds_server}.key 2048 || { echo "Could not generate ${shib_ds_server}.key using OpenSSL.  Aborting..."; exit 27; }
	openssl req -new -nodes -subj "${shib_ds_ssl_subject}" -key ${shib_ds_server}.key -out ${shib_ds_server}.csr || { echo "Could not generate ${shib_ds_server}.csr using OpenSSL.  Aborting..."; exit 28; }
	openssl x509 -req -days 3650 -in ${shib_ds_server}.csr -signkey ${shib_ds_server}.key -out ${shib_ds_server}.crt || { echo "Could not generate ${shib_ds_server}.crt using OpenSSL.  Aborting..."; exit 29; }
	sudo cp ${shib_ds_server}.key /etc/ssl/private/ || { echo "Could not copy file ${shib_ds_server}.key to /etc/ssl/private/.  Aborting..."; exit 30; } 
	sudo cp ${shib_ds_server}.crt /etc/ssl/certs/ || { echo "Could not copy file ${shib_ds_server}.crt to /etc/ssl/certs/.  Aborting..."; exit 31; }
fi
 

echo "[`date +%H:%M:%S`] Setting up user authentication and configuring Tomcat"
if [ `grep "$etc_default_tomcat6" /etc/default/tomcat6 | wc -l` -lt 1 ]; then
	cat /etc/default/tomcat6 | grep -v "^JAVA_OPTS" > ${tempdir}/tomcat6 || { echo "Could not copy file /etc/default/tomcat6 to ${tempdir}.  Aborting..."; exit 32; }
	echo $etc_default_tomcat6 >> ${tempdir}/tomcat6 || { echo "Could not copy add additional configuration to ${tempdir}/tomcat6.  Aborting..."; exit 33; }
	sudo cp ${tempdir}/tomcat6 /etc/default/ || { echo "Could not copy file ${tempdir}/tomcat6 to /etc/default/.  Aborting..."; exit 34; }
	sudo cp ${tempdir}/server.xml /etc/tomcat6/ | { echo "Could not copy file ${tempdir}/server.xml to /etc/tomcat6/.  Aborting..."; exit 35; }
fi


if [ ! -f /etc/apache2/sites-enabled/${shib_ds_server} ]; then
	echo "[`date +%H:%M:%S`] Configuring Apache"
	cat /etc/apache2/conf.d/security | sed "s/ServerTokens OS/ServerTokens Prod/" > $tempdir/security || { echo "Could not copy a modified version of /etc/apache2/conf.d/security to ${tempdir}.  Aborting..."; exit 36; }
	sudo cp ${tempdir}/security /etc/apache2/conf.d/ || { echo "Could not copy file ${tempdir}/security to /etc/apache2/conf.d/.  Aborting..."; exit 37; }
	sudo cp ${tempdir}/${shib_ds_server}.ds /etc/apache2/sites-available/${shib_ds_server} || { echo "Could not copy file ${tempdir}/${shib_ds_server}.ds to /etc/apache2/sites-available/${shib_ds_server}.  Aborting..."; exit 38; }
	sudo a2ensite ${shib_ds_server}  || { echo "Could not enable site ${shib_ds_server} in Apache.  Aborting..."; exit 39; }
	sudo a2enmod ssl || { echo "Could not enable module ssl for Apache.  Aborting..."; exit 39; }
	sudo a2enmod proxy_ajp || { echo "Could not enable module proxy_ajp for Apache.  Aborting..."; exit 40; }
        if [ `grep "^NameVirtualHost \*:443" /etc/apache2/ports.conf | wc -l` -eq 0 ]; then
                cp /etc/apache2/ports.conf ${tempdir} || { echo "Could not copy file /etc/apache2/ports.conf to ${tempdir}.  Aborting..."; exit 41; }
                echo "NameVirtualHost *:443" >> ${tempdir}/ports.conf || { echo "Could not add 'NameVirtualHost *:443' to ${tempdir}/ports.conf.  Aborting..."; exit 42; }
                sudo cp ${tempdir}/ports.conf /etc/apache2/ || { echo "Could not copy modified ${tempdir}/ports.conf to /etc/apache2/.  Aborting..."; exit 43; }
        fi
elif [ "${shib_ds_server}" == "${shib_idp_server}" ]; then
	echo "[`date +%H:%M:%S`] Configuring Apache (on same host as Identity Provider)"
	cat /etc/apache2/sites-enabled/${shib_idp_server} | sed "s@^#ProxyPass /ds@ProxyPass /ds@" > ${tempdir}/${shib_idp_server} || { echo "Could not write modified /etc/apache2/sites-enabled/${shib_idp_server} to ${tempdir}.  Aborting..."; exit 57; }
        sudo cp ${tempdir}/${shib_idp_server} /etc/apache2/sites-enabled/ || { echo "Could not copy modified ${tempdir}/${shib_idp_server} to /etc/apache2/sites-enabled/.  Aborting..."; exit 58; }
fi


echo "[`date +%H:%M:%S`] Configuring Shibboleth Discovery Service"
cd ${shib_ds_home}
sudo chown -R tomcat6 logs metadata || { echo "Could not change owner of logs and metadata in ${shib_ds_home} to tomcat6.  Aborting..."; exit 44; }
sudo chgrp -R tomcat6 conf logs metadata war  || { echo "Could not change group of conf, logs, metadata and war in ${shib_ds_home} to tomcat6.  Aborting..."; exit 45; }
sudo chmod 750 war conf || { echo "Could not change permissions on war and conf in ${shib_ds_home} to tomcat 750.  Aborting..."; exit 46; }
sudo chmod 775 logs metadata || { echo "Could not change permissions on logs and metadata in ${shib_ds_home} to tomcat 775.  Aborting..."; exit 47; }
wget --no-check-certificate https://${shib_idp_server}/idp/profile/Metadata/SAML -O ${tempdir}/idp_site.xml || { echo "Could not retrieve metadata for ${shib_idp_server} Identity Provider.  Aborting..."; exit 48; }
if [ `cat ${tempdir}/idp_site.xml | head -n 1 | grep "^<?xml" | wc -l` -gt 0 ]; then 
	cat ${tempdir}/idp_site.xml | sed "s/^<?xml [^>]\+>//" >> ${tempdir}/sites.xml  || { echo "Could not copy modified metadata file for ${shib_idp_server} Identity Provider into ${tempdir}/sites.xml.  Aborting..."; exit 49; }
fi
echo -e "\n\n</EntitiesDescriptor>" >> ${tempdir}/sites.xml || { echo "Could not copy append closing EntitiesDescriptor tag to ${tempdir}/sites.xml.  Aborting..."; exit 50; }
sudo cp ${tempdir}/sites.xml ${shib_ds_home}/metadata/ || { echo "Could not copy ${tempdir}/sites.conf to ${shib_ds_home}/metadata/.  Aborting..."; exit 51; }
sudo ln -s ${shib_ds_home}/metadata/sites.xml /var/www/sites.xml || { echo "Could not create symlink /var/www/sites.xml -> ${shib_ds_home}/metadata/sites.xml.  Aborting..."; exit 52; }
sudo cp ${tempdir}/update-shibboleth-ds-metadata /etc/cron.daily/ || { echo "Could not copy ${tempdir}/update-shibboleth-ds-metadata to /etc/cron.daily/.  Aborting..."; exit 53; }
sudo chmod a+x /etc/cron.daily/update-shibboleth-ds-metadata || { echo "Could not make /etc/cron.daily/update-shibboleth-ds-metadata executable to all.  Aborting..."; exit 54; }

sudo service tomcat6 restart || { echo "Could not restart Tomcat.  Aborting..."; exit 55; }
echo "[`date +%H:%M:%S`] Sleeping for 30 seconds to allow Tomcat to initialise before restarting Apache."
sleep 30
sudo service apache2 restart || { echo "Could not restart Apache.  Aborting..."; exit 56; }

echo -e "\n\n[`date +%H:%M:%S`] Shibboleth Discovery Service installed successfully.  Goodbye.\n"
