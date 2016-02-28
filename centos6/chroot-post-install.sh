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

# Must run at post-install, e.g., chroot to image

#---------------------------------------
abort() {
    echo "ERROR: $@" 1>&2
    exit 1
}

#---------------------------------------
set_boot_symlink() {
    rm -f /boot/boot
    cd /boot && ln -s ./ boot

    ls -l /boot
    echo "/boot symlink created."
}

#---------------------------------------
set_root_user() {
    cat > /root/.bashrc <<EOF
# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi
EOF
    echo "/root/.bashrc created"

    cat > /root/.bash_profile <<EOF
# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
# User specific environment and startup programs
PATH=\$PATH:\$HOME/bin
export PATH
EOF
    echo "/root/.bash_profile created"

}

#---------------------------------------
set_sshd_config() {
    sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

    echo "sshd_config updated"
}

#---------------------------------------
set_network() {
    mkdir -p /etc/sysconfig/network-scripts

    cat > /etc/sysconfig/network <<EOF
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF
    echo "/etc/sysconfig/network updated."

    cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DEVICE="eth0"
NM_CONTROLLED="yes"
ONBOOT=yes
TYPE=Ethernet
BOOTPROTO=dhcp
DEFROUTE=yes
PEERDNS=yes
PEERROUTES=yes
IPV4_FAILURE_FATAL=yes
IPV6INIT=no
EOF
    echo "ifcfg-eth0 updated."
}

#---------------------------------------
set_fstab() {
    cat > /etc/fstab <<EOF
LABEL=_boot             /boot                   ext4    defaults        1 1
LABEL=_root             /                       ext4    defaults        1 1
tmpfs                   /dev/shm                tmpfs   defaults        0 0
devpts                  /dev/pts                devpts  gid=5,mode=620  0 0
sysfs                   /sys                    sysfs   defaults        0 0
proc                    /proc                   proc    defaults        0 0
EOF

    echo "/etc/fstab updated."
}

#---------------------------------------
set_selinux() {
    sed -i '/^SELINUX=/d' /etc/sysconfig/selinux
    echo "SELINUX=disabled" >> /etc/sysconfig/selinux
    touch /.autorelabel

    echo "/etc/sysconfig/selinux updated."
}

#---------------------------------------
set_chkconfig() {
    /sbin/chkconfig iptables off || true
    /sbin/chkconfig ip6tables off || true
    /sbin/chkconfig sendmail off || true
    /sbin/chkconfig 

    echo "chkconfig set."
}

#---------------------------------------
set_grub() {
    VMLINUZ_FILE=`(cd /boot/ && ls -1 vmlinuz* | head -1)`
    INITRAMFS_FILE=`(cd /boot/ && ls -1 initramfs-*.img | head -1)`

    # Create /boot/grub/grub.conf
    cat > /boot/grub/grub.conf <<EOF
default=0
timeout=1
serial --unit=0 --speed=115200
terminal --timeout=1 serial console
title CentOS ${CENTOS_VERSION} (Custom AMI)
        root (hd0,0)
        kernel /boot/${VMLINUZ_FILE} ro root=LABEL=_root console=hvc0 crashkernel=no SYSFONT=latarcyrheb-sun16 LANG=en_US.UTF-8 KEYTABLE=us
        initrd /boot/${INITRAMFS_FILE}
EOF

    cd /boot/grub/ && ln -sf grub.conf menu.lst

    echo "/boot/grub/grub.conf and menu.lst set."
}

#---------------------------------------
set_cloud() {
    sed -i 's/^disable_root:.*/disable_root: 0/' /etc/cloud/cloud.cfg

    echo "/etc/cloud/cloud.cfg updated."
}

ALL="
set_boot_symlink
set_root_user
set_sshd_config
set_network
set_fstab
set_selinux
set_chkconfig
set_grub
set_cloud
"

#---------------------------------------
usage() {
    cat <<EOF
Warning: Must run only inside chroot image.
EOF
    exit 1
}

#---------------------------------------
# START MAIN
#---------------------------------------
[ `id -u` -eq 0 ] || abort "Must run as root"
[ $# -ne 0 ] || usage

if [ "$1" = "all" ]; then
    for cmd in $ALL; do $cmd || true; done
else
    for cmd in $*; do $cmd || true; done
fi
