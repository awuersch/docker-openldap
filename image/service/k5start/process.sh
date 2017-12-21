#!/bin/bash -e

if [[ -f /etc/ldap/slapd.d/docker-openldap-is-ldap-consumer ]] ; then
  PRINCIPAL=ldapsync/admin
else
  PRINCIPAL=ldapadm/admin
fi

exec /usr/bin/k5start \
  -a \
  -p /var/run/k5start/k5start.pid \
  -f /etc/krb5.keytab \
  -K 60 \
  -k /tmp/krb5cc_$(id -u openldap) \
  -o openldap -g openldap -m 600 \
  -v \
  -r TONY.WUERSCH.NAME \
  "${PRINCIPAL}"
