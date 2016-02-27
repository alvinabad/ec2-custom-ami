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

#----------
# abort
abort() {
    echo "ERROR: $@" 1>&2
    exit 1
}

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

[ ! -f "$TARFILE" ] || abort "$TARFILE already exists."
TARFILE_DIR=`dirname $TARFILE`
TARFILE_DIR=`(cd $TARFILE_DIR && pwd)`
TARFILE=${TARFILE_DIR}/`basename $TARFILE`

SCRIPT_DIR=`dirname $0`
SCRIPT_DIR=`(cd $SCRIPT_DIR && pwd)`

cleanup() {
    echo "Cleaning up ${ROOT_MOUNT} ..."
    close_devices
    rm -rf ${ROOT_MOUNT}
}

#----------
close_devices() {
    yum -c $REPO_FILE --installroot=${ROOT_MOUNT} -y clean packages || true

    rm -f ${ROOT_MOUNT}/root/.bash_history
    rm -rf ${ROOT_MOUNT}/var/cache/yum
    rm -rf ${ROOT_MOUNT}/var/lib/yum

    set +e
    umount ${ROOT_MOUNT}/sys 2>/dev/null
    umount ${ROOT_MOUNT}/proc 2>/dev/null
    umount ${ROOT_MOUNT}/dev/shm 2>/dev/null
    umount ${ROOT_MOUNT}/dev/pts 2>/dev/null
    umount ${ROOT_MOUNT}/dev 2>/dev/null
    sync;sync;sync;sync;sync

    echo "Devices closed."
}

setup_devices() {
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
    echo "Devices mounted."
}

install_packages() {
    touch ${ROOT_MOUNT}/etc/fstab
    mkdir -p ${ROOT_MOUNT}/etc/sysconfig
    touch ${ROOT_MOUNT}/etc/sysconfig/network

    # Install packages
    PACKAGES=`cat $PACKAGE_FILE | grep -P '^[^#\s]+.*'`

    #yum -c $REPO_FILE --disablerepo=* --enablerepo=_base --installroot=${ROOT_MOUNT} -y groupinstall Core
    for p in $PACKAGES
    do
        yum -c $REPO_FILE --disablerepo=* --enablerepo=_base,_extras --installroot=${ROOT_MOUNT} -y install $p
    done
    echo "Packages installation complete."

    #yum -c $REPO_FILE --disablerepo=* --enablerepo=_updates --installroot=${ROOT_MOUNT} -y update
    #echo "YUM update complete."
}

post_install() {
    cp chroot-post-install.sh ${ROOT_MOUNT}/tmp
    chroot ${ROOT_MOUNT} /tmp/chroot-post-install.sh all

}

clean() {
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

trap "cleanup; exit 1" SIGHUP SIGINT SIGTERM

ROOT_MOUNT=/var/tmp/`basename $0`.${RANDOM}
mkdir -p $ROOT_MOUNT

clean
setup_devices
install_packages
post_install
close_devices
create_tar
cleanup
