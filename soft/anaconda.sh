#!/bin/bash

# 定义下载目录
DOWNLOAD_DIR="$HOME/Downloads"
mkdir -p "$DOWNLOAD_DIR"

# 下载最新版 Anaconda
ANACONDA_URL=$(wget -qO- https://www.anaconda.com/products/distribution | grep -oP 'https://repo.anaconda.com/archive/Anaconda3-\d{4}\.\d{2}-Linux-x86_64.sh' | head -n 1)
ANACONDA_INSTALLER="$DOWNLOAD_DIR/$(basename $ANACONDA_URL)"
wget -O "$ANACONDA_INSTALLER" "$ANACONDA_URL"

# 安装 Anaconda
bash "$ANACONDA_INSTALLER" -b -p "$HOME/anaconda3"
echo 'export PATH="$HOME/anaconda3/bin:$PATH"' >> "$HOME/.bashrc"
source "$HOME/.bashrc"

# 创建新的 conda 环境
conda create -y -n deeplearning python=3.9
conda activate deeplearning

# 安装 PyTorch 及常用深度学习模块
pip install torch torchvision torchaudio
pip install scikit-learn pandas matplotlib tqdm

# 清理下载文件
rm "$ANACONDA_INSTALLER"

echo "Anaconda、PyTorch 和常用深度学习模块已安装完成。"    
