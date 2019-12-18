#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/globals.sh
source "$SCRIPT_DIR"/parameters.sh

STAGING_RPM_DIR="$KOJI_DIR/work/imported-rpms"
STAGING_RPM_SRC_DIR="$STAGING_RPM_DIR/src"
STAGING_RPM_BIN_DIR="$STAGING_RPM_DIR/bin"
STAGING_RPM_DEBUG_DIR="$STAGING_RPM_DIR/debug"

import_koji_pkg() {
	local src_dir="$1"
	local dst_dir="$2"
	local search_pattern="$3"
	cp -r "$src_dir" "$dst_dir"
	chown -R "$HTTPD_USER":"$HTTPD_USER" "$dst_dir"
	find "$dst_dir" -name "$search_pattern" -exec koji import --link {} + > /dev/null
}

if [[ -n "$SRC_RPM_DIR" && -n "$BIN_RPM_DIR" ]]; then
	ADMIN_KOJI_DIR="$(echo ~kojiadmin)/.koji"
	cp -r "$ADMIN_KOJI_DIR" "$HOME/.koji"
	mkdir -p "$STAGING_RPM_DIR"
	chown -R "$HTTPD_USER":"$HTTPD_USER" "$STAGING_RPM_DIR"

	import_koji_pkg "$SRC_RPM_DIR" "$STAGING_RPM_SRC_DIR" "*.src.rpm"
	import_koji_pkg "$BIN_RPM_DIR" "$STAGING_RPM_BIN_DIR" "*.$RPM_ARCH.rpm"
	if [[ -n "$DEBUG_RPM_DIR" ]]; then
		import_koji_pkg "$DEBUG_RPM_DIR" "$STAGING_RPM_DEBUG_DIR" "*.$RPM_ARCH.rpm"
	fi

	rm -rf "$STAGING_RPM_DIR" "$HOME/.koji"
fi
sudo -u kojiadmin koji add-tag dist-"$TAG_NAME"
sudo -u kojiadmin koji edit-tag dist-"$TAG_NAME" -x mock.package_manager=dnf
if [[ -n "$SRC_RPM_DIR" && -n "$BIN_RPM_DIR" ]]; then
	sudo -u kojiadmin koji list-pkgs --quiet | xargs sudo -u kojiadmin koji add-pkg --owner kojiadmin dist-"$TAG_NAME"
	sudo -u kojiadmin koji list-untagged | xargs -n 1 -P 100 sudo -u kojiadmin koji call tagBuildBypass dist-"$TAG_NAME" > /dev/null
fi
sudo -u kojiadmin koji add-tag --parent dist-"$TAG_NAME" --arches "$RPM_ARCH" dist-"$TAG_NAME"-build
sudo -u kojiadmin koji add-target dist-"$TAG_NAME" dist-"$TAG_NAME"-build
sudo -u kojiadmin koji add-group dist-"$TAG_NAME"-build build
sudo -u kojiadmin koji add-group dist-"$TAG_NAME"-build srpm-build
sudo -u kojiadmin koji add-group-pkg dist-"$TAG_NAME"-build build autoconf automake automake-dev binutils bzip2 clr-rpm-config coreutils cpio diffutils elfutils file gawk gcc gcc-dev gettext gettext-bin git glibc-dev glibc-locale glibc-utils grep gzip hostname libc6-dev libcap libtool libtool-dev linux-libc-headers m4 make netbase nss-altfiles patch pigz pkg-config pkg-config-dev rpm sed shadow systemd-lib tar unzip which xz
sudo -u kojiadmin koji add-group-pkg dist-"$TAG_NAME"-build srpm-build coreutils cpio curl-bin elfutils file git glibc-utils grep gzip make pigz plzip rpm sed shadow tar unzip wget xz
if [[ -n "$EXTERNAL_REPO" ]]; then
	sudo -u kojiadmin koji add-external-repo -t dist-"$TAG_NAME"-build dist-"$TAG_NAME"-external-repo "$EXTERNAL_REPO"
fi
sudo -u kojiadmin koji regen-repo dist-"$TAG_NAME"-build
