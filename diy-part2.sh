#!/bin/bash

# 依赖于 parted losetup resize2fs 自动扩容
mkdir -p ./package/base-files/files/etc/uci-defaults || true

cat <<"EOF" >./package/base-files/files/etc/uci-defaults/70-rootpt-resize
#!/bin/sh

if [ ! -e /etc/rootpt-resize ] && type parted > /dev/null && lock -n /var/lock/root-resize
then
    ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk -e '$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
    ROOT_DISK="/dev/$(basename "${ROOT_BLK%/*}")"
    ROOT_PART="${ROOT_BLK##*[^0-9]}"
    parted -f -s "${ROOT_DISK}" \
    resizepart "${ROOT_PART}" 100%
    mount_root done
    touch /etc/rootpt-resize
 
    if [ -e /boot/cmdline.txt ]
    then 
        NEW_UUID=`blkid ${ROOT_DISK}p${ROOT_PART} | sed -n 's/.*PARTUUID="\([^"]*\)".*/\1/p'`
        sed -i "s/PARTUUID=[^ ]*/PARTUUID=${NEW_UUID}/" /boot/cmdline.txt
    fi
    
    reboot
fi

exit 1
EOF

cat <<"EOF" >./package/base-files/files/etc/uci-defaults/80-rootfs-resize
#!/bin/sh

if [ ! -e /etc/rootfs-resize ] && [ -e /etc/rootpt-resize ] && type losetup > /dev/null && type resize2fs > /dev/null && lock -n /var/lock/root-resize
then
    ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk -e '$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
    ROOT_DEV="/dev/${ROOT_BLK##*/}"
    LOOP_DEV="$(awk -e '$5=="/overlay"{print $9}' /proc/self/mountinfo)"
    
    if [ -z "${LOOP_DEV}" ]
    then
        LOOP_DEV="$(losetup -f)"
        losetup "${LOOP_DEV}" "${ROOT_DEV}"
    fi
    
    resize2fs -f "${LOOP_DEV}"
    mount_root done
    touch /etc/rootfs-resize
    
    reboot
fi

exit 1
EOF

chmod +x ./package/base-files/files/etc/uci-defaults/70-rootpt-resize
chmod +x ./package/base-files/files/etc/uci-defaults/80-rootfs-resize

cat <<"EOF" >>./package/base-files/files/etc/sysupgrade.conf
/etc/uci-defaults/70-rootpt-resize
/etc/uci-defaults/80-rootfs-resize
EOF
