#!/bin/bash

#-------------------------------------------------------------------------------
# The MIT License (MIT)
# 
# Copyright (c) 2016 Alvin Abad
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Usage
usage() {
    cat <<EOF
Create Tarfile Image for EC2
Usage:
    `basename $0` [options] image-tarfile

options:
    -c repo_file        YUM repo file
    -p package_file     Packages List file

Example:
    `basename $0` -c yum.repo -p packages.cfg mycentos6.tar.gz

Creates mycentos6.tar.gz file.
Extract this file to a disk volume and create a snapshot/AMI image.
EOF
    exit 1
}

#-------------------------------------------------------------------------------
# abort
abort() {
    echo "ERROR: $@" 1>&2
    exit 1
}

#-------------------------------------------------------------------------------
cleanup() {
    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    echo "Cleaning up ${ROOT_MOUNT} ..."
    close_devices
    rm -rf ${ROOT_MOUNT}
}

#-------------------------------------------------------------------------------
close_devices() {
    echo "Closing devices..."

    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    rm -f ${ROOT_MOUNT}/root/.bash_history

    if [ "$IS_CENTOS" = "true" ]; then
        yum -c $REPO_FILE --installroot=${ROOT_MOUNT} -y clean packages || true
        rm -rf ${ROOT_MOUNT}/var/cache/yum
        rm -rf ${ROOT_MOUNT}/var/lib/yum


        umount ${ROOT_MOUNT}/sys 2>/dev/null || true
        umount ${ROOT_MOUNT}/proc 2>/dev/null || true
        umount ${ROOT_MOUNT}/dev/shm 2>/dev/null || true
        umount ${ROOT_MOUNT}/dev/pts 2>/dev/null || true
        umount ${ROOT_MOUNT}/dev 2>/dev/null || true
    elif [ "$IS_DEBIAN" = "true" ]; then
        if [ -d "${ROOT_MOUNT}/proc" ]; then
            umount ${ROOT_MOUNT}/proc || true
        fi
        if [ -d "${ROOT_MOUNT}/sys" ]; then
            umount ${ROOT_MOUNT}/sys || true
        fi
    fi

    sync;sync;sync;sync;sync

    echo "Devices closed."
}

setup_devices() {
    echo "Setting up devices..."

    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    if [ "$IS_CENTOS" = "true" ]; then
        mkdir -p ${ROOT_MOUNT}/var/{cache,log,lock,lib/rpm}
        mkdir -p ${ROOT_MOUNT}/{dev,etc,proc,run,sys,srv}

        # make device nodes
        umount ${ROOT_MOUNT}/sys 2>/dev/null || true
        umount ${ROOT_MOUNT}/proc 2>/dev/null || true
        umount ${ROOT_MOUNT}/dev/shm 2>/dev/null || true
        umount ${ROOT_MOUNT}/dev/pts 2>/dev/null || true
        umount ${ROOT_MOUNT}/dev 2>/dev/null || true

        # mount devices
        mount -o bind /dev ${ROOT_MOUNT}/dev
        mount -o bind /dev/pts ${ROOT_MOUNT}/dev/pts
        mount -o bind /dev/shm ${ROOT_MOUNT}/dev/shm
        mount -o bind /proc ${ROOT_MOUNT}/proc
        mount -o bind /sys ${ROOT_MOUNT}/sys
    elif [ "$IS_DEBIAN" = "true" ]; then
        mkdir -p ${ROOT_MOUNT}/{dev,etc,proc,sys}
    fi

    echo "Devices mounted."
}

