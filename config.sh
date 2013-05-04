#!/bin/bash
d=`dirname $0`
basedir=`cd ${d}; pwd`
tempdir=$1
source $basedir/settings.sh

JAVA_HOME=/usr/lib/jvm/java-6-openjdk

cat <<EOF > $tempdir/java_home
JAVA_HOME=/usr/lib/jvm/java-6-openjdk
export JAVA_HOME
EOF

cat <<EOF > $tempdir/ds_home
DS_HOME=${shib_ds_home}
export IDP_HOME
EOF

cat <<EOF > $tempdir/idp_home
etc_profile_idp_home="IDP_HOME=${shib_idp_home}
export IDP_HOME
EOF

read -d '' etc_default_tomcat6 <<"EOF"
JAVA_OPTS="-Djava.awt.headless=true -Xmx512M -XX:MaxPermSize=128M -Dcom.sun.security.enableCRLDP=true"
EOF

cat <<EOF > $tempdir/ds.xml
<Context
    docBase="${shib_ds_home}/war/discovery.war"
    privileged="true"
    antiResourceLocking="false"
    antiJARLocking="false"
    unpackWAR="false" />
EOF

cat <<EOF > $tempdir/idp.xml
<Context
    docBase="${shib_idp_home}/war/idp.war"
    privileged="true"
    antiResourceLocking="false"
    antiJARLocking="false"
    unpackWAR="false"
    swallowOutput="true"
    cookies="false" />
EOF

cat <<EOF > $tempdir/login.config
ShibUserPassAuth { 
   edu.vt.middleware.ldap.jaas.LdapLoginModule required
     host="${ldap_server}"
     port="389"
     ssl="false"
     tls="false"
     base="${ldap_people_base_dn}"
     subtreeSearch="true"
     userField="uid"
     serviceUser="${ldap_bind_dn}"
     serviceCredential="${ldap_admin_password}";
};
EOF

handler_xml="    <ph:LoginHandler xsi:type=\"ph:UsernamePassword\" 
                  jaasConfigurationLocation=\"file://${shib_idp_home}/conf/login.config\">
        <ph:AuthenticationMethod>urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport</ph:AuthenticationMethod>
        <ph:AuthenticationMethod>urn:oasis:names:tc:SAML:2.0:ac:classes:unspecified</ph:AuthenticationMethod>
    </ph:LoginHandler>

</ph:ProfileHandlerGroup>"

read -d '' web_xml_allowed_ips <<"EOF"
<param-value>127.0.0.1/32 ::1/128</param-value>
EOF

cat <<EOF > $tempdir/expect_ds.sh
#!/usr/bin/expect
spawn env JAVA_HOME=${JAVA_HOME} ./install.sh
expect "Buildfile: src/installer/resources/build.xml

install:
Where should the Shibboleth Discovery Service software be installed? \[/opt/shibboleth-ds\]"
send "${shib_ds_home}\r"
interact
EOF

cat <<EOF > $tempdir/expect_ds2.sh
#!/usr/bin/expect
spawn env JAVA_HOME=${JAVA_HOME} ./install.sh
expect "Buildfile: src/installer/resources/build.xml

install:
Where should the Shibboleth Discovery Service software be installed? \[/opt/shibboleth-ds\]"
send "${shib_ds_home}\r"
expect "The directory '/opt/shibboleth-ds' already exists.  Would you like to overwrite your existing configuration? (yes, \[no\])"
send "no\r"
interact
EOF

cat <<EOF > $tempdir/expect_idp.sh
#!/usr/bin/expect
spawn env IdpCertLifetime=3 JAVA_HOME=${JAVA_HOME} ./install.sh
expect "Buildfile: src/installer/resources/build.xml

install:
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Be sure you have read the installation/upgrade instructions on the Shibboleth website before proceeding.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Where should the Shibboleth Identity Provider software be installed? \[/opt/shibboleth-idp\]"
send "${shib_idp_home}\r"
expect "What is the fully qualified hostname of the Shibboleth Identity Provider server? \[default: idp.example.org\]"
send "${shib_idp_server}\r"
expect "A keystore is about to be generated for you. Please enter a password that will be used to protect it."
send "${shib_idp_keystore_password}\r"
interact
EOF

