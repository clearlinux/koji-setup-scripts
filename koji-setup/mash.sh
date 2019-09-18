#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e
. /etc/profile.d/proxy.sh || :

BUILD_ARCH="${BUILD_ARCH:-x86_64}"
KOJI_DIR="${KOJI_DIR:-/srv/koji}"
MASH_DIR="${MASH_DIR:-/srv/mash}"
MASH_TRACKER_FILE="$MASH_DIR"/latest-mash-build
MASH_TRACKER_DIR="$MASH_DIR"/latest
MASH_DIR_OLD="$MASH_TRACKER_DIR".old
MASH_DIR_NEW="$MASH_TRACKER_DIR".new

create_dist_repos() {
	local output_dir="${1}"

	local work_dir="$(mktemp -d)"

	local nvr_pkg_list="${work_dir}/nvr-pkg-list"
	local bin_rpm_paths="${work_dir}/bin-rpm-paths"
	local debuginfo_rpm_paths="${work_dir}/debuginfo-rpm-paths"
	local src_rpm_paths="${work_dir}/src-rpm-paths"
	local comps_file="${work_dir}/comps.xml"

	sed -r -e 's|[^/]+/||' -e "s|^|${KOJI_DIR}/|" "${KOJI_REPO_PATH}/${BUILD_ARCH}/pkglist" > "${bin_rpm_paths}"
	cut -d/ -f3-5 "${KOJI_REPO_PATH}/${BUILD_ARCH}/pkglist" | sort -u > "${nvr_pkg_list}"
	while IFS='/' read -r name version release; do
		local debuginfo_rpm_path="${KOJI_DIR}/packages/${name}/${version}/${release}/${BUILD_ARCH}/${name}-debuginfo-${version}-${release}.${BUILD_ARCH}.rpm"
		if [[ -s "${debuginfo_rpm_path}" ]]; then
			echo "${debuginfo_rpm_path}" >> "${debuginfo_rpm_paths}"
		fi
		echo "${KOJI_DIR}/packages/${name}/${version}/${release}/src/${name}-${version}-${release}.src.rpm" >> "${src_rpm_paths}"
	done < "${nvr_pkg_list}"

	cp -f "${KOJI_REPO_PATH}/groups/comps.xml" "${comps_file}"

	make_repo "${output_dir}/clear/${BUILD_ARCH}/os" "Packages" "${bin_rpm_paths}" "${comps_file}" &
	make_repo "${output_dir}/clear/${BUILD_ARCH}/debug" "." "${debuginfo_rpm_paths}" &
	make_repo "${output_dir}/clear/source/SRPMS" "." "${src_rpm_paths}" &
	wait

	create_dnf_conf "${work_dir}/dnf-os.conf" "${output_dir}/clear/${BUILD_ARCH}/os" clear-os
	create_dnf_conf "${work_dir}/dnf-debug.conf" "${output_dir}/clear/${BUILD_ARCH}/debug" clear-debug
	create_dnf_conf "${work_dir}/dnf-SRPMS.conf" "${output_dir}/clear/source/SRPMS" clear-SRPMS

	write_packages_file "${work_dir}/dnf-os.conf" "$output_dir/clear/$BUILD_ARCH/packages-os"
	write_packages_file "${work_dir}/dnf-debug.conf" "$output_dir/clear/$BUILD_ARCH/packages-debug"
	write_packages_file "${work_dir}/dnf-SRPMS.conf" "$output_dir/clear/source/packages-SRPMS"

	rm -rf "${work_dir}"
}

make_repo() {
	local repo_dir="${1}"
	local rpm_dir="${1}/${2}"
	local file_list="${3}"
	local comps_file="${4}"

	local create_repo_cmd="createrepo_c --quiet --database --compress-type xz --workers $(nproc --all)"

	mkdir -p "${rpm_dir}"
	xargs -a "${file_list}" -I {} cp -f {} "${rpm_dir}"
	if [[ -z "${comps_file}" ]]; then
		${create_repo_cmd} "${repo_dir}"
	else
		${create_repo_cmd} --groupfile "${comps_file}" "${repo_dir}"
	fi
}

create_dnf_conf() {
	local dnf_conf="${1}"
	local repo_path="${2}"
	local repo_name="${3:-clear}"
	cat > "${dnf_conf}" <<EOF
[${repo_name}]
name=${repo_name}
baseurl=file://${repo_path}
EOF
}

write_packages_file() {
	local dnf_conf="${1}"
	local output_file="${2}"

	dnf --config "${dnf_conf}" --quiet --releasever=clear \
		repoquery --all --queryformat="%{NAME}\t%{VERSION}\t%{RELEASE}" \
		| sort > "${output_file}"
}

if [[ -e "$MASH_TRACKER_FILE" ]]; then
	MASH_BUILD_NUM="$(< "$MASH_TRACKER_FILE")"
else
	MASH_BUILD_NUM=0
fi
KOJI_TAG="${KOJI_TAG:-"dist-clear"}"
KOJI_REPO_PATH="$(realpath "$KOJI_DIR/repos/$KOJI_TAG-build/latest")"
KOJI_BUILD_NUM="$(basename "$KOJI_REPO_PATH")"
if [[ "$MASH_BUILD_NUM" -ne "$KOJI_BUILD_NUM" ]]; then
	rm -rf "$MASH_DIR_NEW"
	mkdir -p "$MASH_DIR_NEW"
	create_dist_repos "$MASH_DIR_NEW"
	if [[ -e "$MASH_TRACKER_DIR" ]]; then
		mv "$MASH_TRACKER_DIR" "$MASH_DIR_OLD"
	fi
	mv "$MASH_DIR_NEW" "$MASH_TRACKER_DIR"
	rm -rf "$MASH_DIR_OLD"

	echo "$KOJI_BUILD_NUM" > "$MASH_TRACKER_FILE"
fi
