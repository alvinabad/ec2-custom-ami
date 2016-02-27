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

set -e

TEMP_FILE=/tmp/.temp${RANDOM}

usage() {
    cat <<EOF
Extract EC2 tar image to disk

Usage:
    `basename $0` tarfile disk

Example:
    `basename $0` ec2-image.tar.gz /dev/xvdk

    ec2-image.tar.gz will be extracted to /dev/xvdk disk.
    Create snapshot and AMI of /dev/xvdk volume.
    Use:
        Root device name: /dev/sda
        ARCH: x86_64
        Kernel ID: pv-grub-hd00_1.04-x86_64

WARNING: Contents of /dev/xvdk will be destroyed.

EOF
    exit 1
}

abort() {
    echo "ERROR: $@" 1>&2
    exit 1
}

partition_disk() {
    typeset device=$1

    [ -b "$device" ] || abort "$device is not a disk device."

    # clear device
    dd if=/dev/zero of=$device bs=1 count=512

    # partition device
    cat > $TEMP_FILE <<EOF
n
p
1
1
+250M
n
p
2


p
w
EOF
    fdisk /dev/xvdl < $TEMP_FILE > /dev/null 2>&1 || true
    rm -f $TEMP_FILE

    # format partitions
    mkfs.ext4 ${device}1 > /dev/null
    mkfs.ext4 ${device}2 > /dev/null

    # label partitions
    e2label ${DEVICE}2 _root
    e2label ${DEVICE}1 _boot
    blkid ${DEVICE}1
    blkid ${DEVICE}2
    echo "Disk partitioned and formatted: ${DEVICE}1, ${DEVICE}2"
}

cleanup() {
    umount ${ROOT_MOUNT}/boot || true
    umount ${ROOT_MOUNT} || true
}

#---------------------------------------
# START MAIN
#---------------------------------------

[ $# -ne 0 ] || usage

TARFILE=$1
DEVICE=$2

[ -f "$TARFILE" ] || abort "Not found: $TARFILE"
[ -b "$DEVICE" ] || abort "$DEVICE is not a disk device."

MOUNT_NAME=`basename $TARFILE`
MOUNT_NAME=`echo $MOUNT_NAME | sed 's/.tar.gz//'`
[ -n "$MOUNT_NAME" ] || abort "Mount name not found."

ROOT_MOUNT=/mnt/$MOUNT_NAME
mkdir -p $ROOT_MOUNT

# check if something is already mounted
if mountpoint $ROOT_MOUNT; then
    abort "Something is already mounted."
fi

if [ -d "${ROOT_MOUNT}/boot" ]; then
    if mountpoint ${ROOT_MOUNT}/boot; then
        abort "Something is already mounted."
    fi
fi

# Partition and format disk
partition_disk $DEVICE

# mount partitions
mount ${DEVICE}2 $ROOT_MOUNT

mkdir -p ${ROOT_MOUNT}/boot
mount ${DEVICE}1 ${ROOT_MOUNT}/boot
mountpoint $ROOT_MOUNT
mountpoint ${ROOT_MOUNT}/boot

trap "cleanup; exit 1" SIGHUP SIGINT SIGTERM

# deploy tarfile
echo "Extracting ${TARFILE} into $ROOT_MOUNT ..."
tar xfz $TARFILE -C $ROOT_MOUNT

cleanup
sync; sync; sync; sync;
