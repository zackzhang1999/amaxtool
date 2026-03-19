#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
	    echo "请以 root 权限运行此脚本。"
	        exit 1
fi

# 更新系统软件包列表
echo "正在更新系统软件包列表..."
apt-get update

# 安装必要的依赖包
echo "正在安装必要的依赖包..."
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# 添加 Docker 的官方 GPG 密钥
echo "正在添加 Docker 的官方 GPG 密钥..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 设置 Docker 稳定版仓库
echo \
	  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
	    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新软件包列表以包含 Docker 仓库
echo "正在更新软件包列表以包含 Docker 仓库..."
apt-get update

# 安装最新版本的 Docker 引擎
echo "正在安装最新版本的 Docker 引擎..."
apt-get install -y docker-ce docker-ce-cli containerd.io

# 验证 Docker 是否安装成功
if [ $? -eq 0 ]; then
	    echo "Docker 安装成功。"
    else
	        echo "Docker 安装失败，请检查错误信息。"
		    exit 1
fi

# 启动 Docker 服务并设置为开机自启
echo "正在启动 Docker 服务并设置为开机自启..."
systemctl start docker
systemctl enable docker

# 添加 NVIDIA Container Toolkit 仓库
echo "正在添加 NVIDIA Container Toolkit 仓库..."
curl -fsSL https://mirrors.ustc.edu.cn/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
&& curl -s -L https://mirrors.ustc.edu.cn/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
sed 's#deb https://nvidia.github.io#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://mirrors.ustc.edu.cn#g' | \
sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 更新软件包列表以包含 NVIDIA Container Toolkit 仓库
echo "正在更新软件包列表以包含 NVIDIA Container Toolkit 仓库..."
apt-get update

# 安装 NVIDIA Container Toolkit
echo "正在安装 NVIDIA Container Toolkit..."
apt-get install -y nvidia-container-toolkit

# 配置 Docker 以使用 NVIDIA Container Toolkit
echo "正在配置 Docker 以使用 NVIDIA Container Toolkit..."
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# 验证 NVIDIA GPU 支持是否安装成功
echo "正在验证 NVIDIA GPU 支持是否安装成功..."
docker run --rm --gpus all nvidia/cuda:12.0.1-base-ubuntu22.04 nvidia-smi
if [ $? -eq 0 ]; then
	    echo "NVIDIA GPU 支持安装成功。"
    else
	        echo "NVIDIA GPU 支持安装失败，请检查错误信息。"
		    exit 1
fi

echo "所有安装和配置已完成。"
