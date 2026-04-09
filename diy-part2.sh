#!/bin/bash

# 依赖于 parted losetup resize2fs 自动扩容
mkdir -p ./package/base-files/files/etc/uci-defaults || true

cat <<"EOF" >./package/base-files/files/etc/uci-defaults/70-rootpt-resize
#!/bin/sh
# /etc/uci-defaults/70-rootpt-resize - safely resize root partition

LOCKFILE=/var/lock/root-resize

if [ ! -e /etc/rootpt-resize ] && type parted >/dev/null 2>&1 && lock -n $LOCKFILE; then
    logger -t root-resize "Starting root partition resize"

    ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk '$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
    ROOT_DISK="/dev/$(basename "${ROOT_BLK%/*}")"
    ROOT_PART="$(echo "${ROOT_BLK}" | sed -n 's/.*[^0-9]\([0-9]\+\)$/\1/p')"

    if [ -z "$ROOT_PART" ]; then
        logger -t root-resize "Error: cannot determine root partition number"
        exit 1
    fi

    logger -t root-resize "Resizing partition ${ROOT_DISK}${ROOT_PART} to 100%"
    parted -f -s "$ROOT_DISK" resizepart "$ROOT_PART" 100% || {
        logger -t root-resize "Error: parted resize failed"
        exit 1
    }

    mount_root done
    touch /etc/rootpt-resize

    if [ -e /boot/cmdline.txt ]; then
        NEW_UUID=$(blkid -o value -s PARTUUID "${ROOT_DISK}${ROOT_PART}")
        if [ -n "$NEW_UUID" ]; then
            sed -i "s/PARTUUID=[^ ]*/PARTUUID=${NEW_UUID}/" /boot/cmdline.txt
            logger -t root-resize "Updated /boot/cmdline.txt with new PARTUUID"
        else
            logger -t root-resize "Warning: blkid returned empty PARTUUID"
        fi
    fi

    logger -t root-resize "Root partition resize complete, rebooting"
    reboot
fi

exit 1
EOF

cat <<"EOF" >./package/base-files/files/etc/uci-defaults/80-rootfs-resize
#!/bin/sh
# /etc/uci-defaults/80-rootfs-resize - safely resize root filesystem

LOCKFILE=/var/lock/root-resize

if [ ! -e /etc/rootfs-resize ] && [ -e /etc/rootpt-resize ] && type losetup >/dev/null 2>&1 && type resize2fs >/dev/null 2>&1 && lock -n $LOCKFILE; then
    logger -t root-resize "Starting root filesystem resize"

    ROOT_BLK="$(readlink -f /sys/dev/block/"$(awk '$9=="/dev/root"{print $3}' /proc/self/mountinfo)")"
    ROOT_DEV="/dev/${ROOT_BLK##*/}"

    LOOP_DEV=$(awk '$5=="/overlay"{print $9}' /proc/self/mountinfo)
    if [ -z "$LOOP_DEV" ]; then
        LOOP_DEV=$(losetup --show -f "$ROOT_DEV") || {
            logger -t root-resize "Error: failed to setup loop device"
            exit 1
        }
        logger -t root-resize "Created loop device $LOOP_DEV for $ROOT_DEV"
    else
        logger -t root-resize "Using existing loop device $LOOP_DEV"
    fi

    resize2fs -f "$LOOP_DEV" || {
        logger -t root-resize "Error: resize2fs failed"
        exit 1
    }

    mount_root done
    touch /etc/rootfs-resize
    logger -t root-resize "Root filesystem resize complete, rebooting"
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
