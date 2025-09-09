#!/bin/bash

set -ex

sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
sed -i 's/OpenWrt/Zero/g' package/base-files/files/bin/config_generate
sed -i 's/0.openwrt.pool.ntp.org/0.ntp.aliyun.com/g' package/base-files/files/bin/config_generate

echo 'src-git mypkg https://github.com/zfdx123/packages.git;packages' >>feeds.conf.default
