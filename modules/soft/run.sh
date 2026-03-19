#!/bin/bash
#===============================================================================
# AMAX Tool - Software Installation Module
# Description: Install various software packages
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/utils.sh"

#-------------------------------------------------------------------------------
# NVIDIA Driver Installation
#-------------------------------------------------------------------------------
install_nvidia_driver() {
    print_header "安装 NVIDIA 驱动"
    
    check_root || return 1
    
    # Check network
    if ! check_internet; then
        log_error "未检测到网络连接"
        return 1
    fi
    
    # Check GPU
    if [[ -z "$HW_NVIDIA" ]]; then
        log_warn "未检测到 NVIDIA GPU"
        confirm "是否继续安装?" || return 1
    fi
    
    # Disable nouveau
    log_info "禁用 nouveau 驱动..."
    modprobe -r nouveau 2>/dev/null || true
    
    # Download driver
    local driver_file="$SCRIPT_DIR/tools/nvidia-driver.run"
    if [[ ! -f "$driver_file" ]]; then
        log_info "下载驱动文件..."
        wget -O "$driver_file" "http://amax.xyz:10002/driver/nvidia-last.run" 2>/dev/null || {
            log_error "下载失败"
            return 1
        }
    fi
    
    chmod +x "$driver_file"
    
    # Blacklist nouveau
    cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u
    
    # Stop display manager
    systemctl stop gdm 2>/dev/null || systemctl stop gdm3 2>/dev/null || true
    
    # Install driver
    log_info "安装驱动..."
    "$driver_file" --ui=none --no-questions --accept-license \
        --no-nouveau-check --no-x-check
    
    if [[ $? -eq 0 ]]; then
        log_success "驱动安装成功"
        confirm "是否立即重启系统?" && reboot
    else
        log_error "驱动安装失败"
        systemctl start gdm 2>/dev/null || systemctl start gdm3 2>/dev/null || true
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Anaconda Installation
#-------------------------------------------------------------------------------
install_anaconda() {
    print_header "安装 Anaconda"
    
    local download_dir="$HOME/Downloads"
    mkdir -p "$download_dir"
    
    log_info "获取最新 Anaconda 下载链接..."
    local url
    url=$(wget -qO- https://www.anaconda.com/products/distribution 2>/dev/null | \
        grep -oP 'https://repo.anaconda.com/archive/Anaconda3-\d{4}\.\d{2}-Linux-x86_64.sh' | head -1)
    
    if [[ -z "$url" ]]; then
        log_error "无法获取下载链接"
        return 1
    fi
    
    local installer="$download_dir/$(basename "$url")"
    
    log_info "下载 Anaconda..."
    wget -O "$installer" "$url" 2>/dev/null || {
        log_error "下载失败"
        return 1
    }
    
    log_info "安装 Anaconda..."
    bash "$installer" -b -p "$HOME/anaconda3"
    
    # Add to PATH
    if ! grep -q "anaconda3/bin" "$HOME/.bashrc"; then
        echo 'export PATH="$HOME/anaconda3/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    
    # Setup conda
    export PATH="$HOME/anaconda3/bin:$PATH"
    
    log_info "创建 conda 环境..."
    conda create -y -n deeplearning python=3.9 2>/dev/null || {
        log_error "创建环境失败"
        return 1
    }
    
    # shellcheck source=/dev/null
    source activate deeplearning 2>/dev/null || conda activate deeplearning
    
    log_info "安装 PyTorch..."
    pip install torch torchvision torchaudio 2>/dev/null
    pip install scikit-learn pandas matplotlib tqdm 2>/dev/null
    
    rm -f "$installer"
    log_success "Anaconda 安装完成"
    echo "请运行 'source ~/.bashrc' 或重新登录以激活环境"
}

#-------------------------------------------------------------------------------
# Docker Installation
#-------------------------------------------------------------------------------
install_docker() {
    print_header "安装 Docker"
    
    check_root || return 1
    
    log_info "更新软件包列表..."
    apt-get update
    
    log_info "安装依赖包..."
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    log_info "添加 Docker GPG 密钥..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    log_info "添加 Docker 仓库..."
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    
    log_info "安装 Docker..."
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    log_info "启动 Docker 服务..."
    systemctl start docker
    systemctl enable docker
    
    # NVIDIA Container Toolkit
    if [[ -n "$HW_NVIDIA" ]]; then
        log_info "安装 NVIDIA Container Toolkit..."
        
        curl -fsSL https://mirrors.ustc.edu.cn/libnvidia-container/gpgkey | \
            gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        
        curl -s -L https://mirrors.ustc.edu.cn/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://nvidia.github.io#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://mirrors.ustc.edu.cn#g' | \
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        
        apt-get update
        apt-get install -y nvidia-container-toolkit
        
        nvidia-ctk runtime configure --runtime=docker
        systemctl restart docker
        
        # Test
        docker run --rm --gpus all nvidia/cuda:12.0.1-base-ubuntu22.04 nvidia-smi 2>/dev/null && \
            log_success "GPU 支持安装成功"
    fi
    
    log_success "Docker 安装完成"
}

#-------------------------------------------------------------------------------
# Mellanox Mode Switch
#-------------------------------------------------------------------------------
switch_mellanox_mode() {
    local mode="$1"
    
    if ! check_command mst; then
        log_error "未安装 Mellanox 工具 (mst)"
        return 1
    fi
    
    mst start
    
    for mst_dev in /dev/mst/*; do
        [[ -e "$mst_dev" ]] || continue
        log_info "配置 $mst_dev..."
        
        if [[ "$mode" == "ib" ]]; then
            mlxconfig -y -d "$mst_dev" set LINK_TYPE_P1=1 LINK_TYPE_P2=1 2>/dev/null
        else
            mlxconfig -y -d "$mst_dev" set LINK_TYPE_P1=2 LINK_TYPE_P2=2 2>/dev/null
        fi
    done
    
    log_success "模式切换完成，请重启生效"
}

#-------------------------------------------------------------------------------
# Mellanox PXE Enable
#-------------------------------------------------------------------------------
enable_mellanox_pxe() {
    if ! check_command mst; then
        log_error "未安装 Mellanox 工具"
        return 1
    fi
    
    mst start
    
    for mst_dev in /dev/mst/*; do
        [[ -e "$mst_dev" ]] || continue
        [[ "$mst_dev" == *".1" ]] && continue
        
        log_info "配置 $mst_dev..."
        mlxconfig -d "$mst_dev" -y set EXP_ROM_UEFI_x86_ENABLE=1 2>/dev/null
        mlxconfig -d "$mst_dev" -y set EXP_ROM_PXE_ENABLE=1 2>/dev/null
        mlxconfig -d "$mst_dev" q 2>/dev/null | grep "EXP_ROM"
    done
    
    log_success "PXE 支持已启用"
}

#-------------------------------------------------------------------------------
# Menu
#-------------------------------------------------------------------------------
show_menu() {
    while true; do
        clear
        print_header "软件安装"
        echo "  1. 安装 NVIDIA 驱动"
        echo "  2. 安装 Anaconda + PyTorch"
        echo "  3. 安装 Docker + GPU 支持"
        echo "  4. Mellanox 切换至 IB 模式"
        echo "  5. Mellanox 切换至 ETH 模式"
        echo "  6. 启用 Mellanox PXE 支持"
        echo "  b. 返回主菜单"
        print_separator
        
        read -rp "请选择: " choice
        case "$choice" in
            1) install_nvidia_driver; read -r ;;
            2) install_anaconda; read -r ;;
            3) install_docker; read -r ;;
            4) switch_mellanox_mode ib; read -r ;;
            5) switch_mellanox_mode eth; read -r ;;
            6) enable_mellanox_pxe; read -r ;;
            b|B) break ;;
            *) log_warn "无效选择"; sleep 1 ;;
        esac
    done
}

show_menu
