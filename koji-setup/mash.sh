#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e
if [[ -e /etc/profile.d/proxy.sh ]]; then
	source /etc/profile.d/proxy.sh
fi

TAG_NAME="${TAG_NAME:-clear}"
BUILD_ARCH="${BUILD_ARCH:-x86_64}"
KOJI_DIR="${KOJI_DIR:-/srv/koji}"
MASH_DIR="${MASH_DIR:-/srv/mash}"
MASH_TRACKER_FILE="$MASH_DIR"/latest-mash-build
MASH_TRACKER_DIR="$MASH_DIR"/latest
MASH_DIR_OLD="$MASH_TRACKER_DIR".old
MASH_DIR_NEW="$MASH_TRACKER_DIR".new

write_packages_file() {
	local PKG_DIR="$1"
	local PKG_FILE="$2"
	rpm -qp --qf="%{NAME}\t%{VERSION}\t%{RELEASE}\n" "$PKG_DIR"/*.rpm | sort > "$PKG_FILE"
}

if [[ -e "$MASH_TRACKER_FILE" ]]; then
	MASH_BUILD_NUM="$(< "$MASH_TRACKER_FILE")"
else
	MASH_BUILD_NUM=0
fi
KOJI_BUILD_NUM="$(basename "$(realpath "$KOJI_DIR"/repos/dist-"$TAG_NAME"-build/latest/)")"
if [[ "$MASH_BUILD_NUM" -ne "$KOJI_BUILD_NUM" ]]; then
	COMPS_FILE="$(mktemp)"
	koji show-groups --comps dist-"$TAG_NAME"-build > "$COMPS_FILE"
	rm -rf "$MASH_DIR_NEW"
	mkdir -p "$MASH_DIR_NEW"
	mash --outputdir="$MASH_DIR_NEW" --compsfile="$COMPS_FILE" clear
	rm -f "$COMPS_FILE"

	write_packages_file "$MASH_DIR_NEW"/clear/"$BUILD_ARCH"/os/Packages "$MASH_DIR_NEW"/clear/"$BUILD_ARCH"/packages-os
	write_packages_file "$MASH_DIR_NEW"/clear/"$BUILD_ARCH"/debug "$MASH_DIR_NEW"/clear/"$BUILD_ARCH"/packages-debug
	write_packages_file "$MASH_DIR_NEW"/clear/source/SRPMS "$MASH_DIR_NEW"/clear/source/packages-SRPMS

	if [[ -e "$MASH_TRACKER_DIR" ]]; then
		mv "$MASH_TRACKER_DIR" "$MASH_DIR_OLD"
	fi
	mv "$MASH_DIR_NEW" "$MASH_TRACKER_DIR"
	rm -rf "$MASH_DIR_OLD"

	echo "$KOJI_BUILD_NUM" > "$MASH_TRACKER_FILE"
fi
