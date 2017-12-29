#!/bin/bash -e
set -o pipefail

# set -x (bash debug) if log level is trace
# https://github.com/osixia/docker-light-baseimage/blob/stable/image/tool/log-helper
log-helper level eq trace && set -x

# Reduce maximum number of number of open file descriptors to 1024
# otherwise slapd consumes two orders of magnitude more of RAM
# see https://github.com/docker/docker/issues/8231
ulimit -n 1024

# create dir if they not already exists
[ -d /var/lib/ldap ] || mkdir -p /var/lib/ldap
[ -d /etc/ldap/slapd.d ] || mkdir -p /etc/ldap/slapd.d

# fix file permissions
chown -R openldap:openldap /var/lib/ldap
chown -R openldap:openldap /etc/ldap
chown -R openldap:openldap ${CONTAINER_SERVICE_DIR}/slapd

FIRST_START_DONE="${CONTAINER_STATE_DIR}/slapd-first-start-done"
WAS_STARTED_WITH_TLS="/etc/ldap/slapd.d/docker-openldap-was-started-with-tls"
WAS_STARTED_WITH_TLS_ENFORCE="/etc/ldap/slapd.d/docker-openldap-was-started-with-tls-enforce"
WAS_STARTED_WITH_REPLICATION="/etc/ldap/slapd.d/docker-openldap-was-started-with-replication"
WAS_STARTED_WITH_AUTHENTICATION="/etc/ldap/slapd.d/docker-openldap-was-started-with-authentication"
IS_LDAP_CONSUMER="/etc/ldap/slapd.d/docker-openldap-is-ldap-consumer"

ASSETS_DIR="${CONTAINER_SERVICE_DIR}/slapd/assets"
CERTS_DIR="$ASSETS_DIR/certs"

LDAP_TLS_CA_CRT_PATH="${CERTS_DIR}/$LDAP_TLS_CA_CRT_FILENAME"
LDAP_TLS_CRT_PATH="${CERTS_DIR}/$LDAP_TLS_CRT_FILENAME"
LDAP_TLS_KEY_PATH="${CERTS_DIR}/$LDAP_TLS_KEY_FILENAME"
LDAP_TLS_DH_PARAM_PATH="${CERTS_DIR}/dhparam.pem"

# CONTAINER_SERVICE_DIR and CONTAINER_STATE_DIR variables are set by
# the baseimage run tool more info : https://github.com/osixia/docker-light-baseimage

