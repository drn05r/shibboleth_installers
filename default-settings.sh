#!/bin/bash
shib_idp_version="2.3.8"
shib_idp_home="/opt/shibboleth-idp"
shib_idp_server="shib-idp.example.org"
shib_idp_ssl_subject="/C=US/ST=STATE/L=LOCALITY/O=ORGANIZATION/OU=ORGANIZATIONUNIT/CN=$shib_idp_server"
shib_idp_keystore_password="changeme"
shib_ds_version="1.2.1"
shib_ds_home="/opt/shibboleth-ds"
shib_ds_server="shib-ds.example.org"
shib_ds_ssl_subject="/C=US/ST=STATE/L=LOCALITY/O=ORGANIZATION/OU=ORGANIZATIONUNIT/CN=$shib_ds_server"
allowed_ips="192.168.0.0/16"
mysql_jdbc_version="5.1.24"
mysql_root_password="changeme"
mysql_user_password="changeme"
ldap_server="localhost"
ldap_domain="example.org"
ldap_base_dn="dc="`echo ${ldap_server} | sed 's/\./,dc=/g'`
ldap_people_base_dn="ou=People,${ldap_base_dn}"
ldap_admin_user="admin"
ldap_bind_dn="cn=${ldap_admin_user},${ldap_base_dn}"
ldap_admin_password="changeme"
