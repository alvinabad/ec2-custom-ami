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
Create Ubuntu Tarfile Image for EC2
Usage:
    `basename $0` [options] image-tarfile

options:
    -c filename         APT sources file
    -p filename         Packages List file

Examples:
    `basename $0` -c ubuntu-sources.list -p ubuntu-packages.cfg myubuntu14.tar.gz
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
    echo "Removing ${ROOT_MOUNT} ..."
    rm -rf ${ROOT_MOUNT} > /dev/null 2>&1
}

#-------------------------------------------------------------------------------
close_devices() {
    echo "Closing devices..."

    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    rm -f ${ROOT_MOUNT}/root/.bash_history

    if [ -d "${ROOT_MOUNT}/proc" ] && mountpoint ${ROOT_MOUNT}/proc; then
        umount ${ROOT_MOUNT}/proc || true
    fi
    if [ -d "${ROOT_MOUNT}/sys" ] && mountpoint ${ROOT_MOUNT}/sys; then
        umount ${ROOT_MOUNT}/sys || true
    fi
    if [ -d "${ROOT_MOUNT}/dev/pts" ] && mountpoint ${ROOT_MOUNT}/dev/pts; then
        umount ${ROOT_MOUNT}/dev/pts || true
    fi

    sync;sync;sync
    echo "Devices closed."
}

setup_devices() {
    echo "Setting up devices..."

    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    mkdir -p ${ROOT_MOUNT}/{dev,etc,proc,sys}

    echo "Devices mounted."
}

install_packages() {
    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    # Install packages
    PACKAGES=`cat $PACKAGE_FILE | grep -P '^[^#\s]+.*'`

    ubuntu_url=`grep '^deb' $REPO_FILE | head -1 |  awk '{print $2}'`
    ubuntu_release=`grep '^deb' $REPO_FILE | head -1 |  awk '{print $3}'`

    debootstrap --arch amd64 $ubuntu_release ${ROOT_MOUNT} $ubuntu_url
    echo
    echo "debootstrap install complete."

    if [ -d "${ROOT_MOUNT}/proc" ] && mountpoint ${ROOT_MOUNT}/proc; then
        umount ${ROOT_MOUNT}/proc || true
    fi
    if [ -d "${ROOT_MOUNT}/sys" ] && mountpoint ${ROOT_MOUNT}/sys; then
        umount ${ROOT_MOUNT}/sys || true
    fi
    if [ -d "${ROOT_MOUNT}/dev/pts" ] && mountpoint ${ROOT_MOUNT}/dev/pts; then
        umount ${ROOT_MOUNT}/dev/pts || true
    fi

    chroot ${ROOT_MOUNT} mount -t proc none /proc
    chroot ${ROOT_MOUNT} mount -t sysfs none /sys
    chroot ${ROOT_MOUNT} mount -t devpts none /dev/pts

    chroot ${ROOT_MOUNT} apt-get update
    echo
    echo "apt-get update complete."

    for p in $PACKAGES
    do
        chroot ${ROOT_MOUNT} apt-get --assume-yes -y install $p
        echo
        echo "apt-get install $p complete."
    done

    echo "Packages installation complete."
}

post_install() {
    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    cp chroot-post-install.sh ${ROOT_MOUNT}/tmp
    chroot ${ROOT_MOUNT} /tmp/chroot-post-install.sh all
}

clean() {
    [ -d "${ROOT_MOUNT}" ] || abort "Not a directory: ${ROOT_MOUNT}"

    close_devices
    rm -rf ${ROOT_MOUNT}/*
}

create_tar() {
    echo "Creating ${TARFILE} from ${ROOT_MOUNT}/ ..."
    cd ${ROOT_MOUNT}/ && tar cfz ${TARFILE} .
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

trap "cleanup; exit 1" SIGHUP SIGINT SIGTERM

ROOT_MOUNT=/var/tmp/`basename $0`.${RANDOM}
mkdir -p $ROOT_MOUNT

[ -f /etc/debian_version ] || abort "Must run under Ubuntu system."

clean
setup_devices
install_packages
post_install
close_devices
create_tar
cleanup

echo "All done."