cat <<EOF > $tempdir/expect_idp2.sh
#!/usr/bin/expect
spawn env IdpCertLifetime=3 JAVA_HOME=${JAVA_HOME} ./install.sh
expect "Buildfile: src/installer/resources/build.xml

install:
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Be sure you have read the installation/upgrade instructions on the Shibboleth website before proceeding.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Where should the Shibboleth Identity Provider software be installed? \[/opt/shibboleth-idp\]"
send "${shib_idp_home}\r"
expect "The directory '/opt/shibboleth-idp' already exists.  Would you like to overwrite this Shibboleth configuration? (yes, \[no\])"
send "no\r"
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
  ('localhost','shibboleth',PASSWORD('${mysql_user_password}'),
   'Y','Y','Y','Y','Y','Y','Y');
FLUSH PRIVILEGES;
GRANT ALL ON shibboleth.* TO 'shibboleth'@'localhost'
IDENTIFIED BY '${mysql_user_password}';
FLUSH PRIVILEGES;
EOF

cat <<EOF > ${tempdir}/${shib_idp_server}
ServerName ${shib_idp_server}
<VirtualHost _default_:443>
ServerName ${shib_idp_server}:443
ServerAdmin root@localhost

DocumentRoot /var/www

SSLEngine On
SSLCipherSuite HIGH:MEDIUM:!ADH
SSLProtocol all -SSLv2
SSLCertificateFile /etc/ssl/certs/${shib_idp_server}.crt
SSLCertificateKeyFile /etc/ssl/private/${shib_idp_server}.key
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
ServerName ${shib_idp_server}:8443
ServerAdmin root@localhost

DocumentRoot /var/www

SSLEngine On
SSLCipherSuite HIGH:MEDIUM:!ADH
SSLProtocol all -SSLv2
SSLCertificateFile ${shib_idp_home}/credentials/idp.crt
SSLCertificateKeyFile ${shib_idp_home}/credentials/idp.key
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

cat <<EOF > ${tempdir}/${shib_ds_server}
ServerName ${shib_ds_server}
<VirtualHost _default_:443>
ServerName ${shib_ds_server}:443
ServerAdmin root@localhost

DocumentRoot /var/www

SSLEngine On
SSLCipherSuite HIGH:MEDIUM:!ADH
SSLProtocol all -SSLv2
SSLCertificateFile /etc/ssl/certs/${shib_ds_server}.crt
SSLCertificateKeyFile /etc/ssl/private/${shib_ds_server}.key
#SSLCertificateChainFile /etc/ssl/certs/qvsslica.crt.pem
    
<Proxy ajp://localhost:8009>
    Allow from all
</Proxy>
    
ProxyPass /ds ajp://localhost:8009/ds retry=5

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

    <resolver:AttributeDefinition xsi:type="ad:Scoped" id="eduPersonScopedAffiliation" scope="${ldap_domain}" sourceAttributeID="eduPersonAffiliation">
        <resolver:Dependency ref="myLDAP" />
        <resolver:AttributeEncoder xsi:type="enc:SAML1ScopedString" name="urn:mace:dir:attribute-def:eduPersonScopedAffiliation" />
        <resolver:AttributeEncoder xsi:type="enc:SAML2ScopedString" name="urn:oid:1.3.6.1.4.1.5923.1.1.1.9" friendlyName="eduPersonScopedAffiliation" />
    </resolver:AttributeDefinition>

    <!-- ========================================== -->
    <!--      Data Connectors                       -->
    <!-- ========================================== -->

   <resolver:DataConnector id="myLDAP" xsi:type="dc:LDAPDirectory" 
        ldapURL="ldap://${ldap_server}:389" 
        baseDN="${ldap_people_base_dn}" 
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
                                         jdbcURL="jdbc:mysql://localhost:3306/shibboleth"
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

</resolver:AttributeResolver>
EOF

cat <<EOF > ${tempdir}/attribute-filter.xml
<?xml version="1.0" encoding="UTF-8"?>

