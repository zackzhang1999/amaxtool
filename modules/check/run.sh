#!/bin/bash
#===============================================================================
# AMAX Tool - Environment Check Module
# Description: Check runtime dependencies and environment
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Dependencies list
readonly REQUIRED_COMMANDS=(
    "fio"
    "ipmitool"
    "stress-ng"
    "screen"
    "storcli64"
    "arp-scan"
)

readonly REQUIRED_PYTHON_MODULES=(
    "GPUtil"
)

#-------------------------------------------------------------------------------
# Check Commands
#-------------------------------------------------------------------------------
check_commands() {
    print_header "检查依赖命令"
    
    local all_ok=true
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        printf "  %-20s " "$cmd"
        if check_command "$cmd"; then
            echo_green "[OK]"
        else
            echo_red "[MISSING]"
            all_ok=false
        fi
        sleep 0.2
    done
    
    print_separator
    
    if [[ "$all_ok" == "false" ]]; then
        echo_yellow "提示: 部分命令缺失，某些功能可能无法使用"
        echo "缺失的命令可以通过以下方式安装:"
        echo "  apt-get install fio ipmitool stress-ng screen arp-scan"
        echo "  storcli64 需要从官网下载"
    else
        log_success "所有依赖命令已安装"
    fi
}

#-------------------------------------------------------------------------------
# Check Python Modules
#-------------------------------------------------------------------------------
check_python() {
    print_header "检查 Python 模块"
    
    if ! check_command python3; then
        echo_red "Python3 未安装"
        return 1
    fi
    
    echo "Python 版本: $(python3 --version)"
    echo ""
    
    local all_ok=true
    
    for mod in "${REQUIRED_PYTHON_MODULES[@]}"; do
        printf "  %-20s " "$mod"
        if check_python_module "$mod"; then
            echo_green "[OK]"
        else
            echo_red "[MISSING]"
            all_ok=false
            
            if confirm "是否安装 $mod?"; then
                install_python_module "$mod"
            fi
        fi
    done
    
    print_separator
    
    if [[ "$all_ok" == "true" ]]; then
        log_success "所有 Python 模块已安装"
    fi
}

#-------------------------------------------------------------------------------
# Check Hardware
#-------------------------------------------------------------------------------
check_hardware() {
    print_header "硬件检测"
    
    init_hw_info
    
    echo "服务器 SN: ${SERVERSN:-Unknown}"
    echo "RAID SN: ${RAIDSN:-Unknown}"
    echo ""
    
    # Check RAID
    printf "  RAID 卡              "
    if [[ -n "$HW_RAID" ]]; then
        echo_green "[检测到]"
        echo "    $HW_RAID"
    else
        echo_yellow "[未检测到]"
    fi
    
    # Check NVIDIA GPU
    printf "  NVIDIA GPU           "
    if [[ -n "$HW_NVIDIA" ]]; then
        echo_green "[检测到]"
        echo "    $HW_NVIDIA"
    else
        echo_yellow "[未检测到]"
    fi
    
    # Check IPMI
    printf "  IPMI                 "
    if [[ -c /dev/ipmi0 ]]; then
        echo_green "[OK]"
    else
        echo_yellow "[未检测到]"
    fi
    
    print_separator
}

#-------------------------------------------------------------------------------
# Check Network
#-------------------------------------------------------------------------------
check_network() {
    print_header "网络检查"
    
    printf "  外网连接             "
    if check_internet; then
        echo_green "[OK]"
    else
        echo_yellow "[不通]"
    fi
    
    # Show network interfaces
    echo ""
    echo "网络接口:"
    ip -br addr show 2>/dev/null | grep -v "lo" | while read -r line; do
        echo "    $line"
    done
    
    print_separator
}

#-------------------------------------------------------------------------------
# Full Check
#-------------------------------------------------------------------------------
run_full_check() {
    print_header "AMAX 服务器运行环境检测"
    echo "检测时间: $(date)"
    echo ""
    
    check_hardware
    check_commands
    check_python
    check_network
    
    print_header "检测完成"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
run_full_check

# Export results
echo ""
read -rp "按回车键继续..."
