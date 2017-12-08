#!/bin/bash -e

(($#==4)) || {
  >&2 echo "usage: $0 container-name hostname-prefix provider-host rid"
  exit 1
}

NAME=$1
HOSTNAME_PREFIX=$2
PROVIDER_HOST=$3
RID=$4

. ~/.ldapvars

BASEDIR="${BASEDIR:-/home/tony/home/docker/awuersch/openldap}"
LDAP_ORGANISATION="${LDAP_ORGANIZATION:-Anthony Wuersch, Consultant}"
# LDAP_DOMAIN=< in .ldapvars >
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-$ADMIN_PASSWORD}"
LDAP_CONFIG_PASSWORD="${LDAP_CONFIG_PASSWORD:-$CONFIG_PASSWORD}"
LDAP_READONLY_USER_USERNAME="${LDAP_READONLY_USER_USERNAME:-$READONLY_USERNAME}"
LDAP_READONLY_USER_PASSWORD="${LDAP_READONLY_USER_PASSWORD:-$READONLY_PASSWORD}"
KRB5_VOLUME=/home/tony/home/stretch/etc/krb5
KRB5_TARGET=/etc/krb5
CERT_VOLUME="${CERT_VOLUME:-$BASEDIR/data/slapd/certs/$HOSTNAME_PREFIX}"
CERT_TARGET="${CERT_TARGET:-/container/service/slapd/assets/certs}"

# --env LDAP_REMOVE_CONFIG_AFTER_SETUP=false \
# --loglevel debug \
# --keep-startup-env
# --mount type=bind,source=$CERT_VOLUME,target=$CERT_TARGET \
# --mount type=bind,source=$KRB5_VOLUME,target=$KRB5_TARGET \
# --env LDAP_TLS_CRT_FILENAME=ds1.crt \
# --env LDAP_TLS_KEY_FILENAME=ds1.key \
# --env LDAP_TLS_CA_CRT_FILENAME=chain.crt \

docker run \
  --privileged \
  --name $NAME \
  --hostname "$HOSTNAME_PREFIX.$LDAP_DOMAIN" \
  --env LDAP_ORGANISATION="$LDAP_ORGANISATION" \
  --env LDAP_DOMAIN="$LDAP_DOMAIN" \
  --env LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD" \
  --env LDAP_CONFIG_PASSWORD="$LDAP_CONFIG_PASSWORD" \
  --env LDAP_READONLY_USER_USERNAME="$LDAP_READONLY_USER_USERNAME" \
  --env LDAP_READONLY_USER_PASSWORD="$LDAP_READONLY_USER_PASSWORD" \
  --env LDAP_CONSUMER=true \
  --env LDAP_PROVIDER_HOST="$PROVIDER_HOST" \
  --env LDAP_RID="$RID" \
  --mount type=bind,source=$KRB5_VOLUME,target=$KRB5_TARGET \
  --detach awuersch/openldap:1.2.0-tony
