#!/bin/bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/globals.sh
source "$SCRIPT_DIR"/parameters.sh

swupd bundle-add storage-utils

# Export server directory to be mounted by clients
echo "$KOJI_DIR $KOJI_SLAVE_FQDN(ro)" >> /etc/exports

systemctl enable --now rpcbind
systemctl enable --now nfs-server
