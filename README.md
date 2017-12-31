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
- [Changelog](#changelog)

## Genealogy

This repo draws on and updates
[osixia/openldap](https://github.com/osixia/docker-openldap).
Osixia's openldap has great documentation of its own -- check it out.

The other inspiration for this repo is
[the FreeIPA project](https://freeipa.org)

## Under the hood: osixia/light-baseimage

This image is based on
[osixia/light-baseimage](https://github.com/osixia/docker-light-baseimage).

It uses the following features:

- **ssl-tools** service for auto-generated TLS certificates
- **log-helper** tool to print log messages based on a log level
- **run** tool as entrypoint to init the container environment

## Future

This contributes to my little vision of privacy and its prerequisites,
see [here](https://tony.wuersch.name/stog-output/posts/vision-1.html).

The vision asks for

- a principal-persisting ecology (Kerberos / Active Directory),
- ontologies and apps to set up and maintain organizational forms (LDAP+),
- a certificate authority (Google's Certificate Transparency),
- an orchestration framework (Docker Swarm or Kubernetes),
- compatible location transmitters, and
- visit history updaters. 

## What's New

We support Osixia's openldap functionality, i.e.

- TLS via self-signed CA autogeneration of certificates.
- mirror mode replication.

Added are:

- provider-consumer (or primary-replica, pick your jargon poison) replication
- SASL (GSSAPI, i.e., Kerberos) support and Kerberos user support
- Kerberos backend support

Scripts in the `scripts` directory show how we use the image
currently. The main script is `run-container.sh`. The scripts
source an `ldapvars` file with environment variable assignments.

A python subdirectory under `scripts` has leader-election code
for mirror-mode replicated servers, presuming etcd. One script
there adjusts replica referral values based on leader-election
results.

This repo should support

- backups
- nssproxy (nslcd for Linux) and sudo
- setup of backends for multiple Kerberos realms

shortly.

Passwords (before startup) should also be removed soon.

We expect using the image will change a lot, once choices are made
to run in Docker Swarm or Kubernetes.

## What's Not Here

This release only uses `slapd` and `k5start` daemons.
Slapd is the OpenLDAP engine.
K5start keeps Kerberos credentials fresh.

Support for Kerberos admin daemons (`krb5kdc` and `kadmind`) is
[here](https://github.com/awuersch/docker-krb5kdc).
We could put admin daemons here, but a microservices ideal
suggests that one shouldn't put too much function in one image.

We removed the examples and test directories in the original Osixia
openldap repo. If we reintegrate to them, we'll add them back.

## Prerequisites

SASL support presumes a Docker volume bound to `/etc/krb5`.
The volume should have a proper Kerberos keytab, relative to the SASL
Kerberos realm used by the container.
It should also have `kdc.conf` and `krb5.conf` configuration files.
In the style of Osixia config files, these config files are templates,
resolved by the image's `slapd/startup.sh` script.

## Security

This repo is not "secure" yet.

It still has easy startup features,
such as command-line overrides to environment variables,
which expose secrets in process and audit outputs.

A good use of this image should update the startup YAML file.

Unfortunately, I don't yet have a tool I like to update a YAML file.
Default startup YAML is filled with useful defaults. To create a good
startup YAML file, the default should be read and updated.

SASL enables running LDAP without passwords.
An issue is Kerberos backend DNs for _krb5kdc_ daemons.
Their passwords can't be removed until I get SASL GSSAPI support
working from a _kdc.conf_ file.

I'm hoping soon to use only certificates generated from a private
CA, instead of self-signed certificates.

The upshot of this section is that I hope to move away from the
flexible many arguments of Osixia's framework, to a mode where
arguments to the image are the result of preprocessing, and the
resulting container is very likely to be secure.

## Changelog

Please refer to: [CHANGELOG.md](CHANGELOG.md)
