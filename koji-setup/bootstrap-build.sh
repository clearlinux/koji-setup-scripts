#!/bin/bash
set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/parameters.sh

sudo -u kojiadmin koji add-tag dist-"$TAG_NAME"
sudo -u kojiadmin koji add-tag --parent dist-"$TAG_NAME" --arches "x86_64" dist-"$TAG_NAME"-build
sudo -u kojiadmin koji edit-tag dist-"$TAG_NAME" -x mock.package_manager=dnf
sudo -u kojiadmin koji add-group dist-"$TAG_NAME"-build build
sudo -u kojiadmin koji add-group dist-"$TAG_NAME"-build srpm-build
sudo -u kojiadmin koji add-target dist-"$TAG_NAME" dist-"$TAG_NAME"-build
if [[ -n "$EXTERNAL_REPO" ]]; then
	sudo -u kojiadmin koji add-external-repo -t dist-"$TAG_NAME"-build dist-"$TAG_NAME"-external-repo "$EXTERNAL_REPO"
fi
sudo -u kojiadmin koji taginfo dist-"$TAG_NAME"-build
sudo -u kojiadmin koji add-group-pkg dist-"$TAG_NAME"-build build autoconf automake automake-dev binutils bzip2 clr-rpm-config coreutils diffutils g++ gawk gcc gcc-dev gettext gettext-bin git glibc-dev glibc-locale glibc-utils grep gzip hostname lib6-locale libc6-dev libcap libgcc-s-dev libstdc++-dev libtool libtool-dev linux-libc-headers linux-libc-headers-dev m4 make netbase nss-altfiles patch pigz pkg-config pkg-config-dev rpm-build sed sed-doc shadow systemd-libs tar unzip which xz
sudo -u kojiadmin koji add-group-pkg dist-"$TAG_NAME"-build srpm-build coreutils cpio curl-bin git glibc-utils grep gzip make pigz rpm-build sed shadow tar unzip wget xz
sudo -u kojiadmin koji regen-repo dist-"$TAG_NAME"-build
