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
	local fsname="$2"
	local size=$3
	local hdmedia="$4"
	local iso="$5"
	local rdpatch="$6"
	local offset=$((4*1024*1024)) # partition at 4M offset

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp/fs"

	# add files
	tar -C "${BASEDIR}/tmp/fs" -xf "${BASEDIR}/download/${hdmedia}"
	cp --reflink=auto "${BASEDIR}/download/${iso}" "${BASEDIR}/tmp/fs"

	# patch initrd
	if [ -n "${rdpatch}" ]; then
		cat "${rdpatch}" >> "${BASEDIR}/tmp/fs/initrd.gz"
	fi

	# create ext2 fs, size - 4M
	truncate -s $((size-offset)) "${BASEDIR}/tmp/installer.ext2"
	mke2fs -t ext2 -E root_owner=0:0 -E no_copy_xattrs -L "${fsname}" -d "${BASEDIR}/tmp/fs" "${BASEDIR}/tmp/installer.ext2"

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
	local fsname="$2"
	local size=$3
	local netboot="$4"
	local dtbs_pkg=$5
	local offset=$((4*1024*1024)) # partition at 4M offset

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp/fs"

	# add files
	tar -C "${BASEDIR}/tmp/fs" -xf "${BASEDIR}/download/${netboot}"

	# add DTBs
	mkdir -p "${BASEDIR}/tmp/fs/dtb"
	tar -C "${BASEDIR}/tmp/fs/dtb" -xf "${dtbs_pkg}"

	# create boot-script
	mkimage -A arm -T script -C none -a 0 -e 0 -d "${BASEDIR}/src/arm64-hdmedia-boot.txt" "${BASEDIR}/tmp/fs/boot.scr"

	# create ext2 fs, size - 4M
	truncate -s $((size-offset)) "${BASEDIR}/tmp/installer.ext2"
	mke2fs -t ext2 -E root_owner=0:0 -E no_copy_xattrs -L "${fsname}" -d "${BASEDIR}/tmp/fs" "${BASEDIR}/tmp/installer.ext2"

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

# generate device-tree tarball from kernel deb
function build_dtb_pkg() {
	local deb="$1"
	local pkg="$2"

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp"
	pushd "${BASEDIR}/tmp"

	dpkg -x "${deb}" .
	cd usr/lib/linux-image-*
	tar -cf "${pkg}" *

	# clean workdir
	popd
	rm -rf "${BASEDIR}/tmp"
}

# generate initrd withlisted kernel modules, for appenidng to installer initrd
# can e.g. supply watchdog driver into debian-installer
function build_initrd_kmod_patch() {
	local kernel="$1"
	local patch="$2"
	shift 2

	# create empty workdir
	rm -rf "${BASEDIR}/tmp"
	mkdir -p "${BASEDIR}/tmp"
	pushd "${BASEDIR}/tmp"

	dpkg -x $kernel .

	rm -f "$patch"
	mkdir -p lib/debian-installer-startup.d
	printf "#!/bin/sh\n" > lib/debian-installer-startup.d/S09-sr-modules
	for mod in $*; do
		echo $mod | cpio -R 0:0 -H newc -o | gzip >> "$patch"
		echo "insmod /$mod" >> lib/debian-installer-startup.d/S09-sr-modules
	done
	echo lib/debian-installer-startup.d/S09-sr-modules | cpio -R 0:0 -H newc -o | gzip >> "$patch"

	# clean workdir
	popd
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
function build_debian_12_armhf() {
	set -e
	download linux-image-6.1.0-29-armmp_6.1.123-1_armhf.deb http://ftp.debian.org/debian/pool/main/l/linux linux-image-armmp-12.9.0.deb
	download hd-media.tar.gz http://ftp.debian.org/debian/dists/bookworm/main/installer-armhf/20230607+deb12u9/images/hd-media hd-media-12.9.0-armhf.tar.gz
	download debian-12.9.0-armhf-netinst.iso https://cdimage.debian.org/cdimage/release/12.9.0/armhf/iso-cd

	# generate initrd patch with watchdog driver
	mkdir -p ${BASEDIR}/generate
	build_initrd_kmod_patch "${BASEDIR}/download/linux-image-armmp-12.9.0.deb" "${BASEDIR}/generate/linux-image-armmp-12.9.0-kmod.cpio.gz" lib/modules/6.1.0-29-armmp/kernel/drivers/watchdog/imx2_wdt.ko

	build_hdmedia debian-12.9.0-armhf-netinst.img d-i-12.9.0-armhf $((1024*1024*1024)) hd-media-12.9.0-armhf.tar.gz debian-12.9.0-armhf-netinst.iso "${BASEDIR}/generate/linux-image-armmp-12.9.0-kmod.cpio.gz"
}

# Debian testing for arm64, net-install, for USB flash-drive (no bootloader)
# - AM64 HummingBoard-T
# - CN9130 Clearfog Base
# - CN9130 Clearfog Pro
# - CN9131 SolidWAN
# - CN9132 Clearfog
# - LX2160 Clearfog-CX
# - LX2160 Honeycomb
# - LX2162 Clearfog
function build_debian_testing_arm64() {
	download linux-image-6.12.21-arm64_6.12.21-1_arm64.deb http://ftp.de.debian.org/debian/pool/main/l/linux-signed-arm64 linux-image-arm64-testing.deb
	build_dtb_pkg "${BASEDIR}/download/linux-image-arm64-testing.deb" "${BASEDIR}/generate/dtbs-arm64-testing.tar"
	download netboot.tar.gz https://d-i.debian.org/daily-images/arm64/daily/netboot netboot-testing-arm64.tar.gz
	build_hdmedia_from_netboot \
		debian-testing-arm64-netinst.img \
		d-i-sid-arm64 \
		$((256*1024*1024)) \
		netboot-testing-arm64.tar.gz \
		"${BASEDIR}/generate/dtbs-arm64-testing.tar"
	return $?
}

if [ $# -lt 1 ]; then
	# build everything by default
	s=0
	build_debian_12_armhf || s=$?
	build_debian_testing_arm64 || s=$?
else
	# build specified only
	s=0
	build_${1} || s=$?
fi

# end with last error coce
exit $s
