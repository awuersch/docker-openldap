#!/bin/bash -e

. ~/.ldapvars

# LDAP_DOMAIN= < in .ldapvars >
# LDAP_DN= < in .ldapvars >
# ADMIN_USERNAME= < in .ldapvars >
# ADMIN_PASSWORD= < in .ldapvars >
# CONFIG_USERNAME= < in .ldapvars >
# CONFIG_PASSWORD= < in .ldapvars >

function searchcsn { # arg ...
  ldapsearch -x -LLL "$@" -s base contextCSN entryCSN
}

echo 'ldap admin'
searchcsn -H ldap://ldap."$LDAP_DOMAIN" -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -b "$LDAP_DN"

echo 'ldap2 admin'
searchcsn -H ldap://ldap2."$LDAP_DOMAIN" -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -b "$LDAP_DN"

echo 'ldap3 admin'
searchcsn -H ldap://ldap3."$LDAP_DOMAIN" -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -b "$LDAP_DN"

echo 'replica admin'
searchcsn -H ldap://replica."$LDAP_DOMAIN" -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -b "$LDAP_DN"

echo 'replica2 admin'
searchcsn -H ldap://replica2."$LDAP_DOMAIN" -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -b "$LDAP_DN"

echo 'replica3 admin'
searchcsn -H ldap://replica3."$LDAP_DOMAIN" -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -b "$LDAP_DN"

BASE="cn=config"

echo 'ldap config'
searchcsn -H ldap://ldap."$LDAP_DOMAIN" -D "$CONFIG_DN" -w "$CONFIG_PASSWORD" -b "$BASE"

echo 'ldap2 config'
searchcsn -H ldap://ldap2."$LDAP_DOMAIN" -D "$CONFIG_DN" -w "$CONFIG_PASSWORD" -b "$BASE"

echo 'ldap3 config'
searchcsn -H ldap://ldap3."$LDAP_DOMAIN" -D "$CONFIG_DN" -w "$CONFIG_PASSWORD" -b "$BASE"

BASE="olcDatabase={2}mdb,cn=config"

echo 'ldap accesslog'
searchcsn -H ldap://ldap."$LDAP_DOMAIN" -D "$CONFIG_DN" -w "$CONFIG_PASSWORD" -b "$BASE"

echo 'ldap2 accesslog'
searchcsn -H ldap://ldap2."$LDAP_DOMAIN" -D "$CONFIG_DN" -w "$CONFIG_PASSWORD" -b "$BASE"

echo 'ldap3 accesslog'
searchcsn -H ldap://ldap3."$LDAP_DOMAIN" -D "$CONFIG_DN" -w "$CONFIG_PASSWORD" -b "$BASE"
