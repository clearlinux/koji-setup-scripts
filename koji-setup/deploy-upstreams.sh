#!/bin/bash
# Copyright (C) 2018 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/globals.sh
source "$SCRIPT_DIR"/parameters.sh

mkdir -p "$UPSTREAMS_DIR"
chown -R "$GIT_USER":"$GIT_USER" "$UPSTREAMS_DIR"
mkdir -p "$HTTPD_DOCUMENT_ROOT"
UPSTREAMS_LINK="$HTTPD_DOCUMENT_ROOT"/"$(basename "$UPSTREAMS_DIR")"
ln -sf "$UPSTREAMS_DIR" "$UPSTREAMS_LINK"
chown -h "$GIT_USER":"$GIT_USER" "$UPSTREAMS_LINK"
usermod -a -G "$GIT_USER" "$HTTPD_USER"
