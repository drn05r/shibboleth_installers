#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$1
source $basedir/settings.sh

JAVA_HOME=/usr/lib/jvm/java-6-openjdk

read -d '' etc_profile_1 <<"EOF"
JAVA_HOME=/usr/lib/jvm/java-6-openjdk
export JAVA_HOME
EOF

read -d '' etc_profile_2 <<"EOF"
IDP_HOME=/opt/shibboleth-idp
export IDP_HOME
EOF

read -d '' tomcat_server_xml_1 <<"EOF"
JAVA_OPTS="-Djava.awt.headless=true -Xmx512M -XX:MaxPermSize=128M -Dcom.sun.security.enableCRLDP=true"
EOF

read -d '' tomcat_server_xml_2 <<"EOF"
<!-- Define an AJP 1.3 Connector on port 8009 -->
    <Connector port="8009" address="127.0.0.1"
               enableLookups="false" redirectPort="443"
               protocol="AJP/1.3"
               tomcatAuthentication="false" />

  <!--  
    <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
  -->
EOF

read -d '' idp_xml <<"EOF"
<Context
    docBase="/opt/shibboleth-idp/war/idp.war"
    privileged="true"
    antiResourceLocking="false"
    antiJARLocking="false"
    unpackWAR="false"
    swallowOutput="true"
    cookies="false" />
EOF

read -d '' shib_idp_login_config <<"EOF"
ShibUserPassAuth {
    
// Example LDAP authentication
   edu.vt.middleware.ldap.jaas.LdapLoginModule required
      ldapUrl="${ldap_url}"
      baseDn="${ldap_base_dn}"
      bindDn="${ldap_bind_dn}"
      bindCredential="${ldap_admin_password}";
};
EOF

read -d '' apache_ports_config <<"EOF"
Listen 8443
EOF

cat <<EOF > $tempdir/expect.sh
#!/usr/bin/expect
spawn env IdpCertLifetime=3 JAVA_HOME=${JAVA_HOME} ./install.sh
expect "Buildfile: src/installer/resources/build.xml

install:
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Be sure you have read the installation/upgrade instructions on the Shibboleth website before proceeding.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Where should the Shibboleth Identity Provider software be installed? \[/opt/shibboleth-idp\]"
send "/opt/shibboleth-idp\r"
expect "What is the fully qualified hostname of the Shibboleth Identity Provider server? \[default: idp.example.org\]"
send "${server_for_ssl}\r"
expect "A keystore is about to be generated for you. Please enter a password that will be used to protect it."
send "${shib_idp_keystore_password}\r"
interact
EOF

