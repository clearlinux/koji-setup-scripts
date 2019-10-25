#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/globals.sh
source "$SCRIPT_DIR"/parameters.sh

swupd bundle-add package-utils || :
check_dependency dnf
check_dependency createrepo_c

mkdir -p "$MASH_DIR"
chown -R kojiadmin:kojiadmin "$MASH_DIR"
mkdir -p "$HTTPD_DOCUMENT_ROOT"
MASH_LINK="$HTTPD_DOCUMENT_ROOT"/"$(basename "$MASH_DIR")"
ln -sf "$MASH_DIR"/latest "$MASH_LINK"
chown -h kojiadmin:kojiadmin "$MASH_LINK"
usermod -a -G kojiadmin "$HTTPD_USER"
rpm --initdb

mkdir -p "$MASH_SCRIPT_DIR"
cp -f "$SCRIPT_DIR"/mash.sh "$MASH_SCRIPT_DIR"
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/mash.service <<- EOF
[Unit]
Description=Mash script to loop local repository creation for local image builds

[Service]
User=kojiadmin
Group=kojiadmin
ExecStart=$MASH_SCRIPT_DIR/mash.sh
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now mash
