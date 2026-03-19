#!/bin/bash

# 检查是否以 root 用户运行脚本
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 用户运行此脚本，可使用 sudo 命令。"
    exit 1
fi

# 判断是否连接公网
echo "正在检查网络连接..."
ping -c 3 8.8.8.8 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "未检测到公网连接，请检查网络设置。"
    exit 1
fi
echo "网络连接正常，可以继续操作。"

# 卸载 nouveau 模块
echo "正在卸载 nouveau 模块..."
modprobe -r nouveau
if [ $? -ne 0 ]; then
    echo "卸载 nouveau 模块时出现问题，但不影响后续流程，继续执行。"
fi

# 检查当前目录下是否存在 nvidia-last.run 文件
if [ ! -f "nvidia-last.run" ]; then
    # 下载 NVIDIA 驱动文件
    echo "开始下载 NVIDIA 驱动文件..."
    wget http://amax.xyz:10002/driver/nvidia-last.run
    if [ $? -ne 0 ]; then
        echo "驱动文件下载失败，请检查网络或下载地址。"
        exit 1
    fi
else
    echo "已检测到本地的 nvidia-last.run 文件，跳过下载步骤。"
fi

# 为驱动文件添加执行权限
chmod +x nvidia-last.run

# 将 nouveau 模块添加到系统 blacklist
echo "将 nouveau 模块添加到系统 blacklist..."
echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist-nouveau.conf
update-initramfs -u

# 停止图形界面
echo "停止图形界面以进行驱动安装..."
systemctl stop gdm

# 安装 NVIDIA 驱动
echo "开始安装 NVIDIA 驱动..."
./nvidia-last.run --ui=none --no-questions --accept-license --no-nouveau-check --no-x-check 
install_status=$?
if [ $install_status -ne 0 ]; then
    echo "NVIDIA 驱动安装失败，请查看错误信息进行排查。"
    # 恢复图形界面
    systemctl start gdm
    exit 1
fi

# 恢复图形界面
echo "驱动安装成功，恢复图形界面..."
systemctl start gdm

# 提示用户重启系统
read -p "NVIDIA 驱动已成功安装，建议重启系统以使驱动生效。是否立即重启？(y/n): " answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    reboot
else
    echo "请在适当的时候手动重启系统。"
fi
