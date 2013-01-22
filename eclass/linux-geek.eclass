# Copyright 1999-2013 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

#
#  Copyright © 2011-2013 Andrey Ovcharov <sudormrfhalt@gmail.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#  The latest version of this software can be obtained here:
#
#  https://github.com/init6/init_6/blob/master/eclass/linux-geek.eclass
#
#  Wiki: https://github.com/init6/init_6/wiki/linux-geek.eclass
#

# Functional part
# Purpose: Installing linux.
# Apply patches, build the kernel from source.
#
# Bugs to sudormrfhalt@gmail.com
#

EXPORT_FUNCTIONS ApplyPatch src_unpack use_if_iuse src_prepare src_compile src_install pkg_postinst

# No need to run scanelf/strip on kernel sources/headers (bug #134453).
RESTRICT="mirror binchecks strip"

: ${LICENSE:="GPL-2"}

# *.gz       -> gunzip -dc    -> app-arch/gzip-1.5
# *.bz|*.bz2 -> bunzip -dc    -> app-arch/bzip2-1.0.6-r3
# *.lrz      -> lrunzip -dc   -> app-arch/lrzip-0.614 <- now only for ck
# *.xz       -> xz -dc        -> app-arch/xz-utils-5.0.4-r1
# *.zip      -> unzip -d      -> app-arch/unzip-6.0-r3
# *.Z        -> uncompress -c -> app-arch/gzip-1.5

# Even though xz-utils are in @system, they must still be added to DEPEND; see
# http://archives.gentoo.org/gentoo-dev/msg_a0d4833eb314d1be5d5802a3b710e0a4.xml
DEPEND="${DEPEND}
app-arch/bzip2
app-arch/gzip
app-arch/unzip
app-arch/xz-utils"

OLDIFS="$IFS"
VER="${PV}"
IFS='.'
set -- ${VER}
IFS="${OLDIFS}"

# the kernel version (e.g 3 for 3.4.2)
VERSION="${1}"
# the kernel patchlevel (e.g 4 for 3.4.2)
PATCHLEVEL="${2}"
# the kernel sublevel (e.g 2 for 3.4.2)
SUBLEVEL="${3}"
# the kernel major version (e.g 3.4 for 3.4.2)
KMV="${1}.${2}"

# ebuild default values setup settings
DEFEXTRAVERSION="-geek"
EXTRAVERSION=${EXTRAVERSION:-$DEFEXTRAVERSION}
KV_FULL="${PVR}${EXTRAVERSION}"
S="${WORKDIR}"/linux-"${KV_FULL}"
SLOT="${PV}"

case "$PR" in
	r0)	case "$VERSION" in
			2) extension="bz2"
			kurl="http://www.kernel.org/pub/linux/kernel/v${KMV}"
			SRC_URI="${kurl}/linux-${PV}.tar.${extension}"
			;;
			3) extension="xz"
			kurl="http://www.kernel.org/pub/linux/kernel/v${VERSION}.0"
			SRC_URI="${kurl}/linux-${KMV}.tar.${extension}"
			if [ "${SUBLEVEL}" != "0" ]; then
				SRC_URI="${SRC_URI} ${kurl}/patch-${PV}.${extension}"
			fi
			;;
		esac
	;;
	*)	extension="xz"
		kurl="http://www.kernel.org/pub/linux/kernel/v${VERSION}.0/testing"
		SRC_URI="${kurl}/linux-${VERSION}.$((${PATCHLEVEL} - 1)).tar.${extension}"
		if [ "${SUBLEVEL}" != "0" ]; then
			SRC_URI="${SRC_URI} ${kurl}/patch-${PVR//r/rc}.${extension}"
		fi
	;;
esac

# default argument to patch
#patch_command='patch -p1 -F1 -s'
patch_command='patch -p1 -s'

# internal function
#
# @FUNCTION: ExtractApply
# @USAGE: ExtractApply "<patch>"
# @DESCRIPTION: Extract patch from *.gz, *.bz, *.bz2, *.lrz, *.xz, *.zip, *.Z
ExtractApply() {
	local patch=$1
	shift
	case "$patch" in
	*.gz)       gunzip -dc    < "$patch" | $patch_command ${1+"$@"} ;; # app-arch/gzip
	*.bz|*.bz2) bunzip2 -dc   < "$patch" | $patch_command ${1+"$@"} ;; # app-arch/bzip2
	*.lrz)      lrunzip -dc   < "$patch" | $patch_command ${1+"$@"} ;; # app-arch/lrzip
	*.xz)       xz -dc        < "$patch" | $patch_command ${1+"$@"} ;; # app-arch/xz-utils
	*.zip)      unzip -d      < "$patch" | $patch_command ${1+"$@"} ;; # app-arch/unzip
	*.Z)        uncompress -c < "$patch" | $patch_command ${1+"$@"} ;; # app-arch/gzip
	*) $patch_command ${1+"$@"} < "$patch" ;;
	esac
}

