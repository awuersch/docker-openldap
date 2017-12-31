#!/bin/bash

(($#==1)) || {
    >&2 echo "usage: $0 [ billy | sammy ]"
    exit 1
}

. ~/.ldapvars

USER=$1

SRC=./${USER}.ldif

[[ -f $SRC ]] || {
    >&2 echo "file not found: $SRC\nexiting"
    exit 1
}

B="${LDAP_DN}"
HOST=ldap.${LDAP_DOMAIN}

DN="$CONFIG_DN"
PW="$CONFIG_PASSWORD"
H="ldap://$HOST"
LDIF=/container/service/slapd/assets/test/${USER}.ldif

docker cp $SRC ds1:$LDIF
docker exec ds1 ldapadd -x -D "$DN" -w $PW -H "$H" -f $LDIF -ZZ
