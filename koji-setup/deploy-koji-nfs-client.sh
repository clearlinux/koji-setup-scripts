#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/globals.sh
source "$SCRIPT_DIR"/parameters.sh

KOJI_MOUNT_DIR=/mnt/koji
KOJI_MOUNT_SERVICE="${KOJI_MOUNT_DIR:1}"
KOJI_MOUNT_SERVICE="${KOJI_MOUNT_SERVICE/\//-}".mount
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/"$KOJI_MOUNT_SERVICE" <<- EOF
[Unit]
Description=Koji NFS Mount
After=network.target

[Mount]
What=$KOJI_MASTER_FQDN:$KOJI_DIR
Where=$KOJI_MOUNT_DIR
Type=nfs
Options=defaults,ro

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now "$KOJI_MOUNT_SERVICE"