<afp:AttributeFilterPolicyGroup id="ShibbolethFilterPolicy"
                                xmlns:afp="urn:mace:shibboleth:2.0:afp" xmlns:basic="urn:mace:shibboleth:2.0:afp:mf:basic" 
                                xmlns:saml="urn:mace:shibboleth:2.0:afp:mf:saml" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
                                xsi:schemaLocation="urn:mace:shibboleth:2.0:afp classpath:/schema/shibboleth-2.0-afp.xsd
                                                    urn:mace:shibboleth:2.0:afp:mf:basic classpath:/schema/shibboleth-2.0-afp-mf-basic.xsd
                                                    urn:mace:shibboleth:2.0:afp:mf:saml classpath:/schema/shibboleth-2.0-afp-mf-saml.xsd">

    <afp:AttributeFilterPolicy id="releaseTargetedIDToAnyone">
        <afp:PolicyRequirementRule xsi:type="basic:ANY" />
        <afp:AttributeRule attributeID="eduPersonTargetedID">
            <afp:PermitValueRule xsi:type="basic:ANY" />
        </afp:AttributeRule>
    </afp:AttributeFilterPolicy>

    <afp:AttributeFilterPolicy id="releaseLdapStuffToAnyone">
        <afp:PolicyRequirementRule xsi:type="basic:ANY" />
        <afp:AttributeRule attributeID="givenName">
            <afp:PermitValueRule xsi:type="basic:ANY" />
        </afp:AttributeRule>
        <afp:AttributeRule attributeID="sn">
            <afp:PermitValueRule xsi:type="basic:ANY" />
        </afp:AttributeRule>
        <afp:AttributeRule attributeID="cn">
            <afp:PermitValueRule xsi:type="basic:ANY" />
        </afp:AttributeRule>
        <afp:AttributeRule attributeID="organizationName">
            <afp:PermitValueRule xsi:type="basic:ANY" />
        </afp:AttributeRule>
        <afp:AttributeRule attributeID="mail">
                <afp:PermitValueRule xsi:type="basic:ANY" />
        </afp:AttributeRule>
        <afp:AttributeRule attributeID="eduPersonPrincipalName">
            <afp:PermitValueRule xsi:type="basic:ANY" />
        </afp:AttributeRule>
        <afp:AttributeRule attributeID="eduPersonScopedAffiliation">
            <afp:PermitValueRule xsi:type="basic:ANY" />
        </afp:AttributeRule>
    </afp:AttributeFilterPolicy>

</afp:AttributeFilterPolicyGroup>
EOF

cat <<EOF > ${tempdir}/relying-party.xml
<?xml version="1.0" encoding="UTF-8"?>