# container first start
if [ ! -e "$FIRST_START_DONE" ]; then

  #
  # Helpers
  #
  function is_new_schema() {
    local COUNT=$(ldapsearch -Q -Y EXTERNAL -H ldapi:/// -b cn=schema,cn=config cn | grep -c $1)
    if [ "$COUNT" -eq 0 ]; then
      echo 1
    else
      echo 0
    fi
  }

  function get_ldap_base_dn() {
    # if LDAP_BASE_DN is empty set value from LDAP_DOMAIN
    if [ -z "$LDAP_BASE_DN" ]; then
      IFS='.' read -ra LDAP_BASE_DN_TABLE <<< "$LDAP_DOMAIN"
      for i in "${LDAP_BASE_DN_TABLE[@]}"; do
        EXT="dc=$i,"
        LDAP_BASE_DN=$LDAP_BASE_DN$EXT
      done
      LDAP_BASE_DN=${LDAP_BASE_DN::-1}
    fi
  }

  get_ldap_base_dn

  function lhd() {
    log-helper debug
  }

  if [[ X"$LDAP_AUTHENTICATION" == X"simple" ]] ; then
    LDAP_DB_ROOT_DN="cn=admin,$LDAP_BASE_DN"
    LDAP_DB_ROOT_PW="$LDAP_ADMIN_PASSWORD"
  elif [[ X"$LDAP_AUTHENTICATION" == X"sasl" ]] ; then
    LDAP_DB_ROOT_DN="cn=admin,cn=config"
    LDAP_DB_ROOT_PW="$LDAP_CONFIG_PASSWORD"
  fi

  function ldap_add_or_modify() { # LDIF_FILE
    local LDIF_FILE=$1
    local a=(-Y EXTERNAL -Q -H ldapi:/// -f $LDIF_FILE)
    local b=(-h localhost -p 389
      -D $LDAP_DB_ROOT_DN -w $LDAP_DB_ROOT_PW
      -f $LDIF_FILE)
    sed -i -e "{
      s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g
      s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g
    }" $LDIF_FILE
    if [ X"${LDAP_READONLY_USER,,}" == X"true" ]; then
      sed -i -e "{
        s|{{ LDAP_READONLY_USER_USERNAME }}|${LDAP_READONLY_USER_USERNAME}|g
        s|{{ LDAP_READONLY_USER_PASSWORD_ENCRYPTED }}|${LDAP_READONLY_USER_PASSWORD_ENCRYPTED}|g
      }" $LDIF_FILE
    fi
    if grep -iq changetype $LDIF_FILE ; then
      ldapmodify "${a[@]}" |& lhd || ldapmodify "${b[@]}" |& lhd
    else
      ldapadd "${a[@]}" |& lhd || ldapadd "${b[@]}" |& lhd
    fi
  }

  BOOTSTRAP_DIR=${ASSETS_DIR}/config/bootstrap
  SCHEMA_DIR=${BOOTSTRAP_DIR}/schema
  LDIF_DIR=${BOOTSTRAP_DIR}/ldif
  CUSTOM_DIR=${BOOTSTRAP_DIR}/custom

  #
  # Global variables
  #
  BOOTSTRAP=false

  #
  # database and config directory are empty
  # setup bootstrap config - Part 1
  #
  if [ -z "$(ls -A -I lost+found -I .rmtab -I .gitignore /var/lib/ldap)" ] && \
     [ -z "$(ls -A -I lost+found -I .rmtab -I .gitignore /etc/ldap/slapd.d)" ]; then

    BOOTSTRAP=true

    log-helper info "Database and config directory are empty..."
    log-helper info "Init new ldap server..."

    cat <<EOF | debconf-set-selections
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORGANISATION}
slapd slapd/backend string ${LDAP_BACKEND^^}
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
slapd slapd/dump_database select when needed
EOF

    dpkg-reconfigure -f noninteractive slapd

    # RFC2307bis schema
    if [ "${LDAP_RFC2307BIS_SCHEMA,,}" == "true" ]; then

      log-helper info "Switching schema to RFC2307bis..."
      cp ${SCHEMA_DIR}/rfc2307bis.* /etc/ldap/schema/

      rm -f /etc/ldap/slapd.d/cn=config/cn=schema/*

      mkdir -p /tmp/schema
      slaptest -f ${SCHEMA_DIR}/rfc2307bis.conf -F /tmp/schema
      mv /tmp/schema/cn=config/cn=schema/* /etc/ldap/slapd.d/cn=config/cn=schema
      rm -r /tmp/schema

      chown -R openldap:openldap /etc/ldap/slapd.d/cn=config/cn=schema
    fi

    rm ${SCHEMA_DIR}/rfc2307bis.*

    # copy kerberos config
    for suffix in conf keytab
    do
      f=krb5.$suffix
      [[ -f /etc/krb5/$f ]] && cp /etc/krb5/$f /etc/$f
    done

    F=/etc/krb5.conf
    [[ -f $F ]] && sed -i -e "{
      s|{{ LDAP_DOMAIN }}|${LDAP_DOMAIN}|g
      s|{{ LDAP_REALM }}|${LDAP_REALM}|g
    }" $F

    # fix permissions on keytab
    chown openldap:openldap /etc/krb5.keytab
  #
  # Error: the database directory (/var/lib/ldap) is empty but not the config directory (/etc/ldap/slapd.d)
  #
  elif [ -z "$(ls -A -I lost+found -I .rmtab /var/lib/ldap)" ] && [ ! -z "$(ls -A -I lost+found -I .rmtab /etc/ldap/slapd.d)" ]; then
    log-helper error "Error: the database directory (/var/lib/ldap) is empty but not the config directory (/etc/ldap/slapd.d)"
    exit 1

  #
  # Error: the config directory (/etc/ldap/slapd.d) is empty but not the database directory (/var/lib/ldap)
  #
  elif [ ! -z "$(ls -A -I lost+found -I .rmtab /var/lib/ldap)" ] && [ -z "$(ls -A -I lost+found -I .rmtab /etc/ldap/slapd.d)" ]; then
    log-helper error "Error: the config directory (/etc/ldap/slapd.d) is empty but not the database directory (/var/lib/ldap)"
    exit 1
  fi

  # set authentication
  if [[ X"$LDAP_AUTHENTICATION" != X"simple" && X"$LDAP_AUTHENTICATION" != X"sasl" ]]; then
    log-helper error "Error: authentication must be simple or sasl"
    exit 1
  else
    echo "export LDAP_AUTHENTICATION=$LDAP_AUTHENTICATION" > $WAS_STARTED_WITH_AUTHENTICATION
  fi

  [[ X"$LDAP_CONSUMER" == X"true" ]] && touch $IS_LDAP_CONSUMER

  if [ "${KEEP_EXISTING_CONFIG,,}" == "true" ]; then
    log-helper info "/!\ KEEP_EXISTING_CONFIG = true configration will not be updated"
  else
    #
    # start OpenLDAP
    #

    # get previous hostname if OpenLDAP was started with replication
    # to avoid configuration pbs
    PREVIOUS_HOSTNAME_PARAM=""
    if [ -e "$WAS_STARTED_WITH_REPLICATION" ]; then

      source $WAS_STARTED_WITH_REPLICATION

      # if previous hostname != current hostname
      # set previous hostname to a loopback ip in /etc/hosts
      if [ "$PREVIOUS_HOSTNAME" != "$HOSTNAME" ]; then
        echo "127.0.0.2 $PREVIOUS_HOSTNAME" >> /etc/hosts
        PREVIOUS_HOSTNAME_PARAM="ldap://$PREVIOUS_HOSTNAME"
      fi
    fi

    # if the config was bootstraped with TLS
    # to avoid error (#6) (#36) and (#44)
    # we create fake temporary certificates if they do not exists
    if [ -e "$WAS_STARTED_WITH_TLS" ]; then
      source $WAS_STARTED_WITH_TLS

      log-helper debug "Check previous TLS certificates..."

      # fix for #73
      # image started with an existing database/config created before 1.1.5
      [[ -z "$PREVIOUS_LDAP_TLS_CA_CRT_PATH" ]] && PREVIOUS_LDAP_TLS_CA_CRT_PATH="${CERTS_DIR}/$LDAP_TLS_CA_CRT_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_CRT_PATH" ]] && PREVIOUS_LDAP_TLS_CRT_PATH="${CERTS_DIR}/$LDAP_TLS_CRT_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_KEY_PATH" ]] && PREVIOUS_LDAP_TLS_KEY_PATH="${CERTS_DIR}/$LDAP_TLS_KEY_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_DH_PARAM_PATH" ]] && PREVIOUS_LDAP_TLS_DH_PARAM_PATH="${CERTS_DIR}/dhparam.pem"

      ssl-helper $LDAP_SSL_HELPER_PREFIX $PREVIOUS_LDAP_TLS_CRT_PATH $PREVIOUS_LDAP_TLS_KEY_PATH $PREVIOUS_LDAP_TLS_CA_CRT_PATH
      [ -f ${PREVIOUS_LDAP_TLS_DH_PARAM_PATH} ] || openssl dhparam -out ${LDAP_TLS_DH_PARAM_PATH} 2048

      chmod 600 ${PREVIOUS_LDAP_TLS_DH_PARAM_PATH}
      chown openldap:openldap $PREVIOUS_LDAP_TLS_CRT_PATH $PREVIOUS_LDAP_TLS_KEY_PATH $PREVIOUS_LDAP_TLS_CA_CRT_PATH $PREVIOUS_LDAP_TLS_DH_PARAM_PATH
    fi

    # start OpenLDAP
    log-helper info "Start OpenLDAP..."

    if log-helper level ge debug; then
      slapd -h "ldap://$HOSTNAME $PREVIOUS_HOSTNAME_PARAM ldap://localhost ldapi:///" -u openldap -g openldap -d $LDAP_LOG_LEVEL 2>&1 &
    else
      slapd -h "ldap://$HOSTNAME $PREVIOUS_HOSTNAME_PARAM ldap://localhost ldapi:///" -u openldap -g openldap
    fi


    log-helper info "Waiting for OpenLDAP to start..."
    while [ ! -e /run/slapd/slapd.pid ]; do sleep 0.1; done

    #
    # setup bootstrap config - Part 2
    #
    if $BOOTSTRAP; then

      log-helper info "Add bootstrap schemas..."

      # add ppolicy schema
      ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f /etc/ldap/schema/ppolicy.ldif |& log-helper debug

      # convert schemas to ldif
      SCHEMAS=""
      for f in $(find $SCHEMA_DIR -name \*.schema -type f); do
        SCHEMAS="$SCHEMAS ${f}"
      done
      ${ASSETS_DIR}/schema-to-ldif.sh "$SCHEMAS"

      # add converted schemas
      for f in $(find $SCHEMA_DIR -name \*.ldif -type f); do
        log-helper debug "Processing file ${f}"
        # add schema if not already exists
        SCHEMA=$(basename "${f}" .ldif)
        ADD_SCHEMA=$(is_new_schema $SCHEMA)
        if [ "$ADD_SCHEMA" -eq 1 ]; then
          ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f $f |& log-helper debug
        else
          log-helper info "schema ${f} already exists"
        fi
      done

      # set config password
      LDAP_CONFIG_PASSWORD_ENCRYPTED=$(slappasswd -s $LDAP_CONFIG_PASSWORD)
      sed -i -e "s|{{ LDAP_CONFIG_PASSWORD_ENCRYPTED }}|${LDAP_CONFIG_PASSWORD_ENCRYPTED}|g" ${LDIF_DIR}/01-config-password.ldif

      log-helper info "Getting db base DN..."
      log-helper info "Setting authentication..."

      # set authentication

      if [[ X"$LDAP_AUTHENTICATION" == X"sasl" ]] ; then

	# now we're in SASL_ROOT_DN territory.
        LDAP_DB_ROOT_DN="cn=admin,cn=config"
        LDAP_DB_ROOT_PW="$LDAP_CONFIG_PASSWORD"

        get_ldap_base_dn

        # adapt sasl config file
        F=$LDIF_DIR/sasl/sasl.ldif
        sed -i -e "{
          s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g
          s|{{ LDAP_DOMAIN }}|${LDAP_DOMAIN}|g
          s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g
          s|{{ LDAP_REALM }}|${LDAP_REALM}|g
        }" $F

        # run sasl config file
        log-helper debug "Processing file $F"
        ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug


	# now we're SASL-enabled.

	# TODO: add sasl security levels (watch out! -Y EXTERNAL is used here)

      elif [[ X"$LDAP_AUTHENTICATION" == X"simple" ]] ; then

        LDAP_DB_ROOT_DN="cn=admin,$LDAP_BASE_DN"
        LDAP_DB_ROOT_PW="$LDAP_ADMIN_PASSWORD"
        LDAP_ADMIN_PASSWORD_ENCRYPTED=$(slappasswd -s $LDAP_ADMIN_PASSWORD)

	# now we're simple-enabled.
      fi

      # process config files (*.ldif) in bootstrap directory (do no process files in subdirectories)
      log-helper info "Add image bootstrap ldif..."
      for f in $(ls $LDIF_DIR/*.ldif | sort); do
        log-helper debug "Processing file ${f}"
        ldap_add_or_modify "$f"
      done

      log-helper info "Add custom bootstrap ldif..."
      for f in $(find $CUSTOM_DIR -type f -name \*.ldif  | sort); do
        log-helper debug "Processing file ${f}"
        ldap_add_or_modify "$f"
      done

      # read only user
      if [[ X"${LDAP_READONLY_USER,,}" == X"true" ]]; then

        log-helper info "Add read only user..."

	D=${LDIF_DIR}/readonly-user
	F=$D/readonly-user.ldif

        LDAP_READONLY_USER_PASSWORD_ENCRYPTED=$(slappasswd -s $LDAP_READONLY_USER_PASSWORD)

        log-helper debug "Processing file $F"
        ldap_add_or_modify $F

        if [[ X"${LDAP_AUTHENTICATION}" == X"sasl" && X"${LDAP_SYNCREPL_USER}" != X"\$LDAP_READONLY_USER_USERNAME" ]] ; then

	  # readonly-user is different from syncrepl user, so ...
          F=$LDIF_DIR/sasl/sasl-readonly.ldif
          sed -i -e "{
            s|{{ LDAP_DOMAIN }}|${LDAP_DOMAIN}|g
            s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g
            s|{{ LDAP_READONLY_USER_USERNAME }}|${LDAP_READONLY_USER_USERNAME}|g
          }" $F

          # run sasl config file
          log-helper debug "Processing file $F"
          ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug
	fi

      fi

      # accesslog support
      if [[ X"${LDAP_PROVIDER,,}" == X"true" ]]; then
        log-helper debug "Add accesslog config"
        log-helper info "Add accesslog subdir..."
        mkdir /var/lib/ldap/accesslog
        chown -R openldap:openldap /var/lib/ldap/accesslog

	D=${LDIF_DIR}/provider
        # TODO: add syncrepl user
        LDAP_SYNCREPL_PASSWORD_ENCRYPTED=$(slappasswd -s $LDAP_SYNCREPL_PASSWORD)

	F=$D/accesslog-module.ldif
        log-helper debug "Processing file $F"
        ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug

	F=$D/accesslog-syncprov.ldif
        sed -i -e "{
          s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g
          s|{{ LDAP_DB_ROOT_DN }}|${LDAP_DB_ROOT_DN}|g
          s|{{ LDAP_SYNCREPL_USER }}|${LDAP_SYNCREPL_USER}|g
          s|\$LDAP_READONLY_USER_USERNAME|$LDAP_READONLY_USER_USERNAME|g
	}" $F
        log-helper debug "Processing file $F"
        ldapadd -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug

        if [[ X"${LDAP_AUTHENTICATION}" == X"sasl" ]] ; then
          F=$LDIF_DIR/sasl/sasl-syncrepl.ldif
          sed -i -e "{
            s|{{ LDAP_DOMAIN }}|${LDAP_DOMAIN}|g
            s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g
            s|{{ LDAP_SYNCREPL_USER }}|${LDAP_SYNCREPL_USER}|g
            s|\$LDAP_READONLY_USER_USERNAME|$LDAP_READONLY_USER_USERNAME|g
          }" $F

          # run sasl config file
          log-helper debug "Processing file $F"
          ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug
	fi
      fi

      # accesslog support
      if [[ X"${LDAP_CONSUMER,,}" == X"true" ]]; then
        log-helper debug "Add consumer config"

	D=${LDIF_DIR}/consumer
	F=$D/consumer.ldif

	# fix for sasl
        if [[ X"$LDAP_AUTHENTICATION" == X"sasl" ]] ; then
	  toadd="bindmethod=sasl"
        else
	  toadd="bindmethod=simple credentials=${LDAP_SYNCREPL_PASSWORD}"
        fi
        LDAP_CONSUMER_DB_SYNCPROV="${LDAP_CONSUMER_DB_SYNCPROV} ${toadd}"

        # fix so sed edits will work (filters may have ampersands)
	LDAP_CONSUMER_DB_SYNCPROV="${LDAP_CONSUMER_DB_SYNCPROV//&/\\&}"

        sed -i "{
	  s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g
          s|{{ LDAP_CONSUMER_DB_SYNCPROV }}|${LDAP_CONSUMER_DB_SYNCPROV}|g
          s|{{ LDAP_PROVIDER_HOST }}|${LDAP_PROVIDER_HOST}|g
          s|\$LDAP_RID|$LDAP_RID|g
          s|\$LDAP_PROVIDER_HOST|$LDAP_PROVIDER_HOST|g
          s|\$LDAP_DOMAIN|$LDAP_DOMAIN|g
          s|\$LDAP_SYNCREPL_USER|$LDAP_SYNCREPL_USER|g
          s|\$LDAP_READONLY_USER_USERNAME|$LDAP_READONLY_USER_USERNAME|g
          s|\$LDAP_SYNCREPL_PASSWORD|$LDAP_SYNCREPL_PASSWORD|g
          s|\$LDAP_ADMIN_PASSWORD|$LDAP_ADMIN_PASSWORD|g
          s|\$LDAP_ADMIN_PASSWORD_ENCRYPTED|$LDAP_ADMIN_PASSWORD_ENCRYPTED|g
          s|\$LDAP_READONLY_USER_PASSWORD|$LDAP_READONLY_USER_PASSWORD|g
          s|\$LDAP_READONLY_USER_PASSWORD_ENCRYPTED|$LDAP_READONLY_USER_PASSWORD_ENCRYPTED|g
          s|\$LDAP_BASE_DN|$LDAP_BASE_DN|g
          s|\$LDAP_DB_ROOT_DN|$LDAP_DB_ROOT_DN|g
          s|\$LDAP_DB_ROOT_PW|$LDAP_DB_ROOT_PW|g
	}" $F

        ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug
      fi

      if [[ X"${LDAP_KDC,,}" == X"true" ]]; then
	# TODO: limit updates to first replication host, or provider
        log-helper info "Setup KDC config"
        mkdir -p /etc/krb5kdc

        f=kdc.conf
        F=/etc/krb5kdc/kdc.conf
        [[ -f /etc/krb5/$f ]] && cp /etc/krb5/$f $F
        [[ -f $F ]] && sed -i -e "{
          s|{{ LDAP_KDC_REALM }}|${LDAP_KDC_REALM}|g
          s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g
        }" $F

        f=kadm5.acl
        F=/etc/krb5kdc/kadm5.acl
        [[ -f /etc/krb5/$f ]] && cp /etc/krb5/$f $F
        [[ -f $F ]] && sed -i -e "{
          s|{{ LDAP_KDC_REALM }}|${LDAP_KDC_REALM}|g
        }" $F

        p="${LDAP_KDC_KDC_USER_PASSWORD}"
        echo -e "${p}\n${p}" |& kdb5_ldap_util \
          stashsrvpw \
          -f /etc/krb5kdc/conf_keyfile \
          "uid=${LDAP_KDC_KDC_USER_USERNAME},ou=people,ou=accounts,${LDAP_BASE_DN}"

        p="${LDAP_KDC_ADM_USER_PASSWORD}"
        echo -e "${p}\n${p}" |& kdb5_ldap_util \
          stashsrvpw \
          -f /etc/krb5kdc/conf_keyfile \
          "uid=${LDAP_KDC_ADM_USER_USERNAME},ou=people,ou=accounts,${LDAP_BASE_DN}"

        if [[ X"${LDAP_CONSUMER,,}" != X"true" ]]; then
	  # in consumer case, consumer should get this from provider

	  LDAP_KDC_KDC_USER_PASSWORD_ENCRYPTED=$(slappasswd -s ${LDAP_KDC_KDC_USER_PASSWORD})
	  LDAP_KDC_ADM_USER_PASSWORD_ENCRYPTED=$(slappasswd -s ${LDAP_KDC_ADM_USER_PASSWORD})

          D=${LDIF_DIR}/kdc
          F=$D/srvdn.ldif
          sed -i -e "{
            s|{{ LDAP_KDC_KDC_USER_USERNAME }}|${LDAP_KDC_KDC_USER_USERNAME}|g
            s|{{ LDAP_KDC_ADM_USER_USERNAME }}|${LDAP_KDC_ADM_USER_USERNAME}|g
            s|{{ LDAP_KDC_KDC_USER_PASSWORD_ENCRYPTED }}|${LDAP_KDC_KDC_USER_PASSWORD_ENCRYPTED}|g
            s|{{ LDAP_KDC_ADM_USER_PASSWORD_ENCRYPTED }}|${LDAP_KDC_ADM_USER_PASSWORD_ENCRYPTED}|g
          }" $F
          log-helper debug "Processing file $F"
          ldap_add_or_modify $F

          log-helper debug "Creating kdb container for ${LDAP_KDC_REALM}"
          kdb5_ldap_util \
            -D ${LDAP_DB_ROOT_DN} -w ${LDAP_DB_ROOT_PW} -H ldapi:/// \
            create \
            -P master \
            -subtrees "ou=accounts,${LDAP_BASE_DN}" \
            -sscope sub \
            -s -r "${LDAP_KDC_REALM}"
        fi
      fi
    fi

    #
    # TLS config
    #
    if [ -e "$WAS_STARTED_WITH_TLS" ] && [ "${LDAP_TLS,,}" != "true" ]; then
      log-helper error "/!\ WARNING: LDAP_TLS=false but the container was previously started with LDAP_TLS=true"
      log-helper error "TLS can't be disabled once added. Ignoring LDAP_TLS=false."
      LDAP_TLS=true
    fi

    if [ -e "$WAS_STARTED_WITH_TLS_ENFORCE" ] && [ "${LDAP_TLS_ENFORCE,,}" != "true" ]; then
      log-helper error "/!\ WARNING: LDAP_TLS_ENFORCE=false but the container was previously started with LDAP_TLS_ENFORCE=true"
      log-helper error "TLS enforcing can't be disabled once added. Ignoring LDAP_TLS_ENFORCE=false."
      LDAP_TLS_ENFORCE=true
    fi

    if [ "${LDAP_TLS,,}" == "true" ]; then
      TLS_DIR=${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls

      log-helper info "Add TLS config..."

      # generate a certificate and key with ssl-helper tool if LDAP_CRT and LDAP_KEY files don't exists
      # https://github.com/osixia/docker-light-baseimage/blob/stable/image/service-available/:ssl-tools/assets/tool/ssl-helper
      ssl-helper $LDAP_SSL_HELPER_PREFIX $LDAP_TLS_CRT_PATH $LDAP_TLS_KEY_PATH $LDAP_TLS_CA_CRT_PATH

      # create DHParamFile if not found
      [ -f ${LDAP_TLS_DH_PARAM_PATH} ] || openssl dhparam -out ${LDAP_TLS_DH_PARAM_PATH} 2048
      chmod 600 ${LDAP_TLS_DH_PARAM_PATH}

      # fix file permissions
      chown -R openldap:openldap ${CONTAINER_SERVICE_DIR}/slapd

      F=${TLS_DIR}/tls-enable.ldif

      # adapt tls ldif
      sed -i -e "{
        s|{{ LDAP_TLS_CA_CRT_PATH }}|${LDAP_TLS_CA_CRT_PATH}|g
        s|{{ LDAP_TLS_CRT_PATH }}|${LDAP_TLS_CRT_PATH}|g
        s|{{ LDAP_TLS_KEY_PATH }}|${LDAP_TLS_KEY_PATH}|g
        s|{{ LDAP_TLS_DH_PARAM_PATH }}|${LDAP_TLS_DH_PARAM_PATH}|g
        s|{{ LDAP_TLS_CIPHER_SUITE }}|${LDAP_TLS_CIPHER_SUITE}|g
        s|{{ LDAP_TLS_VERIFY_CLIENT }}|${LDAP_TLS_VERIFY_CLIENT}|g
      }" $F

      ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug

      [[ -f "$WAS_STARTED_WITH_TLS" ]] && rm -f "$WAS_STARTED_WITH_TLS"
      echo "export PREVIOUS_LDAP_TLS_CA_CRT_PATH=${LDAP_TLS_CA_CRT_PATH}" > $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_CRT_PATH=${LDAP_TLS_CRT_PATH}" >> $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_KEY_PATH=${LDAP_TLS_KEY_PATH}" >> $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_DH_PARAM_PATH=${LDAP_TLS_DH_PARAM_PATH}" >> $WAS_STARTED_WITH_TLS

      # enforce TLS
      if [ "${LDAP_TLS_ENFORCE,,}" == "true" ]; then
        log-helper info "Add enforce TLS..."
        ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $TLS_DIR/tls-enforce-enable.ldif |& log-helper debug
        touch $WAS_STARTED_WITH_TLS_ENFORCE

      # disable tls enforcing (not possible for now)
      #else
        #log-helper info "Disable enforce TLS..."
        #ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-enforce-disable.ldif |& log-helper debug || true
        #[[ -f "$WAS_STARTED_WITH_TLS_ENFORCE" ]] && rm -f "$WAS_STARTED_WITH_TLS_ENFORCE"
      fi

    # disable tls (not possible for now)
    #else
      #log-helper info "Disable TLS config..."
      #ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/tls/tls-disable.ldif |& log-helper debug || true
      #[[ -f "$WAS_STARTED_WITH_TLS" ]] && rm -f "$WAS_STARTED_WITH_TLS"
    fi



    #
    # Replication config
    #

    function disableReplication() {
      sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-disable.ldif
      ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication/replication-disable.ldif |& log-helper debug || true
      [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
    }

    if [ "${LDAP_REPLICATION,,}" == "true" ]; then

      log-helper info "Add replication config..."
      disableReplication || true

      D=${CONTAINER_SERVICE_DIR}/slapd/assets/config/replication
      F=$D/replication-enable.ldif

      if [[ X"$LDAP_AUTHENTICATION" == X"sasl" ]] ; then
        LDAP_REPLICATION_CONFIG_SYNCPROV="${LDAP_REPLICATION_CONFIG_SYNCPROV} bindmethod=sasl"
        LDAP_REPLICATION_DB_SYNCPROV="${LDAP_REPLICATION_DB_SYNCPROV} bindmethod=sasl"
      else
        LDAP_REPLICATION_CONFIG_SYNCPROV="${LDAP_REPLICATION_CONFIG_SYNCPROV} bindmethod=simple credentials=${LDAP_CONFIG_PASSWORD_ENCRYPTED}"
        LDAP_REPLICATION_DB_SYNCPROV="${LDAP_REPLICATION_DB_SYNCPROV} bindmethod=simple credentials=${LDAP_ADMIN_PASSWORD}"
      fi

      # fix so sed edits will work (filters may have ampersands)
      LDAP_REPLICATION_CONFIG_SYNCPROV="${LDAP_REPLICATION_CONFIG_SYNCPROV//&/\\&}"
      LDAP_REPLICATION_DB_SYNCPROV="${LDAP_REPLICATION_DB_SYNCPROV//&/\\&}"

      i=1
      for host in $(complex-bash-env iterate LDAP_REPLICATION_HOSTS)
      do
        sed -i -e "{
	  s|{{ LDAP_REPLICATION_HOSTS }}|olcServerID: $i ${!host}\n{{ LDAP_REPLICATION_HOSTS }}|g
          s|{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|olcSyncRepl: rid=00$i provider=${!host} ${LDAP_REPLICATION_CONFIG_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|g
          s|{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|olcSyncRepl: rid=10$i provider=${!host} ${LDAP_REPLICATION_DB_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|g
	}" $F

        ((i++))
      done

      get_ldap_base_dn
      sed -i -e "{
        s|\$LDAP_BASE_DN|$LDAP_BASE_DN|g
        s|\$LDAP_DB_ROOT_DN|$LDAP_DB_ROOT_DN|g
        s|\$LDAP_DOMAIN|$LDAP_DOMAIN|g
        s|\$LDAP_ADMIN_PASSWORD|$LDAP_ADMIN_PASSWORD|g
        s|\$LDAP_DB_ROOT_PW|$LDAP_DB_ROOT_PW|g
        s|\$LDAP_CONFIG_PASSWORD|$LDAP_CONFIG_PASSWORD|g
        /{{ LDAP_REPLICATION_HOSTS }}/d
        /{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}/d
        /{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}/d
        s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g
      }" $F

      ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug || true

      [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
      echo "export PREVIOUS_HOSTNAME=${HOSTNAME}" > $WAS_STARTED_WITH_REPLICATION

    else

      log-helper info "Disable replication config..."
      disableReplication || true

    fi

    #
    # set access
    #

    ACCESS_BITS=
    if [[ X"${LDAP_KDC,,}" == X"true" ]] ; then
      ACCESS_BITS+=1
    else
      ACCESS_BITS+=0
    fi
    if [[ X"${LDAP_PROVIDER,,}" == X"true" || X"${LDAP_CONSUMER,,}" == X"true" ]] ; then
      ACCESS_BITS+=1
    else
      ACCESS_BITS+=0
    fi
    if [[ X"${LDAP_READONLY_USER,,}" == X"true" && X"${LDAP_SYNCREPL_USER}" != X"\$LDAP_READONLY_USER_USERNAME" ]] ; then
      ACCESS_BITS+=1
    else
      ACCESS_BITS+=0
    fi

    F=$LDIF_DIR/access/${ACCESS_BITS}-access.ldif

    sed -i -e "{
      s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g
      s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g
      s|{{ LDAP_READONLY_USER_USERNAME }}|${LDAP_READONLY_USER_USERNAME}|g
      s|{{ LDAP_SYNCREPL_USER }}|${LDAP_SYNCREPL_USER}|g
      s|\$LDAP_READONLY_USER_USERNAME|$LDAP_READONLY_USER_USERNAME|g
    }" $F

    log-helper debug "Processing file $F"
    ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $F |& log-helper debug

    # TODO: remove passwords if sasl
    # TODO: add sasl security levels (watch out! -Y EXTERNAL is used here)

    #
    # stop OpenLDAP
    #
    log-helper info "Stop OpenLDAP..."

    SLAPD_PID=$(cat /run/slapd/slapd.pid)
    kill -15 $SLAPD_PID
    while [ -e /proc/$SLAPD_PID ]; do sleep 0.1; done # wait until slapd is terminated
  fi

  #
  # ldap client config
  #
  if [ "${LDAP_TLS,,}" == "true" ]; then
    log-helper info "Configure ldap client TLS configuration..."
    sed -i --follow-symlinks "s,TLS_CACERT.*,TLS_CACERT ${LDAP_TLS_CA_CRT_PATH},g" /etc/ldap/ldap.conf
    echo "TLS_REQCERT ${LDAP_TLS_VERIFY_CLIENT}" >> /etc/ldap/ldap.conf
    cp -f /etc/ldap/ldap.conf ${CONTAINER_SERVICE_DIR}/slapd/assets/ldap.conf

    [[ -f "$HOME/.ldaprc" ]] && rm -f $HOME/.ldaprc
    echo "TLS_CERT ${LDAP_TLS_CRT_PATH}" > $HOME/.ldaprc
    echo "TLS_KEY ${LDAP_TLS_KEY_PATH}" >> $HOME/.ldaprc
    cp -f $HOME/.ldaprc ${CONTAINER_SERVICE_DIR}/slapd/assets/.ldaprc
  fi

  #
  # remove container config files
  #
  if [ "${LDAP_REMOVE_CONFIG_AFTER_SETUP,,}" == "true" ]; then
    log-helper info "Remove config files..."
    rm -rf ${CONTAINER_SERVICE_DIR}/slapd/assets/config
  fi

  #
  # setup done :)
  #
  log-helper info "First start is done..."
  touch $FIRST_START_DONE
fi

ln -sf ${CONTAINER_SERVICE_DIR}/slapd/assets/.ldaprc $HOME/.ldaprc
ln -sf ${CONTAINER_SERVICE_DIR}/slapd/assets/ldap.conf /etc/ldap/ldap.conf

# force OpenLDAP to listen on all interfaces
ETC_HOSTS=$(cat /etc/hosts | sed "/$HOSTNAME/d")
echo "0.0.0.0 $HOSTNAME" ${HOSTNAME%%.*} > /etc/hosts
echo "$ETC_HOSTS" >> /etc/hosts

exit 0