install_packages() {
    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    # Install packages
    PACKAGES=`cat $PACKAGE_FILE | grep -P '^[^#\s]+.*'`

    if [ "$IS_CENTOS" = "true" ]; then
        touch ${ROOT_MOUNT}/etc/fstab
        mkdir -p ${ROOT_MOUNT}/etc/sysconfig
        touch ${ROOT_MOUNT}/etc/sysconfig/network

        #yum -c $REPO_FILE --disablerepo=* --enablerepo=_base --installroot=${ROOT_MOUNT} -y groupinstall Core
        for p in $PACKAGES
        do
            yum -c $REPO_FILE --disablerepo=* --enablerepo=_base,_extras --installroot=${ROOT_MOUNT} -y install $p
        done
        echo "Packages installation complete."

        #yum -c $REPO_FILE --disablerepo=* --enablerepo=_updates --installroot=${ROOT_MOUNT} -y update
        #echo "YUM update complete."
    elif [ "$IS_DEBIAN" = "true" ]; then
        ubuntu_url=`grep '^deb' $REPO_FILE | head -1 |  awk '{print $2}'`
        ubuntu_release=`grep '^deb' $REPO_FILE | head -1 |  awk '{print $3}'`

        debootstrap --arch amd64 $ubuntu_release ${ROOT_MOUNT} $ubuntu_url
        echo ------------------------------------------------------------------------
        echo "debootstrap install complete."
        echo ------------------------------------------------------------------------

        if [ -d "${ROOT_MOUNT}/proc" ]; then
            umount ${ROOT_MOUNT}/proc || true
        fi
        if [ -d "${ROOT_MOUNT}/sys" ]; then
            umount ${ROOT_MOUNT}/sys || true
        fi

        chroot ${ROOT_MOUNT} mount -t proc none /proc
        chroot ${ROOT_MOUNT} mount -t sysfs none /sys

        chroot ${ROOT_MOUNT} apt-get update
        echo ------------------------------------------------------------------------
        echo "apt-get update complete."
        echo ------------------------------------------------------------------------

        for p in $PACKAGES
        do
            chroot ${ROOT_MOUNT} apt-get --assume-yes -y install $p
            echo ------------------------------------------------------------------------
            echo "apt-get install $p complete."
            echo ------------------------------------------------------------------------
        done
    fi
}

post_install() {
    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    if [ "$IS_CENTOS" = "true" ]; then
        cp chroot-post-install.sh ${ROOT_MOUNT}/tmp
        chroot ${ROOT_MOUNT} /tmp/chroot-post-install.sh all
    elif [ "$IS_DEBIAN" = "true" ]; then
        true
    fi
}

clean() {
    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    close_devices
    rm -rf ${ROOT_MOUNT}/*
}

create_tar() {
    cd ${ROOT_MOUNT}/ && tar cvfz ${TARFILE} .
    echo "Created: $TARFILE"
}

#-------------------------------------------------------------------------------
# START MAIN
#-------------------------------------------------------------------------------
[ $# -ne 0 ] || usage

while getopts ":c:p:v" opt; do
  case $opt in
    c)
        REPO_FILE=$OPTARG
        ;;
    p)
        PACKAGE_FILE=$OPTARG
        ;;
    *)
        echo "Invalid option: -$OPTARG" >&2
        usage
        ;;
  esac
done
shift $((OPTIND-1))

TARFILE=$1

set -e
unalias -a

[ `id -u` -eq 0 ] || abort "Must run as root"

[ -f "$PACKAGE_FILE" ] || abort "Not found: $PACKAGE_FILE"
[ -f "$REPO_FILE" ] || abort "Not found: $REPO_FILE"
REPO_FILE_DIR=`dirname $REPO_FILE`
REPO_FILE_DIR=`(cd $REPO_FILE_DIR && pwd)`
REPO_FILE=${REPO_FILE_DIR}/`basename $REPO_FILE`

[ ! -f "$TARFILE" ] || abort "$TARFILE already exists."
TARFILE_DIR=`dirname $TARFILE`
TARFILE_DIR=`(cd $TARFILE_DIR && pwd)`
TARFILE=${TARFILE_DIR}/`basename $TARFILE`

SCRIPT_DIR=`dirname $0`
SCRIPT_DIR=`(cd $SCRIPT_DIR && pwd)`

trap "cleanup; exit 1" SIGHUP SIGINT SIGTERM EXIT

ROOT_MOUNT=/var/tmp/`basename $0`.${RANDOM}
mkdir -p $ROOT_MOUNT

if [ -f /etc/debian_version ]; then
    IS_DEBIAN=true
elif [ -f /etc/redhat-release ]; then
    IS_CENTOS=true
fi

clean
setup_devices
install_packages
post_install
close_devices
create_tar
cleanup

echo "All done."