<rp:RelyingPartyGroup xmlns:rp="urn:mace:shibboleth:2.0:relying-party" xmlns:saml="urn:mace:shibboleth:2.0:relying-party:saml" 
                      xmlns:metadata="urn:mace:shibboleth:2.0:metadata" xmlns:resource="urn:mace:shibboleth:2.0:resource" 
                      xmlns:security="urn:mace:shibboleth:2.0:security" xmlns:samlsec="urn:mace:shibboleth:2.0:security:saml" 
                      xmlns:samlmd="urn:oasis:names:tc:SAML:2.0:metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
                      xsi:schemaLocation="urn:mace:shibboleth:2.0:relying-party classpath:/schema/shibboleth-2.0-relying-party.xsd
                                          urn:mace:shibboleth:2.0:relying-party:saml classpath:/schema/shibboleth-2.0-relying-party-saml.xsd
                                          urn:mace:shibboleth:2.0:metadata classpath:/schema/shibboleth-2.0-metadata.xsd
                                          urn:mace:shibboleth:2.0:resource classpath:/schema/shibboleth-2.0-resource.xsd 
                                          urn:mace:shibboleth:2.0:security classpath:/schema/shibboleth-2.0-security.xsd
                                          urn:mace:shibboleth:2.0:security:saml classpath:/schema/shibboleth-2.0-security-policy-saml.xsd
                                          urn:oasis:names:tc:SAML:2.0:metadata classpath:/schema/saml-schema-metadata-2.0.xsd">

    <!-- ========================================== -->
    <!--      Relying Party Configurations          -->
    <!-- ========================================== -->
    <rp:AnonymousRelyingParty provider="https://${shib_idp_server}/idp/shibboleth" defaultSigningCredentialRef="IdPCredential"/>

    <rp:DefaultRelyingParty provider="https://${shib_idp_server}/idp/shibboleth" defaultSigningCredentialRef="IdPCredential">
        <rp:ProfileConfiguration xsi:type="saml:ShibbolethSSOProfile" includeAttributeStatement="false" 
                                 assertionLifetime="PT5M" signResponses="conditional" signAssertions="never"/>
        <rp:ProfileConfiguration xsi:type="saml:SAML1AttributeQueryProfile" assertionLifetime="PT5M" 
                                 signResponses="conditional" signAssertions="never"/>
        <rp:ProfileConfiguration xsi:type="saml:SAML1ArtifactResolutionProfile" signResponses="conditional" 
                                 signAssertions="never"/>
        <rp:ProfileConfiguration xsi:type="saml:SAML2SSOProfile" includeAttributeStatement="true" 
                                 assertionLifetime="PT5M" assertionProxyCount="0" 
                                 signResponses="never" signAssertions="always" 
                                 encryptAssertions="conditional" encryptNameIds="never"/>
        <rp:ProfileConfiguration xsi:type="saml:SAML2ECPProfile" includeAttributeStatement="true" 
                                 assertionLifetime="PT5M" assertionProxyCount="0" 
                                 signResponses="never" signAssertions="always" 
                                 encryptAssertions="conditional" encryptNameIds="never"/>
        <rp:ProfileConfiguration xsi:type="saml:SAML2AttributeQueryProfile" 
                                 assertionLifetime="PT5M" assertionProxyCount="0" 
                                 signResponses="conditional" signAssertions="never" 
                                 encryptAssertions="conditional" encryptNameIds="never"/>
        <rp:ProfileConfiguration xsi:type="saml:SAML2ArtifactResolutionProfile" 
                                 signResponses="never" signAssertions="always" 
                                 encryptAssertions="conditional" encryptNameIds="never"/>
    </rp:DefaultRelyingParty>


    <!-- ========================================== -->
    <!--      Metadata Configuration                -->
    <!-- ========================================== -->
    <!-- MetadataProvider the combining other MetadataProviders -->
    <metadata:MetadataProvider id="ShibbolethMetadata" xsi:type="metadata:ChainingMetadataProvider">

        <!-- Load the IdP's own metadata.  This is necessary for artifact support. -->
        <metadata:MetadataProvider id="IdPMD" xsi:type="metadata:FilesystemMetadataProvider"
                                   metadataFile="/opt/shibboleth-idp/metadata/idp-metadata.xml"
                                   maxRefreshDelay="P1D" />


        <!-- Load metadata from Discovery Service. Uncomment once Discovery Service is installed. -->
        <!--
        <metadata:MetadataProvider id="URLMD" xsi:type="metadata:FileBackedHTTPMetadataProvider"
                          metadataURL="http://${shib_ds_server}/sites.xml"
                          backingFile="/opt/shibboleth-idp/metadata/sites-metadata.xml">
            <metadata:MetadataFilter xsi:type="metadata:ChainingFilter">
                <metadata:MetadataFilter xsi:type="metadata:RequiredValidUntil" 
                                maxValidityInterval="P3660D" />
                    <metadata:MetadataFilter xsi:type="metadata:EntityRoleWhiteList">
                    <metadata:RetainedRole>samlmd:SPSSODescriptor</metadata:RetainedRole>
                </metadata:MetadataFilter>
            </metadata:MetadataFilter>
        </metadata:MetadataProvider>
        -->

    </metadata:MetadataProvider>


    <!-- ========================================== -->
    <!--     Security Configurations                -->
    <!-- ========================================== -->
    <security:Credential id="IdPCredential" xsi:type="security:X509Filesystem">
        <security:PrivateKey>/opt/shibboleth-idp/credentials/idp.key</security:PrivateKey>
        <security:Certificate>/opt/shibboleth-idp/credentials/idp.crt</security:Certificate>
    </security:Credential>

    <!-- Trust engine used to evaluate the signature on loaded metadata.  (Not implemented for installer's discovery service) -->
    <!--
    <security:TrustEngine id="shibboleth.MetadataTrustEngine" xsi:type="security:StaticExplicitKeySignature">
        <security:Credential id="${shib_ds_server}" xsi:type="security:X509Filesystem">
            <security:Certificate>/opt/shibboleth-idp/credentials/${shib_ds_server}.crt</security:Certificate>
        </security:Credential>
    </security:TrustEngine>
     -->

    <!-- DO NOT EDIT BELOW THIS POINT -->
    <security:TrustEngine id="shibboleth.SignatureTrustEngine" xsi:type="security:SignatureChaining">
        <security:TrustEngine id="shibboleth.SignatureMetadataExplicitKeyTrustEngine" xsi:type="security:MetadataExplicitKeySignature" metadataProviderRef="ShibbolethMetadata"/>
        <security:TrustEngine id="shibboleth.SignatureMetadataPKIXTrustEngine" xsi:type="security:MetadataPKIXSignature" metadataProviderRef="ShibbolethMetadata"/>
    </security:TrustEngine>
    <security:TrustEngine id="shibboleth.CredentialTrustEngine" xsi:type="security:Chaining">
        <security:TrustEngine id="shibboleth.CredentialMetadataExplictKeyTrustEngine" xsi:type="security:MetadataExplicitKey" metadataProviderRef="ShibbolethMetadata"/>
        <security:TrustEngine id="shibboleth.CredentialMetadataPKIXTrustEngine" xsi:type="security:MetadataPKIXX509Credential" metadataProviderRef="ShibbolethMetadata"/>
    </security:TrustEngine>
    <security:SecurityPolicy id="shibboleth.ShibbolethSSOSecurityPolicy" xsi:type="security:SecurityPolicyType">
        <security:Rule xsi:type="samlsec:Replay" required="false"/>
        <security:Rule xsi:type="samlsec:IssueInstant" required="false"/>
        <security:Rule xsi:type="samlsec:MandatoryIssuer"/>
    </security:SecurityPolicy>
    <security:SecurityPolicy id="shibboleth.SAML1AttributeQuerySecurityPolicy" xsi:type="security:SecurityPolicyType">
        <security:Rule xsi:type="samlsec:Replay"/>
        <security:Rule xsi:type="samlsec:IssueInstant"/>
        <security:Rule xsi:type="samlsec:ProtocolWithXMLSignature" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="security:ClientCertAuth" trustEngineRef="shibboleth.CredentialTrustEngine"/>
        <security:Rule xsi:type="samlsec:MandatoryIssuer"/>
        <security:Rule xsi:type="security:MandatoryMessageAuthentication"/>
    </security:SecurityPolicy>
    <security:SecurityPolicy id="shibboleth.SAML1ArtifactResolutionSecurityPolicy" xsi:type="security:SecurityPolicyType">
        <security:Rule xsi:type="samlsec:Replay"/>
        <security:Rule xsi:type="samlsec:IssueInstant"/>
        <security:Rule xsi:type="samlsec:ProtocolWithXMLSignature" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="security:ClientCertAuth" trustEngineRef="shibboleth.CredentialTrustEngine"/>
        <security:Rule xsi:type="samlsec:MandatoryIssuer"/>
        <security:Rule xsi:type="security:MandatoryMessageAuthentication"/>
    </security:SecurityPolicy>
    <security:SecurityPolicy id="shibboleth.SAML2SSOSecurityPolicy" xsi:type="security:SecurityPolicyType">
        <security:Rule xsi:type="samlsec:Replay"/>
        <security:Rule xsi:type="samlsec:IssueInstant"/>
        <security:Rule xsi:type="samlsec:SAML2AuthnRequestsSigned"/>
        <security:Rule xsi:type="samlsec:ProtocolWithXMLSignature" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:SAML2HTTPRedirectSimpleSign" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:SAML2HTTPPostSimpleSign" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:MandatoryIssuer"/>
    </security:SecurityPolicy>
    <security:SecurityPolicy id="shibboleth.SAML2AttributeQuerySecurityPolicy" xsi:type="security:SecurityPolicyType">
        <security:Rule xsi:type="samlsec:Replay"/>
        <security:Rule xsi:type="samlsec:IssueInstant"/>
        <security:Rule xsi:type="samlsec:ProtocolWithXMLSignature" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:SAML2HTTPRedirectSimpleSign" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:SAML2HTTPPostSimpleSign" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="security:ClientCertAuth" trustEngineRef="shibboleth.CredentialTrustEngine"/>
        <security:Rule xsi:type="samlsec:MandatoryIssuer"/>
        <security:Rule xsi:type="security:MandatoryMessageAuthentication"/>
    </security:SecurityPolicy>
    <security:SecurityPolicy id="shibboleth.SAML2ArtifactResolutionSecurityPolicy" xsi:type="security:SecurityPolicyType">
        <security:Rule xsi:type="samlsec:Replay"/>
        <security:Rule xsi:type="samlsec:IssueInstant"/>
        <security:Rule xsi:type="samlsec:ProtocolWithXMLSignature" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:SAML2HTTPRedirectSimpleSign" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:SAML2HTTPPostSimpleSign" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="security:ClientCertAuth" trustEngineRef="shibboleth.CredentialTrustEngine"/>
        <security:Rule xsi:type="samlsec:MandatoryIssuer"/>
        <security:Rule xsi:type="security:MandatoryMessageAuthentication"/>
    </security:SecurityPolicy>
    <security:SecurityPolicy id="shibboleth.SAML2SLOSecurityPolicy" xsi:type="security:SecurityPolicyType">
        <security:Rule xsi:type="samlsec:Replay"/>
        <security:Rule xsi:type="samlsec:IssueInstant"/>
        <security:Rule xsi:type="samlsec:ProtocolWithXMLSignature" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:SAML2HTTPRedirectSimpleSign" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="samlsec:SAML2HTTPPostSimpleSign" trustEngineRef="shibboleth.SignatureTrustEngine"/>
        <security:Rule xsi:type="security:ClientCertAuth" trustEngineRef="shibboleth.CredentialTrustEngine"/>
        <security:Rule xsi:type="samlsec:MandatoryIssuer"/>
        <security:Rule xsi:type="security:MandatoryMessageAuthentication"/>
    </security:SecurityPolicy>
</rp:RelyingPartyGroup>
EOF

cat <<EOF > ${tempdir}/server.xml
<?xml version='1.0' encoding='utf-8'?>
<Server port="8005" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.core.JasperListener" />
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.ServerLifecycleListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <GlobalNamingResources>
    <Resource name="UserDatabase" auth="Container"
              type="org.apache.catalina.UserDatabase"
              description="User database that can be updated and saved"
              factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
              pathname="conf/tomcat-users.xml" />
  </GlobalNamingResources>
  <Service name="Catalina">
    <Connector port="8009" address="127.0.0.1"
               enableLookups="false" redirectPort="443"
               protocol="AJP/1.3"
               tomcatAuthentication="false" />
    <Engine name="Catalina" defaultHost="localhost">
      <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
             resourceName="UserDatabase"/>
      <Host name="localhost"  appBase="webapps"
            unpackWARs="true" autoDeploy="false"
            xmlValidation="false" xmlNamespaceAware="false">
      </Host>
    </Engine>
  </Service>
</Server>
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

datetime_10_years=`date +%Y-%m-%dT%H:%M:%SZ -ud "1970-01-01 + \`expr \\\`date +%s\\\` + \\\`expr 86400 \\\\* 3650\\\`\` seconds"`

cat <<EOF > ${tempdir}/sites.xml
<EntitiesDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" 
                    xmlns:ds="http://www.w3.org/2000/09/xmldsig#" 
                    xmlns:elab="http://eduserv.org.uk/labels" 
                    xmlns:idpdisc="urn:oasis:names:tc:SAML:profiles:SSO:idp-discovery-protocol" 
                    xmlns:init="urn:oasis:names:tc:SAML:profiles:SSO:request-init" 
                    xmlns:mdrpi="urn:oasis:names:tc:SAML:metadata:rpi" 
                    xmlns:mdui="urn:oasis:names:tc:SAML:metadata:ui" 
                    xmlns:shibmd="urn:mace:shibboleth:metadata:1.0" 
                    xmlns:wayf="http://sdss.ac.uk/2006/06/WAYF" 
                    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
                    ID="my20130501T155342Z" Name="http://${shib_ds_server}" 
                    validUntil="${datetime_10_years}">

EOF

