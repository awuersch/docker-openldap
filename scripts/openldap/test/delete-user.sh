#!/bin/bash -e

(($#==2)) || {
  >&2 echo "usage: $0 hostname-prefix [ billy | sammy ]"
  exit 1
}

. ~/.ldapvars

HOSTNAME_PREFIX=$1
USER=$1

HOST="$HOSTNAME_PREFIX.tony.wuersch.name"

DN="cn=admin,${LDAP_DN}"
PW="${ADMIN_PASSWORD}"
B="uid=${USER},ou=people,${LDAP_DN}"
H="ldap://$HOST"

set -x
ldapdelete \
  -x \
  -D "$DN" -w "$PW" \
  -v -ZZ \
  $B