cat <<EOF > $tempdir/mysql_setup.sql 
SET NAMES 'utf8';
SET CHARACTER SET utf8;
CHARSET utf8;
CREATE DATABASE IF NOT EXISTS shibboleth CHARACTER SET=utf8;
USE shibboleth;
CREATE TABLE IF NOT EXISTS shibpid (
  localEntity TEXT NOT NULL,
  peerEntity TEXT NOT NULL,
  principalName VARCHAR(255) NOT NULL DEFAULT '',
  localId VARCHAR(255) NOT NULL,
  persistentId VARCHAR(36) NOT NULL,
  peerProvidedId VARCHAR(255) DEFAULT NULL,
  creationDate timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
    ON UPDATE CURRENT_TIMESTAMP,
  deactivationDate TIMESTAMP NULL DEFAULT NULL,
  KEY persistentId (persistentId),
  KEY persistentId_2 (persistentId, deactivationDate),
  KEY localEntity (localEntity(16), peerEntity(16), localId),
  KEY localEntity_2 (localEntity(16), peerEntity(16),
    localId, deactivationDate)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
USE mysql;
INSERT INTO user (Host,User,Password,Select_priv,
 Insert_priv,Update_priv,Delete_priv,Create_tmp_table_priv,
 Lock_tables_priv,Execute_priv) VALUES 
  ('localhost','shibboleth',PASSWORD('$mysql_user_password'),
   'Y','Y','Y','Y','Y','Y','Y');
FLUSH PRIVILEGES;
GRANT ALL ON shibboleth.* TO 'shibboleth'@'localhost'
IDENTIFIED BY 'demo';
FLUSH PRIVILEGES;
EOF

cat <<EOF > ${tempdir}/${server_for_ssl}
ServerName ${server_for_ssl}
<VirtualHost _default_:443>
ServerName ${server_for_ssl}:443
ServerAdmin root@localhost

DocumentRoot /var/www

SSLEngine On
SSLCipherSuite HIGH:MEDIUM:!ADH
SSLProtocol all -SSLv2
SSLCertificateFile /etc/ssl/certs/${server_for_ssl}.crt
SSLCertificateKeyFile /etc/ssl/private/${server_for_ssl}.key
#SSLCertificateChainFile /etc/ssl/certs/qvsslica.crt.pem
    
<Proxy ajp://localhost:8009>
    Allow from all
</Proxy>
    
ProxyPass /idp ajp://localhost:8009/idp retry=5

BrowserMatch "MSIE [2-6]" \
             nokeepalive ssl-unclean-shutdown \
             downgrade-1.0 force-response-1.0
# MSIE 7 and newer should be able to use keepalive
BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown

</VirtualHost>
<VirtualHost _default_:8443>
ServerName ${server_for_ssl}:8443
ServerAdmin root@localhost

DocumentRoot /var/www

SSLEngine On
SSLCipherSuite HIGH:MEDIUM:!ADH
SSLProtocol all -SSLv2
SSLCertificateFile /opt/shibboleth-idp/credentials/idp.crt
SSLCertificateKeyFile /opt/shibboleth-idp/credentials/idp.key
SSLVerifyClient optional_no_ca
SSLVerifyDepth 10
    
<Proxy ajp://localhost:8009>
    Allow from all
</Proxy>
    
ProxyPass /idp ajp://localhost:8009/idp retry=5

BrowserMatch "MSIE [2-6]" \
             nokeepalive ssl-unclean-shutdown \
             downgrade-1.0 force-response-1.0
# MSIE 7 and newer should be able to use keepalive
BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown

</VirtualHost>
EOF

random_string_32=`cat /dev/urandom | base64 | tr -dc "[:alnum:]" | head -c32`

cat <<EOF > ${tempdir}/attribute-resolver.xml
<?xml version="1.0" encoding="UTF-8"?>

<resolver:AttributeResolver xmlns:resolver="urn:mace:shibboleth:2.0:resolver" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
                            xmlns:pc="urn:mace:shibboleth:2.0:resolver:pc" xmlns:ad="urn:mace:shibboleth:2.0:resolver:ad" 
                            xmlns:dc="urn:mace:shibboleth:2.0:resolver:dc" xmlns:enc="urn:mace:shibboleth:2.0:attribute:encoder" 
                            xmlns:sec="urn:mace:shibboleth:2.0:security" 
                            xsi:schemaLocation="urn:mace:shibboleth:2.0:resolver classpath:/schema/shibboleth-2.0-attribute-resolver.xsd
                                               urn:mace:shibboleth:2.0:resolver:pc classpath:/schema/shibboleth-2.0-attribute-resolver-pc.xsd
                                               urn:mace:shibboleth:2.0:resolver:ad classpath:/schema/shibboleth-2.0-attribute-resolver-ad.xsd
                                               urn:mace:shibboleth:2.0:resolver:dc classpath:/schema/shibboleth-2.0-attribute-resolver-dc.xsd
                                               urn:mace:shibboleth:2.0:attribute:encoder classpath:/schema/shibboleth-2.0-attribute-encoder.xsd
                                               urn:mace:shibboleth:2.0:security classpath:/schema/shibboleth-2.0-security.xsd">

    <!-- ========================================== -->
    <!--      Attribute Definitions                 -->
    <!-- ========================================== -->

    <resolver:AttributeDefinition xsi:type="ad:Simple" id="uid" sourceAttributeID="uid">
        <resolver:Dependency ref="myLDAP" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1String" name="urn:mace:dir:attribute-def:uid" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2String" name="urn:oid:0.9.2342.19200300.100.1.1" friendlyName="uid" />
    </resolver:AttributeDefinition>

    <resolver:AttributeDefinition xsi:type="ad:Simple" id="mail" sourceAttributeID="mail">
        <resolver:Dependency ref="myLDAP" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1String" name="urn:mace:dir:attribute-def:mail" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2String" name="urn:oid:0.9.2342.19200300.100.1.3" friendlyName="mail" />
    </resolver:AttributeDefinition>

    <resolver:AttributeDefinition xsi:type="ad:Simple" id="cn" sourceAttributeID="cn">
        <resolver:Dependency ref="myLDAP" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1String" name="urn:mace:dir:attribute-def:cn" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2String" name="urn:oid:2.5.4.3" friendlyName="cn" />
    </resolver:AttributeDefinition>

    <resolver:AttributeDefinition xsi:type="ad:Simple" id="sn" sourceAttributeID="sn">
        <resolver:Dependency ref="myLDAP" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1String" name="urn:mace:dir:attribute-def:sn" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2String" name="urn:oid:2.5.4.4" friendlyName="sn" />
    </resolver:AttributeDefinition>

    <resolver:AttributeDefinition xsi:type="ad:Simple" id="givenName" sourceAttributeID="givenName">
        <resolver:Dependency ref="myLDAP" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1String" name="urn:mace:dir:attribute-def:givenName" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2String" name="urn:oid:2.5.4.42" friendlyName="givenName" />
    </resolver:AttributeDefinition>

    <resolver:AttributeDefinition xsi:type="ad:Scoped" id="eduPersonPrincipalName" scope="${ldap_domain}" sourceAttributeID="uid">
        <resolver:Dependency ref="myLDAP" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1ScopedString" name="urn:mace:dir:attribute-def:eduPersonPrincipalName" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2ScopedString" name="urn:oid:1.3.6.1.4.1.5923.1.1.1.6" friendlyName="eduPersonPrincipalName" />
    </resolver:AttributeDefinition>

    <resolver:AttributeDefinition xsi:type="ad:Scoped" id="eduPersonScopedAffiliation" scope="{$ldap_domain}" sourceAttributeID="eduPersonAffiliation">
        <resolver:Dependency ref="myLDAP" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1ScopedString" name="urn:mace:dir:attribute-def:eduPersonScopedAffiliation" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2ScopedString" name="urn:oid:1.3.6.1.4.1.5923.1.1.1.9" friendlyName="eduPersonScopedAffiliation" />
    </resolver:AttributeDefinition>

    <resolver:AttributeDefinition id="transientId" xsi:type="ad:TransientId">
        <resolver:AttributeEncoder xsi:type="enc:SAML1StringNameIdentifier" nameFormat="urn:mace:shibboleth:1.0:nameIdentifier"/>
        <resolver:AttributeEncoder xsi:type="enc:SAML2StringNameID" nameFormat="urn:oasis:names:tc:SAML:2.0:nameid-format:transient"/>
    </resolver:AttributeDefinition>

    <!-- ========================================== -->
    <!--      Data Connectors                       -->
    <!-- ========================================== -->

   <resolver:DataConnector id="myLDAP" xsi:type="dc:LDAPDirectory" 
        ldapURL="ldap://${ldap_server}:389" 
        baseDN="${ldap_server}" 
        principal="${ldap_bind_dn}"
        principalCredential="${ldap_admin_password}">
        <dc:FilterTemplate>
            <![CDATA[
                (uid=\$requestContext.principalName)
            ]]>
        </dc:FilterTemplate>
    </resolver:DataConnector>

    <resolver:DataConnector xsi:type="dc:StoredId" 
                            id="StoredId"
                            sourceAttributeID="cn"
                            generatedAttributeID="StoredId"
                            salt="${random_string_32}" >
      <resolver:Dependency ref="cn" />
      <dc:ApplicationManagedConnection jdbcDriver="com.mysql.jdbc.Driver"
                                 jdbcURL="jdbc:mysql://localhost:3306/shibstoreid"
                                 jdbcUserName="shibboleth"
                                 jdbcPassword="${mysql_user_password}" />
    </resolver:DataConnector>

    <resolver:AttributeDefinition id="eduPersonTargetedID" xsi:type="ad:SAML2NameID" 
        nameIdFormat="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
        sourceAttributeID="StoredId">
        <resolver:Dependency ref="StoredId" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1XMLObject" name="urn:oid:1.3.6.1.4.1.5923.1.1.1.10" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2XMLObject" name="urn:oid:1.3.6.1.4.1.5923.1.1.1.10" friendlyName="eduPersonTargetedID" />
    </resolver:AttributeDefinition>

    <resolver:AttributeDefinition id="persistentId" xsi:type="ad:Simple" sourceAttributeID="StoredId">
        <resolver:Dependency ref="StoredId"/>
        <resolver:AttributeEncoder xsi:type="enc:SAML1StringNameIdentifier" nameFormat="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"/>
        <resolver:AttributeEncoder xsi:type="enc:SAML2StringNameID" nameFormat="urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"/>
    </resolver:AttributeDefinition>

    <!-- ========================================== -->
    <!--      Principal Connectors                  -->
    <!-- ========================================== -->
    <resolver:PrincipalConnector xsi:type="pc:Transient" id="shibTransient" nameIDFormat="urn:mace:shibboleth:1.0:nameIdentifier"/>
    <resolver:PrincipalConnector xsi:type="pc:Transient" id="saml1Unspec" nameIDFormat="urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"/>
    <resolver:PrincipalConnector xsi:type="pc:Transient" id="saml2Transient" nameIDFormat="urn:oasis:names:tc:SAML:2.0:nameid-format:transient"/>

</resolver:AttributeResolver>
EOF

cat <<EOF > ${tempdir}/organizational_units.ldif
dn: ou=Groups,${ldap_base_dn}
objectClass: organizationalUnit
ou: Groups

dn: ou=People,${ldap_base_dn}
objectClass: organizationalUnit
ou: People

dn: ou=Computers,${ldap_base_dn}
objectClass: organizationalUnit
ou: Computers
EOF

cat <<EOF > ${tempdir}/ldapscripts.conf
SERVER=${ldap_server}
BINDDN='${ldap_bind_dn}'
BINDPWDFILE="/etc/ldapscripts/ldapscripts.passwd"
SUFFIX='${ldap_base_dn}'
GSUFFIX='ou=Groups'
USUFFIX='ou=People'
MSUFFIX='ou=Computers'
GCLASS="posixGroup"
GIDSTART=10000
UIDSTART=10000
MIDSTART=10000
EOF

cat <<EOF > ${tempdir}/runtime.debian
LDAPSEARCHBIN=`which ldapsearch`
LDAPADDBIN=`which ldapadd`
LDAPDELETEBIN=`which ldapdelete`
LDAPMODIFYBIN=`which ldapmodify`
LDAPMODRDNBIN=`which ldapmodrdn`
LDAPPASSWDBIN=`which ldappasswd`
GETENTPWCMD="getent passwd"
GETENTGRCMD="getent group"
EOF
