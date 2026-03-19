#!/bin/bash
#===============================================================================
# AMAX Tool - System Information Module
# Description: Display comprehensive system information
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/utils.sh"

init_hw_info

#-------------------------------------------------------------------------------
# System Information Functions
#-------------------------------------------------------------------------------
show_basic_info() {
    print_header "基本信息"
    echo "服务器 SN: ${SERVERSN:-Unknown}"
    echo "操作系统: $(cat /etc/issue 2>/dev/null | head -1 || echo 'Unknown')"
    echo "内核版本: $(uname -r)"
    echo "服务器型号: $(dmidecode -s system-product-name 2>/dev/null || echo 'Unknown')"
    print_separator
}

show_cpu_info() {
    print_header "CPU 信息"
    echo "型号: $(get_cpu_info)"
    echo "核心数: $(nproc)"
    echo "逻辑处理器: $(grep -c processor /proc/cpuinfo)"
    echo "缓存: $(grep 'cache size' /proc/cpuinfo | uniq | awk '{print $4, $5}')"
    print_separator
}

show_memory_info() {
    print_header "内存信息"
    local total=$(get_mem_size)
    echo "总容量: ${total} MB ($((total / 1024)) GB)"
    echo "内存条数: $(dmidecode -t memory 2>/dev/null | grep -c 'Memory Device' || echo 'Unknown')"
    dmidecode -t memory 2>/dev/null | grep -A5 "Memory Device" | grep "Size:" | grep -v "No Module" | head -8
    print_separator
}

show_disk_info() {
    print_header "磁盘信息"
    get_disk_info
    print_separator
}

show_raid_info() {
    if [[ -z "$HW_RAID" ]]; then
        echo_yellow "未检测到 RAID 卡"
        return
    fi
    
    print_header "RAID 信息"
    echo "RAID SN: ${RAIDSN:-Unknown}"
    
    if [[ -x "$TOOL_STORCLI64" ]]; then
        echo ""
        echo "EID:Slt DID State DG     Size Intf Med SED PI SeSz Model               Sp Type"
        echo "-------------------------------------------------------------------------------"
        $TOOL_STORCLI64 /c0/v0 show all 2>/dev/null | grep -i SATA || true
    fi
    print_separator
}

show_gpu_info() {
    if [[ -z "$HW_NVIDIA" ]]; then
        echo_yellow "未检测到 NVIDIA GPU"
        return
    fi
    
    print_header "GPU 信息"
    if check_command nvidia-smi; then
        nvidia-smi --query-gpu=name,temperature.gpu,power.draw,memory.used,memory.total \
            --format=csv 2>/dev/null || echo "无法获取 GPU 信息"
    else
        echo_yellow "nvidia-smi 命令不可用"
    fi
    print_separator
}

#-------------------------------------------------------------------------------
# Menu
#-------------------------------------------------------------------------------
show_menu() {
    while true; do
        clear
        print_header "系统信息"
        echo "  1. 显示所有信息"
        echo "  2. 基本信息"
        echo "  3. CPU 信息"
        echo "  4. 内存信息"
        echo "  5. 磁盘信息"
        echo "  6. RAID 信息"
        echo "  7. GPU 信息"
        echo "  8. 保存到文件"
        echo "  b. 返回主菜单"
        print_separator
        
        read -rp "请选择: " choice
        case "$choice" in
            1)
                show_basic_info
                show_cpu_info
                show_memory_info
                show_disk_info
                show_raid_info
                show_gpu_info
                echo "按回车键继续..."
                read -r
                ;;
            2) show_basic_info; read -r ;;
            3) show_cpu_info; read -r ;;
            4) show_memory_info; read -r ;;
            5) show_disk_info; read -r ;;
            6) show_raid_info; read -r ;;
            7) show_gpu_info; read -r ;;
            8)
                {
                    show_basic_info
                    show_cpu_info
                    show_memory_info
                    show_disk_info
                    show_raid_info
                    show_gpu_info
                } > "${SERVERSN:-system}_$(get_date).txt"
                log_success "信息已保存到 ${SERVERSN:-system}_$(get_date).txt"
                read -r
                ;;
            b|B) break ;;
            *) log_warn "无效选择"; sleep 1 ;;
        esac
    done
}

# Run
show_menu
