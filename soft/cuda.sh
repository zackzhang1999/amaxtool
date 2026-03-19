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
apt-get install -y build-essential dkms freeglut3-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa libglu1-mesa-dev

# 添加 NVIDIA CUDA 仓库
echo "正在添加 NVIDIA CUDA 仓库..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
wget https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-$distribution.pin
mv cuda-$distribution.pin /etc/apt/preferences.d/cuda-repository-pin-600
apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/7fa2af80.pub
echo "deb http://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64 /" | tee /etc/apt/sources.list.d/cuda.list

# 更新软件包列表以包含 CUDA 仓库
echo "正在更新软件包列表以包含 CUDA 仓库..."
apt-get update

# 安装最新版本的 CUDA
echo "正在安装最新版本的 CUDA..."
apt-get install -y cuda

# 配置环境变量
echo "正在配置 CUDA 环境变量..."
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc

# 安装 NCCL
echo "正在安装 NCCL..."
apt-get install -y libnccl2 libnccl-dev

# 提示手动安装 cuDNN
echo "由于授权限制，cuDNN 无法自动安装。请按照以下步骤手动安装："
echo "1. 访问 https://developer.nvidia.com/cudnn 并登录你的 NVIDIA 开发者账号。"
echo "2. 下载适合你 CUDA 版本的 cuDNN 库（cuDNN Library for Linux）。"
echo "3. 解压下载的文件，假设解压后的目录为 'cuda'。"
echo "4. 执行以下命令将文件复制到 CUDA 安装目录："
echo "   sudo cp cuda/include/cudnn*.h /usr/local/cuda/include"
echo "   sudo cp cuda/lib64/libcudnn* /usr/local/cuda/lib64"
echo "   sudo chmod a+r /usr/local/cuda/include/cudnn*.h /usr/local/cuda/lib64/libcudnn*"

echo "CUDA 和 NCCL 安装完成，请按照提示手动安装 cuDNN。"
