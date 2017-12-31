#!/bin/bash -e

(($#==2)) || {
  >&2 echo "usage: $0 hostname-prefix [ billy | sammy ]"
  exit 1
}

HOSTNAME_PREFIX=$1
USER=$2

. ~/.ldapvars

HOST="$HOSTNAME_PREFIX.${LDAP_DOMAIN}"

DN="$CONFIG_DN"
PW="$CONFIG_PASSWORD"
B="uid=${USER},ou=people,ou=accounts,${LDAP_DN}"
H="ldap://$HOST"

set -x
ldapsearch \
  -x \
  -D "$DN" -w "$PW" \
  -b "$B" -s base \
  -H "$H" \
  "(objectclass=*)" \* + \
  -v -ZZ
