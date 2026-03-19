#!/bin/bash
#===============================================================================
# AMAX Tool - Hardware Test Module
# Description: Hardware stress testing and benchmarking
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/utils.sh"

#-------------------------------------------------------------------------------
# Disk I/O Test (FIO)
#-------------------------------------------------------------------------------
test_disk_io() {
    print_header "磁盘 I/O 性能测试"
    
    if ! check_command fio; then
        log_error "请先安装 fio"
        return 1
    fi
    
    local test_dir
    read -rp "请输入测试目录 (例如 /data1): " test_dir
    
    if [[ ! -d "$test_dir" ]]; then
        log_error "目录不存在: $test_dir"
        return 1
    fi
    
    # Check available space (need at least 20GB)
    local avail
    avail=$(df "$test_dir" | tail -1 | awk '{print $4}')
    if [[ $avail -lt 20971520 ]]; then  # 20GB in KB
        log_warn "磁盘空间不足 20GB，测试可能失败"
        confirm "是否继续?" || return 1
    fi
    
    local test_file="$test_dir/fio_test_$$"
    local results_dir="/tmp/fio_results_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$results_dir"
    
    log_info "开始顺序写测试 (1MB block, 10GB)..."
    fio --name=seq_write --ioengine=libaio --rw=write --bs=1M \
        --size=10G --numjobs=8 --runtime=60 --time_based \
        --group_reporting --filename="$test_file" --direct=1 --iodepth=64 \
        --output="$results_dir/seq_write.txt" 2>/dev/null
    
    log_info "开始顺序读测试 (1MB block, 10GB)..."
    fio --name=seq_read --ioengine=libaio --rw=read --bs=1M \
        --size=10G --numjobs=8 --runtime=60 --time_based \
        --group_reporting --filename="$test_file" --direct=1 --iodepth=64 \
        --output="$results_dir/seq_read.txt" 2>/dev/null
    
    log_info "开始随机写测试 (4KB block, 10GB)..."
    fio --name=rand_write --ioengine=libaio --rw=randwrite --bs=4k \
        --size=10G --numjobs=8 --runtime=60 --time_based \
        --group_reporting --filename="$test_file" --direct=1 --iodepth=64 \
        --output="$results_dir/rand_write.txt" 2>/dev/null
    
    log_info "开始随机读测试 (4KB block, 10GB)..."
    fio --name=rand_read --ioengine=libaio --rw=randread --bs=4k \
        --size=10G --numjobs=8 --runtime=60 --time_based \
        --group_reporting --filename="$test_file" --direct=1 --iodepth=64 \
        --output="$results_dir/rand_read.txt" 2>/dev/null
    
    rm -f "$test_file"
    
    log_success "测试完成"
    echo "结果保存在: $results_dir"
    echo ""
    echo "性能摘要:"
    grep -h "IOPS\|bw=" "$results_dir"/*.txt 2>/dev/null | head -20 || true
}

#-------------------------------------------------------------------------------
# Memory Bandwidth Test (STREAM)
#-------------------------------------------------------------------------------
test_memory_bandwidth() {
    print_header "内存带宽测试"
    
    local stream_path="$SCRIPT_DIR/modules/hwtest/stream/stream"
    
    if [[ ! -x "$stream_path" ]]; then
        log_error "未找到 stream 测试程序"
        echo "请在 $SCRIPT_DIR/modules/hwtest/stream/ 目录下编译 stream"
        return 1
    fi
    
    log_info "开始内存带宽测试..."
    echo ""
    "$stream_path"
}

#-------------------------------------------------------------------------------
# GPU Burn Test
#-------------------------------------------------------------------------------
test_gpu_burn() {
    print_header "GPU 压力测试"
    
    if [[ -z "$HW_NVIDIA" ]]; then
        log_warn "未检测到 NVIDIA GPU"
        return 1
    fi
    
    local burn_path="$SCRIPT_DIR/modules/hwtest/benchmark/gpu-burn/gpu_burn"
    
    if [[ ! -x "$burn_path" ]]; then
        log_error "未找到 gpu_burn 程序"
        return 1
    fi
    
    local duration
    read -rp "请输入测试时间(秒，1小时=3600): " duration
    
    if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
        log_error "请输入有效的数字"
        return 1
    fi
    
    local run_choice
    echo "请选择运行方式:"
    echo "  1. 当前进程直接运行"
    echo "  2. screen 后台运行"
    read -rp "选择: " run_choice
    
    case "$run_choice" in
        1)
            log_info "开始 GPU 压力测试..."
            "$burn_path" -tc "$duration"
            log_success "测试完成"
            ;;
        2)
            if ! check_command screen; then
                log_error "请先安装 screen"
                return 1
            fi
            screen -dmS gpu_burn "$burn_path" -tc "$duration"
            log_success "已在 screen 会话 'gpu_burn' 中启动"
            echo "使用 'screen -r gpu_burn' 查看进度"
            ;;
        *)
            log_warn "无效选择"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# CPU Stress Test
#-------------------------------------------------------------------------------
test_cpu_stress() {
    print_header "CPU 压力测试"
    
    if ! check_command stress-ng; then
        log_error "请先安装 stress-ng"
        return 1
    fi
    
    local duration
    read -rp "请输入测试时间(秒): " duration
    
    if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
        log_error "请输入有效的数字"
        return 1
    fi
    
    local cpu_cores
    cpu_cores=$(nproc)
    
    echo "请选择测试方式:"
    echo "  1. 快速测试 (多种算法, 每项10秒)"
    echo "  2. 持续压力测试"
    echo "  3. 自定义时间压力测试"
    read -rp "选择: " test_type
    
    case "$test_type" in
        1)
            log_info "开始快速测试..."
            for method in int8 int16 int32 int64 float double; do
                echo ""
                echo "测试算法: $method"
                stress-ng --cpu "$cpu_cores" --cpu-method "$method" -t 10s --metrics-brief
            done
            ;;
        2)
            local run_choice
            echo "请选择运行方式:"
            echo "  1. 当前进程直接运行"
            echo "  2. screen 后台运行"
            read -rp "选择: " run_choice
            
            case "$run_choice" in
                1)
                    stress-ng --cpu "$cpu_cores" --timeout "$duration"
                    log_success "测试完成"
                    ;;
                2)
                    if check_command screen; then
                        screen -dmS cpu_stress stress-ng --cpu "$cpu_cores" --timeout "$duration"
                        log_success "已在 screen 会话 'cpu_stress' 中启动"
                        echo "使用 'screen -r cpu_stress' 查看进度"
                    else
                        log_error "请先安装 screen"
                    fi
                    ;;
            esac
            ;;
        3)
            stress-ng --cpu "$cpu_cores" --timeout "$duration"
            log_success "测试完成"
            ;;
        *)
            log_warn "无效选择"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# PCI-E Device Scan
#-------------------------------------------------------------------------------
scan_pcie() {
    print_header "PCI-E 设备扫描"
    
    if ! check_command lspci; then
        log_error "请先安装 pciutils"
        return 1
    fi
    
    echo "扫描时间: $(date)"
    echo "系统: $(uname -a)"
    echo ""
    
    local total=0
    local pcie_count=0
    
    while read -r bus_id _; do
        ((total++))
        
        if [[ -d "/sys/bus/pci/devices/$bus_id" ]]; then
            ((pcie_count++))
            
            local device_info
            device_info=$(lspci -s "$bus_id" -vmm)
            local vendor device class
            vendor=$(echo "$device_info" | grep "Vendor" | cut -f2)
            device=$(echo "$device_info" | grep "Device" | cut -f2)
            class=$(echo "$device_info" | grep "Class" | cut -f2)
            
            local max_speed max_width cur_speed cur_width
            max_speed=$(cat "/sys/bus/pci/devices/$bus_id/max_link_speed" 2>/dev/null || echo "Unknown")
            max_width=$(cat "/sys/bus/pci/devices/$bus_id/max_link_width" 2>/dev/null || echo "Unknown")
            cur_speed=$(cat "/sys/bus/pci/devices/$bus_id/current_link_speed" 2>/dev/null || echo "Unknown")
            cur_width=$(cat "/sys/bus/pci/devices/$bus_id/current_link_width" 2>/dev/null || echo "Unknown")
            
            echo "设备: $bus_id"
            echo "  厂商: $vendor"
            echo "  设备: $device"
            echo "  类型: $class"
            echo "  PCIe 最大: $max_speed x$max_width"
            
            if [[ "$cur_speed" == "$max_speed" && "$cur_width" == "$max_width" ]]; then
                echo_green "  PCIe 当前: $cur_speed x$cur_width (满速)"
            else
                echo_yellow "  PCIe 当前: $cur_speed x$cur_width"
            fi
            echo "----------------------------------------"
        fi
    done < <(lspci -D | awk '{print $1}')
    
    echo ""
    echo "总计: $total 个 PCI 设备，其中 $pcie_count 个 PCI-E 设备"
}

#-------------------------------------------------------------------------------
# Comprehensive Stress Test (CPU + Memory + GPU)
#-------------------------------------------------------------------------------
test_comprehensive() {
    print_header "综合压力测试"
    
    local all_py_path="$SCRIPT_DIR/modules/hwtest/benchmark/all.py"
    
    if [[ ! -f "$all_py_path" ]]; then
        log_error "未找到综合测试脚本: $all_py_path"
        return 1
    fi
    
    # 检查 Python3 是否可用
    if ! command -v python3 &> /dev/null; then
        log_error "请先安装 python3"
        return 1
    fi
    
    log_info "启动综合压力测试..."
    echo ""
    echo "此测试将同时或单独对以下组件进行压力测试:"
    echo "  - CPU: 100% 全核满载"
    echo "  - 内存: 90% 容量占用"
    echo "  - GPU: CUDA 核心 + 显存双烤"
    echo ""
    confirm "是否继续?" || return 1
    
    # 运行 Python 脚本
    cd "$SCRIPT_DIR/modules/hwtest/benchmark" && python3 "$all_py_path"
    
    log_success "综合测试已完成"
}

#-------------------------------------------------------------------------------
# Menu
#-------------------------------------------------------------------------------
show_menu() {
    while true; do
        clear
        print_header "硬件测试"
        echo "  1. 磁盘 I/O 性能测试 (FIO)"
        echo "  2. 内存带宽测试 (STREAM)"
        echo "  3. GPU 压力测试"
        echo "  4. CPU 压力测试"
        echo "  5. PCI-E 设备扫描"
        echo "  6. 综合测试 (CPU+内存+GPU)"
        echo "  b. 返回主菜单"
        print_separator
        
        read -rp "请选择: " choice
        case "$choice" in
            1) test_disk_io; read -r ;;
            2) test_memory_bandwidth; read -r ;;
            3) test_gpu_burn; read -r ;;
            4) test_cpu_stress; read -r ;;
            5) scan_pcie; read -r ;;
            6) test_comprehensive; read -r ;;
            b|B) break ;;
            *) log_warn "无效选择"; sleep 1 ;;
        esac
    done
}

show_menu
