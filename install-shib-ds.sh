#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$(mktemp -d /tmp/shib-ds_installer.XXXXXXXXXX)
downloads_dir="$HOME/shibboleth_downloads"
if [ ! -f "${basedir}/settings.sh" ]; then
        echo "Cannot find ${basedir}/settings.sh.  Aborting..."
        exit 1;
fi
source ${basedir}/settings.sh
source ${basedir}/config.sh $tempdir
echo "+----------------------------------------+"
echo "| Shibboleth Discovery Service Installer |"
echo "+----------------------------------------+"
echo ""

echo "[`date +%H:%M:%S`] Installing Prerequisites"
sudo apt-get update
sudo apt-get install -y openssl ntp apache2 unzip expect

if [ `grep ${shib_ds_server} /etc/hosts | grep "^127.0.1.1" | wc -l` -eq 0 ]; then
        echo "[`date +%H:%M:%S`] Adding Shibboleth Discovery Service hostname to local hosts file."
        cat /etc/hosts | sed "s/^\(127.0.1.1.*\)$/\1 ${shib_ds_server}/g" > ${tempdir}/hosts
        sudo cp ${tempdir}/hosts /etc/
fi

if [ ! -f "${JAVA_HOME}/bin/java" ]; then
	echo "[`date +%H:%M:%S`] Installing Java"
	sudo apt-get install -y openjdk-6-jre-headless
	sudo cp $tempdir/java_home /etc/profile.d/
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


echo "[`date +%H:%M:%S`] Installing Shibboleth Discovery Service"
cd $tempdir
shib_ds_download_url="http://shibboleth.net/downloads/centralized-discovery-service/"
shib_ds_folder="shibboleth-discovery-service-${shib_ds_version}"
shib_ds_zip="${shib_ds_folder}-bin.zip"
shib_ds_download_zip_url="${shib_ds_download_url}${shib_ds_version}/${shib_ds_zip}"
if [ ! -f ${downloads_dir}/${shib_ds_zip} ]; then
	wget $shib_ds_download_zip_url -O ${downloads_dir}/${shib_ds_zip}
fi
cd $downloads_dir
if [ ! -d $shib_ds_folder ]; then 
	 unzip $shib_ds_zip
fi
sudo mv $shib_ds_folder /usr/local/src/ 
cd /usr/local/src/$shib_ds_folder
sudo chmod u+x install.sh
if [ ! -d /usr/share/tomcat6/endorsed/ ]; then
	sudo mkdir /usr/share/tomcat6/endorsed/
fi
sudo cp ./lib/endorsed/*.jar /usr/share/tomcat6/endorsed/
cd /usr/local/src/
sudo cp ${tempdir}/expect_ds.sh /usr/local/src/${shib_ds_folder}/
cd /usr/local/src/${shib_ds_folder}/
sudo chmod ug+x expect_ds.sh
sudo ./expect_ds.sh
sudo ln -s ${shib_ds_home}/logs /var/log/shibboleth-ds
echo "$etc_profile_3" > $tempdir/ds_home
sudo cp $tempdir/ds_home /etc/profile.d/
sudo cp $tempdir/ds.xml /etc/tomcat6/Catalina/localhost/
sudo chgrp tomcat6 /etc/tomcat6/Catalina/localhost/ds.xml

if [ ! -f /etc/ssl/certs/${shib_ds_server}.crt ]; then
	echo "[`date +%H:%M:%S`] Setting up SSL certificates"
	cd $tempdir
	openssl genrsa -out ${shib_ds_server}.key 2048
	openssl req -new -nodes -subj "${shib_ds_ssl_subject}" -key ${shib_ds_server}.key -out ${shib_ds_server}.csr
	openssl x509 -req -days 3650 -in ${shib_ds_server}.csr -signkey ${shib_ds_server}.key -out ${shib_ds_server}.crt
	sudo cp ${shib_ds_server}.key /etc/ssl/private/
	sudo cp ${shib_ds_server}.crt /etc/ssl/certs/
fi
 

echo "[`date +%H:%M:%S`] Setting up user authentication and configuring Tomcat"
if [ `grep "$etc_default_tomcat6" /etc/default/tomcat6 | wc -l` -lt 1 ]; then
	cat /etc/default/tomcat6 | grep -v "^JAVA_OPTS" > ${tempdir}/tomcat6
	echo $etc_default_tomcat6 >> ${tempdir}/tomcat6
	sudo cp ${tempdir}/tomcat6 /etc/default/
	sudo cp ${tempdir}/server.xml /etc/tomcat6/
fi


if [ ! -f /etc/apache2/sites-enabled/${shib_ds_server} ]; then
	echo "[`date +%H:%M:%S`] Configuring Apache"
	cat /etc/apache2/conf.d/security | sed "s/ServerTokens OS/ServerTokens Prod/" > $tempdir/security
	sudo cp ${tempdir}/security /etc/apache2/conf.d/
	sudo cp ${tempdir}/${shib_ds_server} /etc/apache2/sites-available/
	sudo a2ensite ${shib_ds_server}
	sudo a2enmod ssl
	sudo a2enmod proxy_ajp 
        if [ `grep "^NameVirtualHost \*:443" /etc/apache2/ports.conf | wc -l` -eq 0 ]; then
                cp /etc/apache2/ports.conf ${tempdir}
                echo "NameVirtualHost *:443" >> ${tempdir}/ports.conf
                sudo cp ${tempdir}/ports.conf /etc/apache2/
        fi
fi


echo "[`date +%H:%M:%S`] Configuring Shibboleth Discovery Service"
cd ${shib_ds_home}
sudo chown -R tomcat6 logs metadata  
sudo chgrp -R tomcat6 conf logs metadata war
sudo chmod 750 war conf
sudo chmod 775 logs metadata
wget --no-check-certificate https://${shib_idp_server}/idp/profile/Metadata/SAML -O ${tempdir}/idp_site.xml
if [ `cat ${tempdir}/idp_site.xml | head -n 1 | grep "^<?xml" | wc -l` -gt 0 ]; then 
	cat ${tempdir}/idp_site.xml | sed "s/^<?xml [^>]\+>//" >> ${tempdir}/sites.xml
fi
echo -e "\n\n</EntitiesDescriptor>" >> ${tempdir}/sites.xml
sudo cp ${tempdir}/sites.xml /opt/shibboleth-ds/metadata/
sudo ln -s /opt/shibboleth-ds/metadata/sites.xml /var/www/sites.xml

sudo service tomcat6 restart
echo "[`date +%H:%M:%S`] Sleeping for 30 seconds to allow Tomcat to initialise before restarting Apache."
sleep 30
sudo service apache2 restart

echo -e "\n\n[`date +%H:%M:%S`] Shibboleth Discovery Service installed successfully.  Goodbye.\n"