# internal function
#
# @FUNCTION: Handler
# @USAGE:
# @DESCRIPTION:
# Check the availability of a patch on the path passed
# Check that the patch was not an empty
# Test run patch with 'patch -p1 --dry-run'
# All tests completed successfully? run ExtractApply
Handler() {
	local patch=$1
	shift
	if [ ! -f "$patch" ]; then
		ewarn "Patch $patch does not exist."
		#exit 1 # why exit ?
	fi
	# don't apply patch if it's empty
	case "$patch" in
	*.gz|*.bz|*.bz2|*.lrz|*.xz|*.zip|*.Z)
		if [ -s "$patch" ]; then # !=0
			patch_command='patch -p1 --dry-run' # test argument to patch
			if ExtractApply "$patch" &>/dev/null; then
				# default argument to patch
				#patch_command='patch -p1 -F1 -s'
				patch_command='patch -p1 -s'
				ExtractApply "$patch" &>/dev/null
			else
				patch_base_name=$(basename "$patch")
				ewarn "Skipping patch --> $patch_base_name"
			fi
		else
			patch_base_name=$(basename "$patch")
			ewarn "Skipping empty patch --> $patch_base_name"
		fi
	;;
	*)
		local C=$(wc -l "$patch" | awk '{print $1}')
		if [ "$C" -gt 9 ]; then # 9 lines
			patch_command='patch -p1 --dry-run' # test argument to patch
			if ExtractApply "$patch" &>/dev/null; then
				# default argument to patch
				#patch_command='patch -p1 -F1 -s'
				patch_command='patch -p1 -s'
				ExtractApply "$patch" &>/dev/null
			else
				patch_base_name=$(basename "$patch")
				ewarn "Skipping patch --> $patch_base_name"
			fi
		else
			patch_base_name=$(basename "$patch")
			ewarn "Skipping empty patch --> $patch_base_name"
		fi
	;;
	esac
}

# @FUNCTION: ApplyPatch
# @USAGE:
# ApplyPatch "${FILESDIR}/${PVR}/patch_list" "Patch set description";
# ApplyPatch "${FILESDIR}/<patch>" "Patch description";
# @DESCRIPTION:
# Main function
linux-geek_ApplyPatch() {
	local patch=$1
	local msg=$2
	shift
	echo
	einfo "${msg}"
	patch_base_name=$(basename "$patch")
	patch_dir_name=$(dirname "$patch")
	case $patch_base_name in
	patch_list) # list of patches
		while read -r line
			do
			# skip empty lines
			[[ -z "$line" ]] && continue
			# skip comments
			[[ $line =~ ^\ {0,}# ]] && continue
			ebegin "Applying $line"
				Handler "$patch_dir_name/$line";
			eend $?
		done < "$patch"
	;;
	*) # else is patch
		ebegin "Applying $patch_base_name"
			Handler "$patch";
		eend $?
	;;
	esac
}
# @FUNCTION: src_unpack
# @USAGE:
# @DESCRIPTION:
linux-geek_src_unpack() {
	if [ "${A}" != "" ]; then
		ebegin "Extract the sources"
			case "$PR" in
			r0) tar xvJf "${DISTDIR}/linux-${KMV}.tar.${extension}" &>/dev/null;;
			*)  tar xvJf "${DISTDIR}/linux-${VERSION}.$((${PATCHLEVEL} - 1)).tar.${extension}" &>/dev/null;;
			esac
		eend $?
		cd "${WORKDIR}"
		case "$PR" in
		r0) mv "linux-${KMV}" "${S}";;
		*)  mv "linux-${VERSION}.$((${PATCHLEVEL} - 1))" "${S}";;
		esac
	fi
	cd "${S}"
case "$VERSION" in
	2) continue
#	if  [ "${SUBLEVEL}" != "0" ]; then
#		ApplyPatch "${DISTDIR}/patch-${PV}.${extension}" "Update to latest upstream ..."
#	fi
	;;
	3) if  [ "${SUBLEVEL}" != "0" ]; then
		case "$PR" in
		r0) ApplyPatch "${DISTDIR}/patch-${PV}.${extension}" "Update to latest upstream ...";;
		*)  ApplyPatch "${DISTDIR}/patch-${PVR//r/rc}.${extension}" "Update to latest upstream ...";;
		esac
	fi
	;;
esac

	if [[ $DEBLOB_AVAILABLE == 1 ]] && use deblob ; then
		cp "${DISTDIR}/deblob-${KMV}" "${T}" || die "cp deblob-${KMV} failed"
		cp "${DISTDIR}/deblob-check" "${T}/deblob-check" || die "cp deblob-check failed"
		chmod +x "${T}/deblob-${KMV}" "${T}/deblob-check" || die "chmod deblob scripts failed"
	fi
}

