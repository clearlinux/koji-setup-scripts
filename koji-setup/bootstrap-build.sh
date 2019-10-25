#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/globals.sh
source "$SCRIPT_DIR"/parameters.sh

if [[ -n "$SRC_RPM_DIR" && -n "$BIN_RPM_DIR" ]]; then
	find "$SRC_RPM_DIR" -name '*.src.rpm' | xargs -n 1 -I {} sudo -u kojiadmin koji import {}
	find "$BIN_RPM_DIR" -name "*.$RPM_ARCH.rpm" | xargs -n 1 -I {} sudo -u kojiadmin koji import {}
	if [[ -n "$DEBUG_RPM_DIR" ]]; then
		find "$DEBUG_RPM_DIR" -name "*.$RPM_ARCH.rpm" | xargs -n 1 -I {} sudo -u kojiadmin koji import {}
	fi
fi
sudo -u kojiadmin koji add-tag "$TAG_NAME"
sudo -u kojiadmin koji edit-tag "$TAG_NAME" -x mock.package_manager=dnf
if [[ -n "$SRC_RPM_DIR" && -n "$BIN_RPM_DIR" ]]; then
	sudo -u kojiadmin koji list-pkgs --quiet | xargs -I {} sudo -u kojiadmin koji add-pkg --owner kojiadmin "$TAG_NAME" {}
	sudo -u kojiadmin koji list-untagged | xargs -n 1 -I {} sudo -u kojiadmin koji call tagBuildBypass "$TAG_NAME" {}
fi
sudo -u kojiadmin koji add-tag --parent "$TAG_NAME" --arches "$RPM_ARCH" "$TAG_NAME"-build
sudo -u kojiadmin koji add-target "$TAG_NAME" "$TAG_NAME"-build
sudo -u kojiadmin koji add-group "$TAG_NAME"-build build
sudo -u kojiadmin koji add-group "$TAG_NAME"-build srpm-build
sudo -u kojiadmin koji add-group-pkg "$TAG_NAME"-build build autoconf automake automake-dev binutils bzip2 clr-rpm-config coreutils diffutils gawk gcc gcc-dev gettext gettext-bin git glibc-dev glibc-locale glibc-utils grep gzip hostname libc6-dev libcap libtool libtool-dev linux-libc-headers m4 make netbase nss-altfiles patch pigz pkg-config pkg-config-dev rpm-build sed sed-doc shadow systemd-lib tar unzip which xz
sudo -u kojiadmin koji add-group-pkg "$TAG_NAME"-build srpm-build coreutils cpio curl-bin git glibc-utils grep gzip make pigz plzip rpm-build sed shadow tar unzip wget xz
if [[ -n "$EXTERNAL_REPO" ]]; then
	sudo -u kojiadmin koji add-external-repo -t "$TAG_NAME"-build "$TAG_NAME"-external-repo "$EXTERNAL_REPO"
fi
sudo -u kojiadmin koji regen-repo "$TAG_NAME"-build
