#!/bin/bash -e

(($# == 0)) && {
  >&2 echo "usage: $0 container-id [container_id ...]"
  exit 1
}

. ~/.ldapvars

etcd_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' etcd)

ips=()
for cid in "$@"
do
  ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $cid)
  [[ X"$ip" == X"" ]] && {
    >&2 echo "invalid container-id $cid"
    exit 1
  }
  ips+=($ip)
done

DIR=~/home/docker/awuersch/python
DOMAIN=${DOMAIN:-$LDAP_DOMAIN}
BINDDN=${BINDDN:-$CONFIG_DN}
PASS=${PASS:-$CONFIG_PASSWORD}

docker run \
  -t \
  --detach \
  --name update_ref \
  -v "$DIR":/usr/src/myapp \
  -w /usr/src/myapp \
  awuersch/python:1.0 \
  python3 \
  ldap_update_ref.py "${DOMAIN}" $etcd_ip "${BINDDN}" "${PASS}" "${ips[@]}"
