#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

## KOJI RPM BUILD AND TRACKER
export KOJI_DIR=/srv/koji
export KOJI_MOUNT_DIR=/mnt/koji
export KOJI_MASTER_FQDN="$(hostname -f)"
export KOJI_URL=https://"$KOJI_MASTER_FQDN"
export KOJI_MOUNT_DIR=/mnt/koji
export KOJI_SLAVE_FQDN="$KOJI_MASTER_FQDN"
export KOJID_CAPACITY=16
export TAG_NAME=clear
# Use for koji SSL certificates
export COUNTRY_CODE='Example Country Code'
export STATE='Example State'
export LOCATION='Example Location'
export ORGANIZATION='Example Organization'
export ORG_UNIT='Example Org Unit'
# Use for importing existing RPMs
export RPM_ARCH='x86_64'
export SRC_RPM_DIR=
export BIN_RPM_DIR=
export DEBUG_RPM_DIR=
# Comment the following if supplying all RPMs as an upstream and not a downstream
export EXTERNAL_REPO=https://cdn.download.clearlinux.org/releases/"$(curl https://download.clearlinux.org/latest)"/clear/\$arch/os/

## POSTGRESQL DATABASE
export POSTGRES_DIR=/srv/pgsql

## GIT REPOSITORIES
export GIT_DIR=/srv/gitolite
export GIT_FQDN="$KOJI_MASTER_FQDN"
export IS_ANONYMOUS_GIT_NEEDED=false
export GITOLITE_PUB_KEY=''

## UPSTREAMS CACHE
export UPSTREAMS_DIR=/srv/upstreams

## MASH RPMS
export MASH_DIR=/srv/mash
export MASH_SCRIPT_DIR=/usr/local/bin