# @FUNCTION: in_iuse
# @USAGE: <flag>
# @DESCRIPTION:
# Determines whether the given flag is in IUSE. Strips IUSE default prefixes
# as necessary.
#
# Note that this function should not be used in the global scope.
in_iuse() {
	debug-print-function ${FUNCNAME} "${@}"
	[[ ${#} -eq 1 ]] || die "Invalid args to ${FUNCNAME}()"

	local flag=${1}
	local liuse=( ${IUSE} )

	has "${flag}" "${liuse[@]#[+-]}"
}

# @FUNCTION: use_if_iuse
# @USAGE: <flag>
# @DESCRIPTION:
# Return true if the given flag is in USE and IUSE.
#
# Note that this function should not be used in the global scope.
linux-geek_use_if_iuse() {
	in_iuse $1 || return 1
	use $1
}

# @FUNCTION: src_prepare
# @USAGE:
# @DESCRIPTION:
linux-geek_src_prepare() {
	einfo "Set extraversion in Makefile" # manually set extraversion
	sed -i -e "s:^\(EXTRAVERSION =\).*:\1 ${EXTRAVERSION}:" Makefile

	einfo "Copy current config from /proc"
	if [ -e "/usr/src/linux-${KV_FULL}/.config" ]; then
		ewarn "Kernel config file already exist."
		ewarn "I will NOT overwrite that."
		cp "/usr/src/linux-${KV_FULL}/.config" "${WORKDIR}/linux-${KV_FULL}/.config"
	else
		zcat /proc/config > .config || ewarn "Can't copy /proc/config"
	fi

	einfo "Cleanup backups after patching"
	find '(' -name '*~' -o -name '*.orig' -o -name '.*.orig' -o -name '.gitignore'  -o -name '.*.old' ')' -print0 | xargs -0 -r -l512 rm -f

	einfo "Remove unneeded architectures"
	if use x86 || use amd64; then
		rm -rf "${WORKDIR}"/linux-"${KV_FULL}"/arch/{alpha,arm,arm26,arm64,avr32,blackfin,c6x,cris,frv,h8300,hexagon,ia64,m32r,m68k,m68knommu,mips,microblaze,mn10300,openrisc,parisc,powerpc,ppc,s390,score,sh,sh64,sparc,sparc64,tile,unicore32,um,v850,xtensa}
	else
		rm -rf "${WORKDIR}"/linux-"${KV_FULL}"/arch/{avr32,blackfin,c6x,cris,frv,h8300,hexagon,m32r,m68k,m68knommu,microblaze,mn10300,openrisc,score,tile,unicore32,um,v850,xtensa}
	fi

	einfo "Compile gen_init_cpio"
	make -C "${WORKDIR}"/linux-"${KV_FULL}"/usr/ gen_init_cpio
	chmod +x "${WORKDIR}"/linux-"${KV_FULL}"/usr/gen_init_cpio "${WORKDIR}"/linux-"${KV_FULL}"/scripts/gen_initramfs_list.sh

	cd "${WORKDIR}"/linux-"${KV_FULL}"
	local GENTOOARCH="${ARCH}"
	unset ARCH
	ebegin "kernel: >> Running oldconfig..."
	make oldconfig </dev/null &>/dev/null
	eend $? "Failed oldconfig"
	ebegin "kernel: >> Running modules_prepare..."
	make modules_prepare &>/dev/null
	eend $? "Failed modules prepare"
	ARCH="${GENTOOARCH}"

	echo
	einfo "Live long and prosper."
	echo
}

# @FUNCTION: src_compile
# @USAGE:
# @DESCRIPTION:
linux-geek_src_compile() {
	if [[ $DEBLOB_AVAILABLE == 1 ]] && use deblob ; then
		echo ">>> Running deblob script ..."
		sh "${T}/deblob-${KMV}" --force || \
			die "Deblob script failed to run!!!"
	fi
}

# @FUNCTION: src_install
# @USAGE:
# @DESCRIPTION:
linux-geek_src_install() {
	# disable sandbox
	export SANDBOX_ON=0
	local version_h_name="usr/src/linux-${KV_FULL}/include/linux"
	local version_h="${ROOT}${version_h_name}"

	if [ -f "${version_h}" ]; then
		einfo "Discarding previously installed version.h to avoid collisions"
		addwrite "/${version_h_name}"
		rm -f "${version_h}"
	fi

	cd "${S}"
	dodir /usr/src
	echo ">>> Copying sources ..."

	mv ${WORKDIR}/linux* "${D}"/usr/src;

	if use symlink ; then
		if [ -h "/usr/src/linux" ]; then
			unlink "/usr/src/linux"
		elif [ -d "/usr/src/linux" ]; then
			mv "/usr/src/linux" "/usr/src/linux-old"
		fi
		dosym linux-${KV_FULL} \
			"/usr/src/linux" ||
			die "cannot install kernel symlink"
	fi

	if use build ; then
		# Find out some info..
		eval $(head -n 4 Makefile | sed -e 's/ //g')
		local ARCH=$(uname -m | sed -e s/i.86/i386/g)
		local FULLVER=${VERSION}.${PATCHLEVEL}.${SUBLEVEL}${EXTRAVERSION}
		local MODULESUPPORT=$(grep "CONFIG_MODULES=y" .config 2>/dev/null)

		if [[ -e .config && -e arch/${ARCH}/boot/bzImage ]]; then
			ISNEWER=$(find .config -newer arch/${ARCH}/boot/bzImage 2>/dev/null)
		else
			if ! [[ -e .config ]]; then
				ISNEWER="noconfig"
			else
				ISNEWER="yes"
			fi
		fi

		if [[ -e .version ]]; then
			BUILDNO=$(cat .version)
		else
			BUILDNO="0"
		fi

		ebegin "Beginning installation procedure for \"${FULLVER}\""
			if [[ ${ISNEWER} == "noconfig" ]]; then
				ebegin " No kernel config found, searching for best availiable config"
					if [[ -e /proc/config.gz ]]; then
						einfo "  Foung config from running kernel, updating to match target kernel"
							zcat /proc/config.gz > .config
							true | make oldconfig 2>/dev/null
					else
						einfo "  No suitable custom config found, defaulting to defconfig"
							cp arch/${ARCH}/defconfig .config
					fi
				eend $?
			fi

			if [[ ${ISNEWER} != "" ]]; then
				ebegin " Kernel build not uptodate, compiling"
					make bzImage 2>/dev/null
					if [[ ${MODULESUPPORT} != "" ]]; then
						einfo "  Module support in kernel detected, building modules"
							make modules 2>/dev/null
					fi
				eend $?
				BUILDNO=$(cat .version)
			fi

			ebegin " Merging kernel to system (Buildnumber: ${BUILDNO})"
				if [[ $(cat /proc/mounts | grep /boot) == "" && $(cat /etc/fstab | grep /boot) != "" ]]; then
					ebegin "  Boot partition unmounted, mounting"
						mount /boot
					eend $?
				fi
				einfo "  Copying bzImage to \"/boot/vmlinuz-${FULLVER}-${BUILDNO}\""
					cp arch/${ARCH}/boot/bzImage /boot/vmlinuz-${FULLVER}-${BUILDNO}
				einfo "  Copying System.map to \"/boot/System.map-${FULLVER}\""
					cp System.map /boot/System.map-${FULLVER}
				einfo "  Copying .config to \"/boot/config-${FULLVER}\""
					cp .config /boot/config-${FULLVER}
				if [[ ${MODULESUPPORT} != "" ]]; then
					einfo "  Installing modules to \"/lib/modules/${FULLVER}/\""
						make modules_install 2>/dev/null
				fi
				ebegin " Editing kernel entry in GRUB"
					if [[ -e "/etc/grub.d/10_linux" ]]; then
						grub2-mkconfig -o /boot/grub2/grub.cfg;
					fi;
					if [[ -e "/etc/boot.conf" ]]; then
						boot-update;
					fi;
				eend $?
			eend $?

			if [[ -e /var/lib/module-rebuild/moduledb && $(cat /var/lib/module-rebuild/moduledb | wc -l) -ge 1 ]]; then
				ebegin " Looking for external kernel modules that need rebuilding"
					for EXTKERNMOD in $(sed -e 's/.:.://g' /var/lib/module-rebuild/moduledb); do
						if [[ $(find /boot/vmlinuz-${FULLVER}-${BUILDNO} -newer /var/db/pkg/${EXTKERNMOD}/environment.bz2 2>/dev/null) != "" ]]; then
							ebegin "  Recompiling outdated module \"${EXTKERNMOD}\""
								emerge --oneshot =${EXTKERNMOD} 2>/dev/null
							eend $?
						fi
					done
				eend $?
			fi
		eend $?
	fi
}

# @FUNCTION: pkg_postinst
# @USAGE:
# @DESCRIPTION:
linux-geek_pkg_postinst() {
	einfo " If you are upgrading from a previous kernel, you may be interested "
	einfo " in the following document:"
	einfo "   - General upgrade guide: http://www.gentoo.org/doc/en/kernel-upgrade.xml"
	einfo " ${CATEGORY}/${PN} is UNSUPPORTED Gentoo Security."
	einfo " This means that it is likely to be vulnerable to recent security issues."
	einfo " For specific information on why this kernel is unsupported, please read:"
	einfo " http://www.gentoo.org/proj/en/security/kernel.xml"
	einfo
	einfo " Now is the time to configure and build the kernel."
	einfo
}
