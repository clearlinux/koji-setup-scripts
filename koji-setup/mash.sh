#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
if [[ -e /etc/profile.d/proxy.sh ]]; then
	source /etc/profile.d/proxy.sh
fi

KOJI_HOME=/srv/koji
MASH_HOME=/srv/mash
MASH_TRACKER_FILE="$MASH_HOME"/latest-mash-build
MASH_DIR="$MASH_HOME"/latest
MASH_DIR_OLD="$MASH_DIR".old
MASH_DIR_NEW="$MASH_DIR".new

if [[ -e "$MASH_TRACKER_FILE" ]]; then
	MASH_BUILD_NUM="$(< "$MASH_TRACKER_FILE")"
else
	MASH_BUILD_NUM=0
fi
KOJI_BUILD_NUM="$(basename "$(realpath "$KOJI_HOME"/repos/dist-clear-build/latest/)")"
if [[ "$MASH_BUILD_NUM" -ne "$KOJI_BUILD_NUM" ]]; then
	COMPS_FILE=$(mktemp)
	koji show-groups --comps dist-clear-build > "$COMPS_FILE"
	rm -rf "$MASH_DIR_NEW"
	mash --outputdir="$MASH_DIR_NEW" --compsfile="$COMPS_FILE" clear
	rm -f "$COMPS_FILE"
	dnf -q --repofrompath=mash,file://"$MASH_DIR_NEW"/clear/x86_64/os repoquery -a --queryformat="%{NAME}\t%{VERSION}\t%{RELEASE}" | sort > "$MASH_DIR_NEW"/clear/x86_64/packages-os &>/dev/null
	dnf -q --repofrompath=mash,file://"$MASH_DIR_NEW"/clear/x86_64/debug repoquery -a --queryformat="%{NAME}\t%{VERSION}\t%{RELEASE}" | sort > "$MASH_DIR_NEW"/clear/x86_64/packages-debug &>/dev/null
	dnf -q --repofrompath=mash,file://"$MASH_DIR_NEW"/clear/source/SRPMS repoquery -a --queryformat="%{NAME}\t%{VERSION}\t%{RELEASE}" | sort > "$MASH_DIR_NEW"/clear/source/packages-SRPMS &>/dev/null
	if [[ -e "$MASH_DIR" ]]; then
		mv "$MASH_DIR" "$MASH_DIR_OLD"
	fi
	mv "$MASH_DIR_NEW" "$MASH_DIR"
	rm -rf "$MASH_DIR_OLD"
	echo "$KOJI_BUILD_NUM" > "$MASH_TRACKER_FILE"
fi
