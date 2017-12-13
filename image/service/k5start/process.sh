#!/bin/bash -e

exec /usr/bin/k5start \
  -a \
  -p /var/run/k5start/k5start.pid \
  -f /etc/krb5.keytab \
  -K 60 \
  -k /tmp/krb5cc_1000 \
  -o openldap -g openldap -m 600 \
  -v \
  -r TONY.WUERSCH.NAME \
  ldap/admin
