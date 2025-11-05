#!/bin/bash
#
# Copyright (c) 2021-2024, NVIDIA CORPORATION.  All rights reserved.
#
# NVIDIA CORPORATION and its licensors retain all intellectual property
# and proprietary rights in and to this software, related documentation
# and any modifications thereto.  Any use, reproduction, disclosure or
# distribution of this software and related documentation without an express
# license agreement from NVIDIA CORPORATION is strictly prohibited.

set -e

USER_NAME="admin"
USER_HOME="/home/${USER_NAME}"

HOST_USER_UID="${HOST_USER_UID:=1000}"
HOST_USER_GID="${HOST_USER_GID:=1000}"

print_info() {
    echo "workspace-entrypoint: $1"
}

# 1. multicastを有効化
/usr/sbin/ip link set lo multicast on

# 2. sysctlの値を直接書き込む 
sysctl -w net.core.rmem_max=2147483647
sysctl -w net.ipv4.ipfrag_time=3
sysctl -w net.ipv4.ipfrag_high_thresh=134217728

print_info "Custom network settings applied."

export HOME=${USER_HOME}
chown -R ${HOST_USER_UID}:${HOST_USER_GID} ${USER_HOME}

# joy_nodeのために、ジョイスティックデバイスへのアクセス権を設定
# js0が存在する場合はそのGIDを使用、存在しない場合は101を使用
if [ -e /dev/input/js0 ]; then
    HOST_INPUT_GID=$(stat -c '%g' /dev/input/js0)
    print_info "Detected input device GID: ${HOST_INPUT_GID}"
else
    HOST_INPUT_GID=101
    print_info "No input device found. Using default GID: ${HOST_INPUT_GID}"
fi

# 該当GIDを持つグループを確認
EXISTING_GROUP=$(getent group ${HOST_INPUT_GID} | cut -d: -f1)

if [ -n "${EXISTING_GROUP}" ]; then
    print_info "Adding user '${USER_NAME}' to existing group '${EXISTING_GROUP}' (GID: ${HOST_INPUT_GID})"
    usermod -aG ${EXISTING_GROUP} ${USER_NAME}
else
    # 該当GIDのグループがない場合は新規作成
    print_info "Creating input group with GID ${HOST_INPUT_GID}"
    groupadd -g ${HOST_INPUT_GID} input
    usermod -aG input ${USER_NAME}
    print_info "Added user '${USER_NAME}' to input group"
fi

# jetracer_nodeのために、GPIOデバイス(/dev/gpiochip0)へのアクセス権を設定
if [ -c /dev/gpiochip0 ]; then
    HOST_GPIO_GID=999 # GIDを999に固定
    print_info "Using hardcoded GPIO GID: ${HOST_GPIO_GID}"

    # 該当GIDを持つグループがコンテナ内に存在するか確認
    EXISTING_GPIO_GROUP=$(getent group ${HOST_GPIO_GID} | cut -d: -f1)

    if [ -n "${EXISTING_GPIO_GROUP}" ]; then
        # 存在する場合、そのグループにユーザーを追加
        print_info "Adding user '${USER_NAME}' to existing GPIO group '${EXISTING_GPIO_GROUP}'"
        usermod -aG ${EXISTING_GPIO_GROUP} ${USER_NAME}
    else
        # 存在しない場合、'gpio'という名前でグループを新規作成
        print_info "Creating gpio group with GID ${HOST_GPIO_GID}"
        groupadd -g ${HOST_GPIO_GID} gpio
        usermod -aG gpio ${USER_NAME}
        print_info "Added user '${USER_NAME}' to gpio group"
    fi
else
    # デバイスが見つからない場合は警告を表示
    print_info "WARNING: GPIO device /dev/gpiochip0 not found. Skipping permission setup."
fi

# jetracer_nodeのために、I2Cデバイス(/dev/i2c-7)へのアクセス権を設定
if [ -c /dev/i2c-7 ]; then
    HOST_I2C_GID=$(stat -c '%g' /dev/i2c-7)
    print_info "Detected I2C device GID: ${HOST_I2C_GID}"

    # 該当GIDを持つグループがコンテナ内に存在するか確認
    EXISTING_I2C_GROUP=$(getent group ${HOST_I2C_GID} | cut -d: -f1)

    if [ -n "${EXISTING_I2C_GROUP}" ]; then
        # 存在する場合、そのグループにユーザーを追加
        print_info "Adding user '${USER_NAME}' to existing I2C group '${EXISTING_I2C_GROUP}' (GID: ${HOST_I2C_GID})"
        usermod -aG ${EXISTING_I2C_GROUP} ${USER_NAME}
    else
        # 存在しない場合、'i2c'という名前でグループを新規作成
        print_info "Creating i2c group with GID ${HOST_I2C_GID}"
        groupadd -g ${HOST_I2C_GID} i2c
        usermod -aG i2c ${USER_NAME}
        print_info "Added user '${USER_NAME}' to i2c group"
    fi
else
    # デバイスが見つからない場合は警告を表示
    print_info "WARNING: I2C device /dev/i2c-7 not found. Skipping permission setup."
fi

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:=0}"
print_info "Using ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"


exec gosu ${USER_NAME} "$@"