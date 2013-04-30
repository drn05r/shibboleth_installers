#!/bin/bash
shib_idp_version="2.3.8"
server_for_ssl="host.domain"
ssl_subject="/C=COUNTRY/ST=STATE|PROVINCE|COUNTY/L=LOCALITY/O=ORGANISATION/CN=$server_for_ssl"
mysql_root_password="changeme"
mysql_user_password="changeme"
shib_idp_keystore_password="changeme"
ldap_server="localhost.localdomain"
ldap_domain="example.org"
ldap_url="ldaps://${ldap_server}"
ldap_base_dn="dc="`echo ${ldap_server} | sed 's/\./,dc=/g'`
ldap_admin_user="admin"
ldap_bind_dn="cn=${ldap_admin_user},${ldap_base_dn}"
ldap_admin_password="changeme"
