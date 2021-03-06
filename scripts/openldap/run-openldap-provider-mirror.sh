#!/bin/bash

(($#==2)) || {
  >&2 echo "usage: $0 container-name hostname-prefix"
  exit 1
}

NAME=$1
HOSTNAME_PREFIX=$2

. ~/.ldapvars

BASEDIR=${BASEDIR:-/home/tony/home/docker/awuersch/openldap}
LDAP_ORGANISATION="${LDAP_ORGANIZATION:-Anthony Wuersch, Consultant}"
# LDAP_DOMAIN= < in .ldapvars >
# LDAP_REALM= < in .ldapvars >
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-$ADMIN_PASSWORD}"
LDAP_CONFIG_PASSWORD="${LDAP_CONFIG_PASSWORD:-$CONFIG_PASSWORD}"
LDAP_READONLY_USER_USERNAME="${LDAP_READONLY_USER_USERNAME:-$READONLY_USERNAME}"
LDAP_READONLY_USER_PASSWORD="${LDAP_READONLY_USER_PASSWORD:-$READONLY_PASSWORD}"
KRB5_VOLUME=/home/tony/home/stretch/etc/krb5
KRB5_TARGET=/etc/krb5
CERT_VOLUME="${CERT_VOLUME:-$BASEDIR/data/slapd/certs/$HOSTNAME_PREFIX}"
CERT_TARGET="${CERT_TARGET:-/container/service/slapd/assets/certs}"

# --privileged \
# --mount type=bind,source=$CERT_VOLUME,target=$CERT_TARGET \
# --mount type=bind,source=$KRB5_VOLUME,target=$KRB5_TARGET \
# --mount type=bind,source=$KRB5KDC_VOLUME,target=$KRB5KDC_TARGET \
# --mount type=bind,source=$KRB5ADM_VOLUME,target=$KRB5ADM_TARGET \
# --env LDAP_REMOVE_CONFIG_AFTER_SETUP=false \
# --env LDAP_TLS_CRT_FILENAME=ds1.crt \
# --env LDAP_TLS_KEY_FILENAME=ds1.key \
# --env LDAP_TLS_CA_CRT_FILENAME=chain.crt \
# --loglevel debug \
# --keep-startup-env

# --env LDAP_READONLY_USER=false \
# --env LDAP_AUTHENTICATION=simple \
# --env LDAP_REPLICATION=false \
# --env LDAP_PROVIDER=false \


docker run \
  --name $NAME \
  --hostname "$HOSTNAME_PREFIX.$LDAP_DOMAIN" \
  --env LDAP_ORGANISATION="$LDAP_ORGANISATION" \
  --env LDAP_DOMAIN="$LDAP_DOMAIN" \
  --env LDAP_REALM="$LDAP_REALM" \
  --env LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD" \
  --env LDAP_CONFIG_PASSWORD="$LDAP_CONFIG_PASSWORD" \
  --env LDAP_READONLY_USER_USERNAME="$LDAP_READONLY_USER_USERNAME" \
  --env LDAP_READONLY_USER_PASSWORD="$LDAP_READONLY_USER_PASSWORD" \
  --env LDAP_READONLY_USER=true \
  --env LDAP_AUTHENTICATION=sasl \
  --env LDAP_REPLICATION=true \
  --env LDAP_PROVIDER=true \
  --env LDAP_KDC=true \
  --env LDAP_KDC_REALM=$LDAP_KDC_REALM \
  --env LDAP_KDC_KDC_USER_USERNAME=$LDAP_KDC_KDC_USER_USERNAME \
  --env LDAP_KDC_ADM_USER_USERNAME=$LDAP_KDC_ADM_USER_USERNAME \
  --env LDAP_KDC_KDC_USER_PASSWORD=$LDAP_KDC_KDC_USER_PASSWORD \
  --env LDAP_KDC_ADM_USER_PASSWORD=$LDAP_KDC_ADM_USER_PASSWORD \
  --env LDAP_REMOVE_CONFIG_AFTER_SETUP=false \
  --mount type=bind,source=$KRB5_VOLUME,target=$KRB5_TARGET \
  --detach awuersch/openldap:1.2.0-tony \
  --loglevel debug \
  --keep-startup-env
