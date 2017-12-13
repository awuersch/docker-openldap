#!/bin/bash -e
set -o pipefail

# set -x (bash debug) if log level is trace
# https://github.com/osixia/docker-light-baseimage/blob/stable/image/tool/log-helper
log-helper level eq trace && set -x

# Reduce maximum number of number of open file descriptors to 1024
# otherwise slapd consumes two orders of magnitude more of RAM
# see https://github.com/docker/docker/issues/8231
ulimit -n 1024

[[ -d /etc/krb5 ]] && {
    cp /etc/krb5/krb5.conf /etc/krb5/krb5.keytab /etc
    chown openldap:openldap /etc/krb5.keytab
}

mkdir -p /var/run/k5start
