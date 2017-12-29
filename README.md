# awuersch/openldap

Latest release: 1.2.0 - OpenLDAP 2.4.44 -  [Changelog](CHANGELOG.md) | [Docker Hub](https://hub.docker.com/r/awuersch/openldap/) 

**A docker image to run OpenLDAP.**

> OpenLDAP website : [www.openldap.org](http://www.openldap.org/)


- [Genealogy](#genealogy)
- [Under the hood: osixia/light-baseimage](#under-the-hood-osixialight-baseimage)
- [Future](#future)
- [What's New Here](#whats-new-here)
- [What's Not Here](#whats-not-here)
- [Security](#security)
- [Environment Variables](#environment-variables)
	- [Set your own environment variables](#set-your-own-environment-variables)
		- [Link environment file](#link-environment-file)
- [Changelog](#changelog)

## Genealogy

This repo draws on and updates
[osixia/openldap](https://github.com/osixia/docker-openldap).
Osixia's openldap has great documentation of its own -- check it out.

The other inspiration for this repo is
[the FreeIPA project](https://freeipa.org)

## Under the hood: osixia/light-baseimage

This image is based on osixia/light-baseimage.
It uses the following features:

- **ssl-tools** service to generate tls certificates
- **log-helper** tool to print log messages based on the log level
- **run** tool as entrypoint to init the container environment

To fully understand how this image works take a look at:
https://github.com/osixia/docker-light-baseimage

## Future

This and other repos are contributing to
my little vision of privacy and its prerequisites,
see [here](https://tony.wuersch.name/stog-output/posts/vision-1.html).

The vision asks for

- a principal-persisting ecology (Kerberos / Active Directory),
- ontologies and apps to set up and maintain organizational forms (LDAP+),
- a certificate authority (Google's Certificate Transparency),
- an orchestration framework (Docker Swarm or Kubernetes),
- compatible location transmitters, and
- visit history updaters. 

## What's New Here

This repo supports Osixia's openldap functionality, i.e.

- TLS via self-signed CA autogeneration of certificates.
- mirror mode replication.

Added are:

- provider-consumer (or primary-replica, pick your jargon poison) replication
- SASL (GSSAPI, i.e., Kerberos) support and Kerberos user support
- Kerberos backend support

It should support

- backups
- nssproxy (nslcd for Linux) and sudo
- setup of backends for multiple Kerberos realms

shortly.

## What's Not Here

This release only uses _slapd_ and _k5start_ daemons.
K5start keeps Kerberos credentials fresh.

Support for Kerberos admin daemons (krb5kdc and kadmind) is in another repo,
[here](https://github.com/awuersch/docker-krb5kdc).

Putting admin daemons in the same container image is contrary to a container
microservices ideal.

## Prerequisites

SASL support is a bit surprising for now.
It presumes a Kerberos config from a volume bound to _/etc/krb5_.
It also presumes a Kerberos REALM *elsewhere*.
The volume bound to _/etc/krb5_ should have a proper keytab.

## Security

This repo does not yet deserve to be called "secure".
It still has easy startup features,
such as command-line overrides to environment variables,
which more or less eviscerate security.

A proper invocation of this repo should update its default startup YAML file.
The default YAML is filled with useful defaults.

Unfortunately, I don't yet have a tool I like
to read and easily generate an update to a default startup YAML file.
I'm looking for one.

A security feature I'm looking to add is to remove passwords before startup.
With SASL, this is largely done.
A loose end is the Kerberos backend DNs.
Their passwords can't be removed until I get SASL GSSAPI support working
from a _kdc.conf_ file.

Finally, I'm hoping to use only certificates generated from a private CA
instead of permitting self-signed certificates for TLS.

- [Environment Variables](#environment-variables)
	- [Default.yaml](#defaultyaml)
	- [Default.startup.yaml](#defaultyamlstartup)
	- [Set your own environment variables](#set-your-own-environment-variables)

## Environment variables

### Set your own environment variables

#### Link environment file

For example if your environment files **my-env.yaml** and **my-env.startup.yaml** are in /data/ldap/environment

	docker run --volume /data/ldap/environment:/container/environment/01-custom \
	--detach osixia/openldap:1.2.0

Take care to link your environment files folder to `/container/environment/XX-somedir` (with XX < 99 so they will be processed before default environment files) and not  directly to `/container/environment` because this directory contains predefined baseimage environment files to fix container environment (INITRD, LANG, LANGUAGE and LC_CTYPE).

Note: the container will try to delete the **\*.startup.yaml** file after the end of startup files so the file will also be deleted on the docker host. To prevent that : use --volume /data/ldap/environment:/container/environment/01-custom**:ro** or set all variables in **\*.yaml** file and don't use **\*.startup.yaml**:

	docker run --volume /data/ldap/environment/my-env.yaml:/container/environment/01-custom/env.yaml \
	--detach osixia/openldap:1.2.0

## Changelog

Please refer to: [CHANGELOG.md](CHANGELOG.md)
