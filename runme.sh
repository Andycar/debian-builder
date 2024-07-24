#!/bin/bash

# we don't have status code checks for each step - use "-e" with a trap instead
function error() {
	status=$?
	printf "ERROR: Line %i failed with status %i: %s\n" $BASH_LINENO $status "$BASH_COMMAND" >&2
	exit $status
}
trap error ERR
set -e

BASEDIR=$(pwd)

# extend path for systems where mke2fs is in sbin
PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

#
# Download file form URL if does not exist locally.
# Optionally with renaming.
#
# Note: This function uses round brackets in order to spawn a sub-shell with different error-behaviour
function download() (
	local filename="$1"
	local url="$2"
	local rename="$3"

	if [ -z "${rename}" ]; then
		rename="${filename}"
	fi

	if [ -f "${BASEDIR}/download/${rename}" ]; then
		# file exists, skip
		return 0
	fi

	# download
	mkdir -p "${BASEDIR}/download"
	wget -O "${BASEDIR}/download/${rename}" "${url}/${filename}"
	if [ $? -ne 0 ]; then
		echo "Download Failed ..."
		rm -f "${BASEDIR}/download/${rename}"
		return 1
	fi

	return 0
)

#
# Build installer image from hd-media tarball and iso
#
function build_hdmedia() {
	local name="$1"
	local size=$2
	local hdmedia="$3"
	local iso="$4"
	local offset=$((4*1024*1024)) # partition at 4M offset

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp/fs"

	# add files
	tar -C "${BASEDIR}/tmp/fs" -xf "${BASEDIR}/download/${hdmedia}"
	cp --reflink=auto "${BASEDIR}/download/${iso}" "${BASEDIR}/tmp/fs"

	# create ext2 fs, size - 4M
	truncate -s $((size-offset)) "${BASEDIR}/tmp/installer.ext2"
	mke2fs -t ext2 -E root_owner=0:0 -E no_copy_xattrs -L "d-i-12.6.0-armhf" -d "${BASEDIR}/tmp/fs" "${BASEDIR}/tmp/installer.ext2"

	# create disk image, ext2 at offset 4M
	truncate -s ${offset} "${BASEDIR}/tmp/installer.img"
	cat "${BASEDIR}/tmp/installer.ext2" >> "${BASEDIR}/tmp/installer.img"

	# create partition table
	parted -s "${BASEDIR}/tmp/installer.img" -- mklabel msdos mkpart primary ext4 ${offset}B $((size-1))B

	# export result
	mkdir -p "${BASEDIR}/output"
	cp -v --reflink=auto "${BASEDIR}/tmp/installer.img" "${BASEDIR}/output/${name}"

	# clean workdir
	rm -rf "${BASEDIR}/tmp"
}

#
# Build installer image from netboot tarball and iso
# Used with arm64 port where debian is not offering hd-media tarballs.
#
function build_hdmedia_from_netboot() {
	local name="$1"
	local size=$2
	local netboot="$3"
	local dtbs_url=$4
	shift 4
	local dtbs="$*"
	local offset=$((4*1024*1024)) # partition at 4M offset

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp/fs"

	# add files
	tar -C "${BASEDIR}/tmp/fs" -xf "${BASEDIR}/download/${netboot}"

	# add DTBs
	for dtb in ${dtbs}; do
		# TODO: cache locally
		mkdir -p "${BASEDIR}/tmp/fs/dtb/$(dirname $dtb)"
		wget -O "${BASEDIR}/tmp/fs/dtb/${dtb}" "${dtbs_url}/${dtb}"
	done

	# create boot-script
	mkimage -A arm -T script -C none -a 0 -e 0 -d "${BASEDIR}/src/arm64-hdmedia-boot.txt" "${BASEDIR}/tmp/fs/boot.scr"

	# create ext2 fs, size - 4M
	truncate -s $((size-offset)) "${BASEDIR}/tmp/installer.ext2"
	mke2fs -t ext2 -E root_owner=0:0 -E no_copy_xattrs -L "d-i-12.6.0-armhf" -d "${BASEDIR}/tmp/fs" "${BASEDIR}/tmp/installer.ext2"

	# create disk image, ext2 at offset 4M
	truncate -s ${offset} "${BASEDIR}/tmp/installer.img"
	cat "${BASEDIR}/tmp/installer.ext2" >> "${BASEDIR}/tmp/installer.img"

	# create partition table
	parted -s "${BASEDIR}/tmp/installer.img" -- mklabel msdos mkpart primary ext4 ${offset}B $((size-1))B

	# export result
	mkdir -p "${BASEDIR}/output"
	cp -v --reflink=auto "${BASEDIR}/tmp/installer.img" "${BASEDIR}/output/${name}"

	# clean workdir
	rm -rf "${BASEDIR}/tmp"
}

# Debian 12 for armhf, net-install, for USB flash-drive (no bootloader)
# - Armada 388:
#   - Clearfog Base
#   - Clearfog Pro
#   - Helios-4
# - i.MX6
#   - Cubox-i
#   - HummingBoard Base
#   - HummingBoard Pro
#   - HummingBoard Gate
#   - HummingBoard Edge
#   - TODO: HummingBoard CBi
#   - TODO: SolidSense N6
download hd-media.tar.gz http://ftp.debian.org/debian/dists/bookworm/main/installer-armhf/20230607+deb12u6/images/hd-media hd-media-12.6.0-armhf.tar.gz
download debian-12.6.0-armhf-netinst.iso https://cdimage.debian.org/cdimage/release/12.6.0/armhf/iso-cd
build_hdmedia debian-12.6.0-armhf-netinst.img $((1024*1024*1024)) hd-media-12.6.0-armhf.tar.gz debian-12.6.0-armhf-netinst.iso

# Debian testing for arm64, net-install, for USB flash-drive (no bootloader)
# - CN9130 Clearfog Base
# - CN9130 Clearfog Pro
# - CN9131 SolidWAN
# - CN9132 Clearfog
# - LX2160 Clearfog-CX
# - LX2160 Honeycomb
# - LX2162 Clearfog
download netboot.tar.gz https://d-i.debian.org/daily-images/arm64/daily/netboot netboot-testing-arm64.tar.gz
build_hdmedia_from_netboot debian-testing-arm64-netinst.img $((96*1024*1024)) netboot-testing-arm64.tar.gz \
	https://d-i.debian.org/daily-images/arm64/daily/device-tree/ \
	marvell/cn9130-cf-base.dtb \
	marvell/cn9130-cf-pro.dtb \
	marvell/cn9131-cf-solidwan.dtb \
	freescale/fsl-lx2160a-clearfog-cx.dtb \
	freescale/fsl-lx2160a-honeycomb.dtb \
	freescale/fsl-lx2162a-clearfog.dtb
