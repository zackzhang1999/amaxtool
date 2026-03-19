#!/bin/bash
#===============================================================================
# AMAX Tool - Installation Script
# Description: Setup script for AMAX Tool
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请以 root 用户运行此脚本"
        exit 1
    fi
}

# Check bash syntax
check_syntax() {
    log_info "检查脚本语法..."
    local errors=0
    
    while IFS= read -r -d '' file; do
        if ! bash -n "$file" 2>/dev/null; then
            log_error "语法错误: $file"
            ((errors++))
        fi
    done < <(find "$SCRIPT_DIR" -name "*.sh" -type f -print0)
    
    if [[ $errors -eq 0 ]]; then
        log_info "所有脚本语法检查通过"
    else
        log_error "发现 $errors 个脚本有语法错误"
        return 1
    fi
}

# Set permissions
set_permissions() {
    log_info "设置文件权限..."
    
    # Main script
    chmod 755 "$SCRIPT_DIR/bin/amax-tool"
    
    # Library files
    chmod 644 "$SCRIPT_DIR/lib"/*.sh
    
    # Module scripts
    find "$SCRIPT_DIR/modules" -name "run.sh" -exec chmod 755 {} \;
    
    # Tools
    chmod 755 "$SCRIPT_DIR/tools"/*
    
    log_info "权限设置完成"
}

# Create symlink
create_symlink() {
    local target="/usr/local/bin/amax-tool"
    
    if [[ -L "$target" ]]; then
        rm -f "$target"
    fi
    
    ln -sf "$SCRIPT_DIR/bin/amax-tool" "$target"
    log_info "创建快捷方式: $target"
}

# Create log directory
setup_logdir() {
    local logdir="/var/log/amax-tool"
    if [[ ! -d "$logdir" ]]; then
        mkdir -p "$logdir"
        chmod 755 "$logdir"
        log_info "创建日志目录: $logdir"
    fi
}

# Install dependencies
install_deps() {
    log_info "检查依赖..."
    
    local deps=("fio" "ipmitool" "stress-ng" "screen" "arp-scan" "smartmontools" "pciutils" "ethtool")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "缺失的依赖: ${missing[*]}"
        if command -v apt-get &>/dev/null; then
            log_info "尝试安装缺失的依赖..."
            apt-get update
            apt-get install -y "${missing[@]}"
        else
            log_warn "请手动安装上述依赖"
        fi
    else
        log_info "所有依赖已安装"
    fi
}

# Main
main() {
    echo "==================================="
    echo "  AMAX Tool 安装脚本"
    echo "==================================="
    echo ""
    
    check_root
    check_syntax
    set_permissions
    setup_logdir
    create_symlink
    
    echo ""
    log_info "安装完成!"
    echo ""
    echo "使用方法:"
    echo "  sudo amax-tool        # 运行主程序"
    echo "  sudo $SCRIPT_DIR/bin/amax-tool  # 或者直接运行"
    echo ""
    
    # Ask to install dependencies
    read -rp "是否安装系统依赖? [y/N]: " install
    if [[ "$install" =~ ^[Yy]$ ]]; then
        install_deps
    fi
}

main "$@"
