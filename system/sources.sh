#!/bin/bash

# 检查是否以 root 用户运行脚本
if [ "$EUID" -ne 0 ]; then
	    echo "请以 root 用户运行此脚本，可使用 sudo 命令。"
	        exit 1
fi

# 获取 Ubuntu 系统版本代号
release=$(lsb_release -cs)

# 定义官方源文件路径
source_file="/etc/apt/sources.list"
# 定义备份文件路径
backup_file="${source_file}.bak"

# 备份原官方源
cp "$source_file" "$backup_file"
echo "已备份原官方源到 $backup_file"

# 根据系统版本选择对应的阿里源
case $release in
	    "xenial")
		            cat <<EOF > "$source_file"
# 阿里源 - Ubuntu 16.04 Xenial Xerus
deb http://mirrors.aliyun.com/ubuntu/ xenial main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ xenial-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-proposed main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse
EOF
        ;;
	    "bionic")
		            cat <<EOF > "$source_file"
# 阿里源 - Ubuntu 18.04 Bionic Beaver
deb http://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic-updates main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ bionic-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic-proposed main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ bionic-backports main restricted universe multiverse
EOF
        ;;
	    "focal")
		            cat <<EOF > "$source_file"
# 阿里源 - Ubuntu 20.04 Focal Fossa
deb http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
EOF
        ;;
	    "jammy")
		            cat <<EOF > "$source_file"
# 阿里源 - Ubuntu 22.04 Jammy Jellyfish
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ jammy-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-proposed main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF
        ;;
	    *)
		            echo "不支持的 Ubuntu 版本: $release，请手动更新源。"
			            exit 1
				            ;;
			    esac

			    echo "已将官方源替换为阿里源（$release 版本）"

			    # 更新软件包索引以检查替换是否成功
			    echo "正在更新软件包索引以检查替换是否成功..."
			    apt-get update
if [ $? -eq 0 ]; then
    echo "源替换成功，软件包索引更新正常。"
else
    echo "源替换可能失败，软件包索引更新出错。你可以恢复备份源：cp $backup_file $source_file"
fi
