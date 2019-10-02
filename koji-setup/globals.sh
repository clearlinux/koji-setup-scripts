#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

#### START DO NOT EDIT ####
export GIT_USER=gitolite
export GIT_DEFAULT_DIR=/var/lib/gitolite

export POSTGRES_USER=postgres
export POSTGRES_DEFAULT_DIR=/var/lib/pgsql

export HTTPD_USER=httpd
export HTTPD_DOCUMENT_ROOT=/var/www/html

export KOJI_PKI_DIR=/etc/pki/koji

check_dependency() {
	if [[ "$#" -ne 1 ]]; then
		echo "Incorrect number of arguments!" >&2
		exit 1
	fi
	if ! type "$1"; then
		echo "$1 not found!" >&2
		exit 1
	fi
}

#### END DO NOT EDIT ####
