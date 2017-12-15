#!/bin/bash -e

if [[ -f /etc/ldap/slapd.d/docker-openldap-is-ldap-consumer ]] ; then
  PRINCIPAL="$LDAP_READONLY_USER_USERNAME"
else
  PRINCIPAL=ldap/admin
fi

UID=$(id -u openldap)

exec /usr/bin/k5start \
  -a \
  -p /var/run/k5start/k5start.pid \
  -f /etc/krb5.keytab \
  -K 60 \
  -k /tmp/krb5cc_$UID \
  -o openldap -g openldap -m 600 \
  -v \
  -r TONY.WUERSCH.NAME \
  "${PRINCIPAL}"
