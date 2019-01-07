#!/bin/bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/parameters.sh

# Install kojid
swupd bundle-add koji

# Create mock folders and permissions
mkdir -p /etc/mock/koji
mkdir -p /var/lib/mock
chown -R root:mock /var/lib/mock

# Setup User Accounts
useradd -r kojibuilder
usermod -G mock kojibuilder

# Kojid Configuration Files
mkdir -p /etc/kojid
cat > /etc/kojid/kojid.conf <<- EOF
[kojid]
sleeptime=5
maxjobs=16
topdir=$KOJI_DIR
workdir=/tmp/koji
mockdir=/var/lib/mock
mockuser=kojibuilder
mockhost=generic-linux-gnu
user=$KOJI_SLAVE_FQDN
server=$KOJI_URL/kojihub
topurl=$KOJI_URL/kojifiles
use_createrepo_c=True
allowed_scms=$GIT_FQDN:/packages/*
cert = $KOJI_PKI_DIR/$KOJI_SLAVE_FQDN.pem
ca = $KOJI_PKI_DIR/koji_ca_cert.crt
serverca = $KOJI_PKI_DIR/koji_ca_cert.crt
EOF

if env | grep -q proxy; then
	echo "yum_proxy = $https_proxy" >> /etc/kojid/kojid.conf
	mkdir -p /etc/systemd/system/kojid.service.d
	cat > /etc/systemd/system/kojid.service.d/00-proxy.conf <<- EOF
	[Service]
	Environment=http_proxy=$http_proxy
	Environment=https_proxy=$https_proxy
	Environment=no_proxy=$no_proxy
	EOF
	systemctl daemon-reload
fi

systemctl enable --now kojid
