#!/bin/bash -e

(($#==1)) || {
  >&2 echo "usage: $0 ldap_container_id"
  exit 1
}

ldap_cid=$1
ldap_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $ldap_cid)
[[ X"$ldap_ip" == X"" ]] && ldap_ip=172.17.0.5

ldap_domain=
[[ X"$ldap_domain" == X"" ]] && ldap_domain=tony.wuersch.name

cid=
[[ X"$cid" == X"" ]] && cid=etcd
etcd_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $cid)
[[ X"$etcd_ip" == X"" ]] && etcd_ip=172.17.0.5

docker run \
  -t \
  --detach \
  --name elect_${ldap_cid} \
  -v "$PWD":/usr/src/myapp \
  -w /usr/src/myapp \
  awuersch/python:1.0 \
  python3 \
  ldap_elect.py \
  $ldap_ip \
  $ldap_domain \
  $etcd_ip
