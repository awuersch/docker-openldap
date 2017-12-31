#!/bin/bash -e

. ~/.ldapvars

# run 4 ldap containers
DIR=~/home/docker/awuersch/openldap
$DIR/run-openldap-provider-mirror.sh ds1 ldap1
sleep 2
$DIR/run-openldap-consumer.sh rs1 replica1 ldap://ldap1.${LDAP_DOMAIN} 0
sleep 2
$DIR/run-openldap-provider-mirror.sh ds2 ldap2
sleep 2
$DIR/run-openldap-consumer.sh rs2 replica2 ldap://ldap2.${LDAP_DOMAIN} 0
sleep 2
$DIR/run-openldap-provider-mirror.sh ds3 ldap3
sleep 2
$DIR/run-openldap-consumer.sh rs3 replica3 ldap://ldap3.${LDAP_DOMAIN} 0
sleep 2

CERTS_ROOT=/home/tony/home/docker/awuersch/openldap/certs
rm -rf $CERTS_ROOT

CA_FILE=/container/service/:ssl-tools/assets/default-ca/default-ca.pem
CERTS_DIR=/container/service/slapd/assets/certs

function c_ip { # container
  docker inspect -f "{{ .NetworkSettings.IPAddress }}" $1
}

ip_a=("$(c_ip ds1)" "$(c_ip ds2)" "$(c_ip ds3)")
ldap_a=(ldap1 ldap2 ldap3)
ds_a=(ds1 ds2 ds3)
dom=tony.wuersch.name

for cn in ds1 ds2 ds3 rs1 rs2 rs3
do
  # sub /etc/hosts for a DNS
  docker exec $cn bash -c "echo '# added hosts' >> /etc/hosts"
  for ((i=0; i< ${#ip_a[@]}; i++))
  do
    typeset ip=${ip_a[$i]} ldap=${ldap_a[$i]} ds=${ds_a[$i]}
    [[ "$cn" == "$ds" ]] || \
    docker exec $cn bash -c "echo $ip $ldap.$dom $ldap >> /etc/hosts"
  done

  # save certs for reference
  D=$CERTS_ROOT/$cn
  mkdir -p $D
  docker cp $cn:$CA_FILE $D/ca.crt
  for f in ldap.crt ldap.key dhparam.pem README.md
  do
    docker cp $cn:$CERTS_DIR/$f $D/$f
  done
done
