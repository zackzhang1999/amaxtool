#!/bin/bash
#
# 文件名: hardware_health_check.sh
# 描述: 服务器硬件健康检查自动化脚本
# 支持: CentOS, RHEL, Ubuntu, Debian
# 作者: System Administrator
# 版本: 1.0
#

set -o pipefail

#==============================================================================
# 全局变量和配置
#==============================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOSTNAME="$(hostname -s)"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# 退出状态码
readonly STATUS_PASS=0
readonly STATUS_WARN=1
readonly STATUS_FAIL=2
readonly STATUS_SKIP=3

# 当前检查状态
OVERALL_STATUS=$STATUS_PASS

#==============================================================================
# 阈值配置（可修改）
#==============================================================================
# 温度阈值 (°C)
readonly TEMP_WARNING=85
readonly TEMP_CRITICAL=90

# 电压偏差阈值 (%)
readonly VOLTAGE_DEVIATION=10

# 风扇转速阈值 (% of nominal)
readonly FAN_WARNING_LOW=20
readonly FAN_WARNING_HIGH=110

# SMART 重映射扇区阈值
readonly SMART_REALLOC_THRESHOLD=1

# 密码猜解阈值（1小时内失败次数）
readonly BRUTE_FORCE_THRESHOLD=10

# PCI-E 速率检查（显示低于此速率的设备）
readonly PCIE_GEN_THRESHOLD=3  # Gen3
readonly PCIE_WIDTH_THRESHOLD=8  # x8

#==============================================================================
# ANSI 颜色定义
#==============================================================================
readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_GRAY='\033[0;90m'

#==============================================================================
# 状态标签
#==============================================================================
readonly TAG_PASS="${COLOR_GREEN}[PASS]${COLOR_RESET}"
readonly TAG_WARN="${COLOR_YELLOW}[WARN]${COLOR_RESET}"
readonly TAG_FAIL="${COLOR_RED}[FAIL]${COLOR_RESET}"
readonly TAG_SKIP="${COLOR_GRAY}[SKIP]${COLOR_RESET}"
readonly TAG_INFO="${COLOR_BLUE}[INFO]${COLOR_RESET}"

#==============================================================================
# 输出函数
#==============================================================================
print_header() {
    echo -e "\n${COLOR_CYAN}========================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}  $1${COLOR_RESET}"
    echo -e "${COLOR_CYAN}========================================${COLOR_RESET}"
}

print_pass() {
    echo -e "${TAG_PASS} $1"
}

print_warn() {
    echo -e "${TAG_WARN} $1"
    [[ $OVERALL_STATUS -lt $STATUS_WARN ]] && OVERALL_STATUS=$STATUS_WARN
}

print_fail() {
    echo -e "${TAG_FAIL} $1"
    [[ $OVERALL_STATUS -lt $STATUS_FAIL ]] && OVERALL_STATUS=$STATUS_FAIL
}

print_skip() {
    echo -e "${TAG_SKIP} $1"
}

print_info() {
    echo -e "${TAG_INFO} $1"
}

print_detail() {
    echo -e "    ${COLOR_GRAY}$1${COLOR_RESET}"
}

#==============================================================================
# 工具检测函数
#==============================================================================
cmd_exists() {
    command -v "$1" &>/dev/null
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_fail "此脚本必须以 root 用户身份运行"
        exit 1
    fi
    print_pass "以 root 用户运行"
}

#==============================================================================
# IPMI 传感器检查
#==============================================================================
check_ipmi_sensors() {
    print_header "IPMI 传感器检查"
    
    if ! cmd_exists ipmitool; then
        print_skip "ipmitool 未安装"
        return $STATUS_SKIP
    fi
    
    # 检测 IPMI 是否可用
    if ! timeout 5 ipmitool mc info &>/dev/null; then
        print_skip "IPMI 设备不可用"
        return $STATUS_SKIP
    fi
    
    local sensor_output
    sensor_output=$(ipmitool sensor list 2>/dev/null)
    if [[ -z "$sensor_output" ]]; then
        print_fail "无法获取 IPMI 传感器数据"
        return $STATUS_FAIL
    fi
    
    local has_issue=false
    
    # 解析传感器数据
    while IFS='|' read -r name value unit status lower nonrec upper; do
        # 清理空格
        name=$(echo "$name" | xargs)
        value=$(echo "$value" | xargs)
        unit=$(echo "$unit" | xargs)
        status=$(echo "$status" | xargs | tr '[:upper:]' '[:lower:]')
        
        # 跳过空行和标题
        [[ -z "$name" ]] && continue
        [[ "$name" == "Sensor" ]] && continue
        
        # 检查传感器状态
        case "$status" in
            "ok"|"0x0100"|"0x0080")
                # 正常状态，但仍检查阈值
                ;;
            "ns"|"na"|"no"*|"nc"|"cr")
                # 无传感器或不可用，跳过
                continue
                ;;
            "nr")
                # 未就绪，跳过但不计为失败
                continue
                ;;
            *)
                # 检查是否是离散传感器（如机箱入侵）
                if [[ "$unit" == *"discrete"* ]] || [[ "$value" == "0x"* ]]; then
                    # 离散传感器，根据具体值判断
                    continue
                fi
                has_issue=true
                print_fail "传感器异常: $name = $value $unit (状态: $status)"
                continue
                ;;
        esac
        
        # 数值类型检查
        if [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            # 温度检查
            if [[ "$unit" == "degrees"* ]] || [[ "$unit" == "C" ]]; then
                local temp_int=${value%.*}
                if [[ $temp_int -ge $TEMP_CRITICAL ]]; then
                    has_issue=true
                    print_fail "温度过高: $name = ${temp_int}°C (阈值: ${TEMP_CRITICAL}°C)"
                elif [[ $temp_int -ge $TEMP_WARNING ]]; then
                    has_issue=true
                    print_warn "温度警告: $name = ${temp_int}°C (阈值: ${TEMP_WARNING}°C)"
                fi
            fi
            
            # 电压检查（需要参考标称值，这里简化处理）
            if [[ "$unit" == "Volts" ]] || [[ "$unit" == "V" ]]; then
                # 常见的标称电压值
                local nominal=0
                if [[ "$value" == "12"* ]]; then
                    nominal=12.0
                elif [[ "$value" == "5"* ]]; then
                    nominal=5.0
                elif [[ "$value" == "3.3"* ]]; then
                    nominal=3.3
                elif [[ "$value" == "1.8"* ]]; then
                    nominal=1.8
                elif [[ "$value" == "1.2"* ]]; then
                    nominal=1.2
                fi
                
                if [[ $nominal != 0 ]]; then
                    local deviation
                    deviation=$(awk "BEGIN {printf \"%.1f\", ($value - $nominal) / $nominal * 100}")
                    local abs_dev=${deviation#-}
                    
                    if (( $(echo "$abs_dev > $VOLTAGE_DEVIATION" | bc -l) )); then
                        has_issue=true
                        if (( $(echo "$abs_dev > 15" | bc -l) )); then
                            print_fail "电压异常: $name = ${value}V (偏差: ${deviation}%, 标称: ${nominal}V)"
                        else
                            print_warn "电压偏差: $name = ${value}V (偏差: ${deviation}%, 标称: ${nominal}V)"
                        fi
                    fi
                fi
            fi
            
            # 风扇转速检查（RPM或百分比）
            if [[ "$unit" == "RPM" ]] || [[ "$name" == *"Fan"* ]]; then
                # 简化：只检查是否为0（停转）
                if [[ "$value" == "0" ]] || [[ "$value" == "0.0" ]]; then
                    has_issue=true
                    print_fail "风扇停转: $name = ${value} $unit"
                fi
            fi
        fi
    done <<< "$sensor_output"
    
    if [[ "$has_issue" == false ]]; then
        print_pass "所有 IPMI 传感器正常"
    fi
    
    # 显示关键传感器汇总
    echo -e "\n${COLOR_BLUE}关键传感器状态:${COLOR_RESET}"
    echo "$sensor_output" | grep -iE "(temp|fan|voltage|power)" | head -10 | while IFS='|' read -r name value unit status _; do
        name=$(echo "$name" | xargs)
        value=$(echo "$value" | xargs)
        unit=$(echo "$unit" | xargs)
        printf "  %-20s %10s %-10s\n" "$name" "$value" "$unit"
    done
    
    return 0
}

#==============================================================================
# RAID 卡状态检查
#==============================================================================
check_raid_status() {
    print_header "RAID 卡状态检查"
    
    local raid_found=false
    local has_issue=false
    
    # 检测存储控制器
    local storage_controllers
    storage_controllers=$(lspci | grep -iE "raid|scsi|sata|sas" 2>/dev/null || echo "")
    
    #============================================================================
    # LSI/Broadcom MegaRAID (storcli64/storcli)
    #============================================================================
    local storcli_cmd=""
    if cmd_exists storcli64; then
        storcli_cmd="storcli64"
    elif cmd_exists storcli; then
        storcli_cmd="storcli"
    fi
    
    if [[ -n "$storcli_cmd" ]]; then
        raid_found=true
        print_info "检测到 $storcli_cmd 工具"
        
        # 检查控制器状态
        local ctrl_info
        ctrl_info=$($storcli_cmd show 2>/dev/null)
        
        local ctrl_count
        ctrl_count=$(echo "$ctrl_info" | grep -c "^[[:space:]]*[0-9]" 2>/dev/null)
        ctrl_count=${ctrl_count//[^0-9]/}
        ctrl_count=${ctrl_count:-0}
        
        if [[ "$ctrl_count" -eq 0 ]]; then
            print_warn "未检测到 RAID 控制器（可能使用 AHCI 模式）"
        else
            print_info "检测到 $ctrl_count 个 RAID 控制器"
            
            # 检查每个控制器
            for ((i=0; i<$ctrl_count; i++)); do
                local cvd_info
                cvd_info=$($storcli_cmd /c$i /vall show 2>/dev/null)
                
                # 检查虚拟磁盘状态
                while IFS= read -r line; do
                    if [[ "$line" =~ ^[[:space:]]*[0-9]+ ]]; then
                        local vd_state
                        vd_state=$(echo "$line" | awk '{print $3}')
                        if [[ "$vd_state" != "Optl" ]] && [[ "$vd_state" != "Opt" ]]; then
                            has_issue=true
                            print_fail "虚拟磁盘状态异常 (Ctrl $i): $vd_state"
                        fi
                    fi
                done <<< "$cvd_info"
                
                # 检查物理磁盘
                local pd_info
                pd_info=$($storcli_cmd /c$i /eall /sall show 2>/dev/null)
                
                # 统计各种状态的磁盘
                local pd_onln=$(echo "$pd_info" | grep -c "Onln" 2>/dev/null || echo 0)
                local pd_ugood=$(echo "$pd_info" | grep -c "UGood" 2>/dev/null || echo 0)
                local pd_gdt=$(echo "$pd_info" | grep -c "Gdt" 2>/dev/null || echo 0)
                local pd_rbld=$(echo "$pd_info" | grep -c "Rbld" 2>/dev/null || echo 0)
                local pd_dgd=$(echo "$pd_info" | grep -c "Dgd\|Offln" 2>/dev/null || echo 0)
                
                print_info "控制器 $i 物理磁盘: 在线=$pd_onln, 可用=$pd_ugood, 热备=$pd_gdt, 重建=$pd_rbld, 异常=$pd_dgd"
                
                if [[ $pd_rbld -gt 0 ]]; then
                    print_warn "有磁盘正在重建 (Rebuild)"
                fi
                if [[ $pd_dgd -gt 0 ]]; then
                    has_issue=true
                    print_fail "有磁盘异常/离线 (Degraded/Offline)"
                fi
                
                # 检查 BBU 状态
                local bbu_info
                bbu_info=$($storcli_cmd /c$i /bbu show 2>/dev/null || $storcli_cmd /c$i /cv show 2>/dev/null)
                if [[ -n "$bbu_info" ]]; then
                    if echo "$bbu_info" | grep -qiE "failed|error|degrade"; then
                        has_issue=true
                        print_fail "控制器 $i BBU/缓存故障"
                    else
                        print_pass "控制器 $i BBU/缓存正常"
                    fi
                fi
            done
        fi
    fi
    
    #============================================================================
    # Dell PERC (perccli)
    #============================================================================
    if cmd_exists perccli; then
        raid_found=true
        print_info "检测到 perccli 工具"
        
        local perc_info
        perc_info=$(perccli show 2>/dev/null)
        
        if echo "$perc_info" | grep -qi "failed\|error\|degrade"; then
            has_issue=true
            print_fail "PERC RAID 存在故障"
        else
            print_pass "PERC RAID 状态正常"
        fi
    fi
    
    #============================================================================
    # HP Smart Array (ssacli)
    #============================================================================
    if cmd_exists ssacli; then
        raid_found=true
        print_info "检测到 ssacli 工具"
        
        local ssa_info
        ssa_info=$(ssacli ctrl all show config 2>/dev/null)
        
        if echo "$ssa_info" | grep -qiE "failed|error|degraded"; then
            has_issue=true
            print_fail "HP Smart Array 存在故障"
        else
            print_pass "HP Smart Array 状态正常"
        fi
    fi
    
    #============================================================================
    # Linux 软件 RAID (mdadm)
    #============================================================================
    if [[ -f /proc/mdstat ]] && grep -q "md" /proc/mdstat 2>/dev/null; then
        raid_found=true
        print_info "检测到 Linux 软件 RAID"
        
        local mdstat
        mdstat=$(cat /proc/mdstat)
        
        # 检查同步状态
        if echo "$mdstat" | grep -qE "\[.*_.*\]"; then
            print_warn "有 RAID 阵列正在同步/重建"
            echo "$mdstat" | grep -E "md|recovery|resync"
        fi
        
        # 检查失败磁盘
        if echo "$mdstat" | grep -qE "\(F\)"; then
            has_issue=true
            print_fail "RAID 阵列中有失败的磁盘"
            echo "$mdstat" | grep -E "\(F\)"
        else
            print_pass "软件 RAID 状态正常"
        fi
    fi
    
    #============================================================================
    # 无 RAID 控制器
    #============================================================================
    if [[ "$raid_found" == false ]]; then
        if [[ -n "$storage_controllers" ]]; then
            print_info "存储控制器:"
            echo "$storage_controllers" | while read -r line; do
                print_detail "$line"
            done
        fi
        print_skip "未检测到 RAID 管理工具"
    elif [[ "$has_issue" == false ]]; then
        print_pass "RAID 系统整体状态正常"
    fi
    
    return 0
}

#==============================================================================
# 硬盘 SMART 检查
#==============================================================================
check_smart_disks() {
    print_header "硬盘 SMART 检查"
    
    if ! cmd_exists smartctl; then
        print_skip "smartctl 未安装"
        return $STATUS_SKIP
    fi
    
    local has_issue=false
    local disk_count=0
    
    # 获取所有块设备
    local block_devs
    block_devs=$(lsblk -d -n -o NAME,TYPE | grep "disk" | awk '{print $1}')
    
    for dev in $block_devs; do
        local dev_path="/dev/$dev"
        
        # 检查是否支持 SMART
        if ! smartctl -i "$dev_path" &>/dev/null; then
            continue
        fi
        
        # 检查是否为 USB 设备（通常 SMART 不可靠）
        if smartctl -i "$dev_path" 2>/dev/null | grep -qi "USB"; then
            continue
        fi
        
        ((disk_count++))
        
        # 获取 SMART 状态
        local smart_status
        smart_status=$(smartctl -H "$dev_path" 2>/dev/null)
        
        # 获取设备信息
        local model
        model=$(smartctl -i "$dev_path" 2>/dev/null | grep "Device Model" | cut -d: -f2 | xargs)
        [[ -z "$model" ]] && model=$(smartctl -i "$dev_path" 2>/dev/null | grep "Product" | cut -d: -f2 | xargs)
        
        if echo "$smart_status" | grep -q "PASSED"; then
            # 进一步检查关键属性
            local smart_all
            smart_all=$(smartctl -a "$dev_path" 2>/dev/null)
            
            # 检查重映射扇区
            local realloc
            realloc=$(echo "$smart_all" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
            if [[ -n "$realloc" ]] && [[ "$realloc" =~ ^[0-9]+$ ]] && [[ $realloc -gt $SMART_REALLOC_THRESHOLD ]]; then
                has_issue=true
                print_fail "$dev ($model): 重映射扇区 = $realloc"
            fi
            
            # 检查当前待映射扇区
            local pending
            pending=$(echo "$smart_all" | grep "Current_Pending_Sector" | awk '{print $10}')
            if [[ -n "$pending" ]] && [[ "$pending" =~ ^[0-9]+$ ]] && [[ $pending -gt 0 ]]; then
                has_issue=true
                print_warn "$dev ($model): 待映射扇区 = $pending"
            fi
            
            # 检查离线不可修复错误
            local offline_unc
            offline_unc=$(echo "$smart_all" | grep "Offline_Uncorrectable" | awk '{print $10}')
            if [[ -n "$offline_unc" ]] && [[ "$offline_unc" =~ ^[0-9]+$ ]] && [[ $offline_unc -gt 0 ]]; then
                has_issue=true
                print_fail "$dev ($model): 离线不可修复错误 = $offline_unc"
            fi
            
            # 温度检查
            local temp
            temp=$(echo "$smart_all" | grep "Temperature_Celsius" | awk '{print $10}')
            if [[ -n "$temp" ]] && [[ "$temp" =~ ^[0-9]+$ ]]; then
                if [[ $temp -ge $TEMP_CRITICAL ]]; then
                    has_issue=true
                    print_fail "$dev ($model): 温度 = ${temp}°C"
                elif [[ $temp -ge $TEMP_WARNING ]]; then
                    print_warn "$dev ($model): 温度 = ${temp}°C"
                fi
            fi
            
            # NVMe 设备特殊处理
            if [[ "$dev" == nvme* ]]; then
                local nvme_temp
                nvme_temp=$(smartctl -a "$dev_path" 2>/dev/null | grep "Temperature:" | awk '{print $2}')
                if [[ -n "$nvme_temp" ]] && [[ "$nvme_temp" =~ ^[0-9]+$ ]]; then
                    if [[ $nvme_temp -ge $TEMP_CRITICAL ]]; then
                        has_issue=true
                        print_fail "$dev ($model): NVMe 温度 = ${nvme_temp}°C"
                    elif [[ $nvme_temp -ge $TEMP_WARNING ]]; then
                        print_warn "$dev ($model): NVMe 温度 = ${nvme_temp}°C"
                    fi
                fi
            fi
            
        else
            has_issue=true
            print_fail "$dev ($model): SMART 检测未通过"
        fi
    done
    
    if [[ $disk_count -eq 0 ]]; then
        print_skip "未检测到支持 SMART 的磁盘"
    elif [[ "$has_issue" == false ]]; then
        print_pass "所有 $disk_count 块硬盘 SMART 状态正常"
    fi
    
    return 0
}

#==============================================================================
# CPU 和内存状态检查
#==============================================================================
check_cpu_memory() {
    print_header "CPU 和内存状态检查"
    
    # CPU 检查
    print_info "CPU 信息:"
    
    local cpu_model
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    local cpu_count
    cpu_count=$(grep -c "processor" /proc/cpuinfo)
    local cpu_cores
    cpu_cores=$(grep "cpu cores" /proc/cpuinfo | head -1 | awk '{print $4}')
    
    print_detail "型号: $cpu_model"
    print_detail "逻辑核心数: $cpu_count"
    print_detail "物理核心数: $cpu_cores"
    
    # 检查 CPU 温度（通过 IPMI 或 sysfs）
    local cpu_temp_found=false
    if [[ -d /sys/class/thermal ]]; then
        for zone in /sys/class/thermal/thermal_zone*; do
            if [[ -f "$zone/temp" ]]; then
                local temp_milli
                temp_milli=$(cat "$zone/temp" 2>/dev/null)
                local temp=$((temp_milli / 1000))
                
                if [[ $temp -gt 0 ]]; then
                    cpu_temp_found=true
                    if [[ $temp -ge $TEMP_CRITICAL ]]; then
                        print_fail "CPU 温度: ${temp}°C"
                    elif [[ $temp -ge $TEMP_WARNING ]]; then
                        print_warn "CPU 温度: ${temp}°C"
                    else
                        print_pass "CPU 温度: ${temp}°C"
                    fi
                fi
            fi
        done
    fi
    
    if [[ "$cpu_temp_found" == false ]]; then
        print_detail "无法从系统获取 CPU 温度"
    fi
    
    # 检查 CPU 错误（通过 dmesg）
    local cpu_errors
    cpu_errors=$(dmesg 2>/dev/null | grep -iE "machine check|mce.*error|cpu.*temperature|thermal shutdown|cpu.*throttl" | tail -5)
    if [[ -n "$cpu_errors" ]]; then
        print_warn "检测到 CPU 错误/温度事件:"
        echo "$cpu_errors" | while read -r line; do
            print_detail "$line"
        done
    fi
    
    # 内存检查
    echo
    print_info "内存信息:"
    
    local mem_total
    mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used
    mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    local mem_percent
    mem_percent=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')
    
    print_detail "总内存: $mem_total"
    print_detail "已使用: $mem_used (${mem_percent}%)"
    
    # 检查内存使用率
    if (( $(echo "$mem_percent > 95" | bc -l) )); then
        print_fail "内存使用率过高: ${mem_percent}%"
    elif (( $(echo "$mem_percent > 85" | bc -l) )); then
        print_warn "内存使用率较高: ${mem_percent}%"
    else
        print_pass "内存使用率正常: ${mem_percent}%"
    fi
    
    # 检查 ECC 错误（通过 edac-util 或 dmesg）
    if cmd_exists edac-util; then
        local ecc_errors
        ecc_errors=$(edac-util -v 2>/dev/null | grep -E "errors:|uncorrected")
        if [[ -n "$ecc_errors" ]]; then
            print_warn "ECC 内存错误:"
            echo "$ecc_errors" | while read -r line; do
                print_detail "$line"
            done
        else
            print_pass "无 ECC 内存错误"
        fi
    else
        # 通过 dmesg 检查
        local mem_errors
        mem_errors=$(dmesg 2>/dev/null | grep -iE "hardware error|ecc.*error|memory error" | tail -5)
        if [[ -n "$mem_errors" ]]; then
            print_warn "检测到内存错误日志:"
            echo "$mem_errors" | while read -r line; do
                print_detail "$line"
            done
        else
            print_pass "无内存错误日志"
        fi
    fi
    
    # 检查 OOM 事件
    local oom_events
    oom_events=$(dmesg 2>/dev/null | grep -c "Out of memory" || echo 0)
    oom_events=${oom_events//[^0-9]/}
    oom_events=${oom_events:-0}
    if [[ $oom_events -gt 0 ]]; then
        print_warn "检测到 $oom_events 次 OOM (Out of Memory) 事件"
    fi
    
    return 0
}

#==============================================================================
# IPMI 系统事件日志检查
#==============================================================================
check_ipmi_sel() {
    print_header "IPMI 系统事件日志检查"
    
    if ! cmd_exists ipmitool; then
        print_skip "ipmitool 未安装"
        return $STATUS_SKIP
    fi
    
    if ! timeout 5 ipmitool mc info &>/dev/null; then
        print_skip "IPMI 设备不可用"
        return $STATUS_SKIP
    fi
    
    # 获取所有 SEL 条目
    local sel_all
    sel_all=$(ipmitool sel elist 2>/dev/null)
    
    if [[ -z "$sel_all" ]]; then
        print_info "SEL 日志为空"
        return 0
    fi
    
    # 获取最近的 50 条记录用于分析
    local sel_entries
    sel_entries=$(echo "$sel_all" | tail -50)
    
    # 统计各类事件
    local critical_count=0
    local warning_count=0
    local info_count=0
    
    # 分类统计变量
    local temp_errors=0
    local voltage_errors=0
    local fan_errors=0
    local disk_errors=0
    local power_errors=0
    local memory_errors=0
    local cpu_errors=0
    
    # 错误详情数组
    local error_details=""
    
    # 检查所有事件并分类
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        # 解析事件级别
        local severity="info"
        if echo "$line" | grep -qiE "critical|#ff|severe"; then
            severity="critical"
            ((critical_count++))
        elif echo "$line" | grep -qiE "warning|#f0|minor|degraded|predictive"; then
            severity="warning"
            ((warning_count++))
        elif echo "$line" | grep -qiE "error|fail|fault|asserted|threshold"; then
            # 检查是否是错误类型
            severity="error"
            ((critical_count++))
        else
            ((info_count++))
            continue
        fi
        
        # 分类错误类型
        if echo "$line" | grep -qiE "temperature|thermal|temp|overheat"; then
            ((temp_errors++))
            error_details="${error_details}TEMP:${line}\n"
        elif echo "$line" | grep -qiE "voltage|power supply|psu|vbat|3\.3v|5v|12v"; then
            ((voltage_errors++))
            error_details="${error_details}VOLT:${line}\n"
        elif echo "$line" | grep -qiE "fan|cooling|airflow"; then
            ((fan_errors++))
            error_details="${error_details}FAN:${line}\n"
        elif echo "$line" | grep -qiE "drive|disk|hdd|ssd|scsi|sata|nvme|predictive failure"; then
            ((disk_errors++))
            error_details="${error_details}DISK:${line}\n"
        elif echo "$line" | grep -qiE "power|pwru|pwr"; then
            ((power_errors++))
            error_details="${error_details}PWR:${line}\n"
        elif echo "$line" | grep -qiE "memory|dimm|ecc|ram"; then
            ((memory_errors++))
            error_details="${error_details}MEM:${line}\n"
        elif echo "$line" | grep -qiE "processor|cpu|core"; then
            ((cpu_errors++))
            error_details="${error_details}CPU:${line}\n"
        else
            error_details="${error_details}OTHER:${line}\n"
        fi
    done <<< "$sel_entries"
    
    # 获取总条目数
    local total_entries
    total_entries=$(echo "$sel_all" | wc -l)
    total_entries=${total_entries//[^0-9]/}
    total_entries=${total_entries:-0}
    
    print_info "SEL 统计: 总计=$total_entries, Critical/Error=$critical_count, Warning=$warning_count, Info=$info_count"
    
    # 如果有错误，输出分类统计
    if [[ $critical_count -gt 0 ]] || [[ $warning_count -gt 0 ]]; then
        echo
        print_warn "错误分类统计:"
        [[ $temp_errors -gt 0 ]] && print_detail "温度事件: $temp_errors"
        [[ $voltage_errors -gt 0 ]] && print_detail "电压/电源事件: $voltage_errors"
        [[ $fan_errors -gt 0 ]] && print_detail "风扇事件: $fan_errors"
        [[ $disk_errors -gt 0 ]] && print_detail "磁盘事件: $disk_errors"
        [[ $power_errors -gt 0 ]] && print_detail "电源事件: $power_errors"
        [[ $memory_errors -gt 0 ]] && print_detail "内存事件: $memory_errors"
        [[ $cpu_errors -gt 0 ]] && print_detail "CPU事件: $cpu_errors"
        
        # 输出详细的错误日志
        echo
        print_fail "=== IPMI 错误日志详情 ==="
        
        # 输出温度相关错误
        if [[ $temp_errors -gt 0 ]]; then
            echo
            print_warn "【温度相关错误】"
            echo -e "$error_details" | grep "^TEMP:" | head -5 | while IFS=: read -r type msg; do
                print_detail "$msg"
            done
        fi
        
        # 输出电压相关错误
        if [[ $voltage_errors -gt 0 ]]; then
            echo
            print_warn "【电压/电源相关错误】"
            echo -e "$error_details" | grep "^VOLT:" | head -5 | while IFS=: read -r type msg; do
                print_detail "$msg"
            done
        fi
        
        # 输出风扇相关错误
        if [[ $fan_errors -gt 0 ]]; then
            echo
            print_warn "【风扇相关错误】"
            echo -e "$error_details" | grep "^FAN:" | head -5 | while IFS=: read -r type msg; do
                print_detail "$msg"
            done
        fi
        
        # 输出磁盘相关错误
        if [[ $disk_errors -gt 0 ]]; then
            echo
            print_warn "【磁盘相关错误】"
            echo -e "$error_details" | grep "^DISK:" | head -5 | while IFS=: read -r type msg; do
                print_detail "$msg"
            done
        fi
        
        # 输出内存相关错误
        if [[ $memory_errors -gt 0 ]]; then
            echo
            print_warn "【内存相关错误】"
            echo -e "$error_details" | grep "^MEM:" | head -5 | while IFS=: read -r type msg; do
                print_detail "$msg"
            done
        fi
        
        # 输出CPU相关错误
        if [[ $cpu_errors -gt 0 ]]; then
            echo
            print_warn "【CPU相关错误】"
            echo -e "$error_details" | grep "^CPU:" | head -5 | while IFS=: read -r type msg; do
                print_detail "$msg"
            done
        fi
        
        # 输出其他错误
        local other_count
        other_count=$(echo -e "$error_details" | grep -c "^OTHER:" || echo 0)
        if [[ ${other_count//[^0-9]/} -gt 0 ]]; then
            echo
            print_warn "【其他错误】"
            echo -e "$error_details" | grep "^OTHER:" | head -5 | while IFS=: read -r type msg; do
                print_detail "$msg"
            done
        fi
        
        # 显示所有关键错误（如果数量不多）
        if [[ $critical_count -le 10 ]] && [[ $critical_count -gt 0 ]]; then
            echo
            print_fail "【所有关键/错误事件】"
            echo "$sel_entries" | grep -iE "critical|error|fail|#ff|#f0|threshold|asserted" | while read -r line; do
                print_detail "$line"
            done
        fi
    fi
    
    # 检查 SEL 空间使用情况
    local sel_info
    sel_info=$(ipmitool sel info 2>/dev/null)
    local sel_percent
    sel_percent=$(echo "$sel_info" | grep "Percent Used" | awk '{print $4}')
    if [[ -n "$sel_percent" ]]; then
        sel_percent=${sel_percent//%/}
        sel_percent=${sel_percent//[^0-9]/}
        sel_percent=${sel_percent:-0}
        if [[ $sel_percent -ge 90 ]]; then
            print_fail "SEL 日志空间即将满: ${sel_percent}%"
        elif [[ $sel_percent -ge 80 ]]; then
            print_warn "SEL 日志空间较高: ${sel_percent}%"
        else
            print_pass "SEL 日志空间: ${sel_percent}%"
        fi
    fi
    
    # 获取 SEL 最新事件时间
    local last_entry
    last_entry=$(echo "$sel_all" | tail -1)
    if [[ -n "$last_entry" ]]; then
        print_info "最新事件: $last_entry"
    fi
    
    if [[ $critical_count -eq 0 ]] && [[ $warning_count -eq 0 ]]; then
        print_pass "近期无关键/警告 SEL 事件"
    elif [[ $critical_count -gt 0 ]]; then
        print_fail "检测到 $critical_count 个关键错误事件，请立即检查！"
    else
        print_warn "检测到 $warning_count 个警告事件，请关注"
    fi
    
    return 0
}

#==============================================================================
# PCI-E 设备速率检查
#==============================================================================
check_pcie_speed() {
    print_header "PCI-E 设备速率检查"
    
    if ! cmd_exists lspci; then
        print_skip "lspci 未安装"
        return $STATUS_SKIP
    fi
    
    local has_issue=false
    local abnormal_count=0
    
    print_info "检查 PCI-E 设备链路状态..."
    
    # 获取所有 PCI-E 设备
    local pcie_devs
    pcie_devs=$(lspci | grep -E "Ethernet|RAID|SAS|SATA|NVMe|VGA|GPU" | awk '{print $1}')
    
    for dev in $pcie_devs; do
        local link_info
        link_info=$(lspci -s "$dev" -vvv 2>/dev/null)
        
        if [[ -z "$link_info" ]]; then
            continue
        fi
        
        # 提取设备名称
        local dev_name
        dev_name=$(lspci -s "$dev" 2>/dev/null | cut -d: -f3- | xargs)
        
        # 提取当前速度和宽度
        local current_speed
        current_speed=$(echo "$link_info" | grep "LnkSta:" | grep -oP "Speed [0-9.]+GT/s" | awk '{print $2}' | sed 's/GT\/s//')
        local current_width
        current_width=$(echo "$link_info" | grep "LnkSta:" | grep -oP "Width x[0-9]+" | sed 's/Width x//')
        
        # 提取最大速度和宽度
        local max_speed
        max_speed=$(echo "$link_info" | grep "LnkCap:" | grep -oP "Speed [0-9.]+GT/s" | head -1 | awk '{print $2}' | sed 's/GT\/s//')
        local max_width
        max_width=$(echo "$link_info" | grep "LnkCap:" | grep -oP "Width x[0-9]+" | head -1 | sed 's/Width x//')
        
        # 检查是否为 PCI-E 设备
        if [[ -z "$current_speed" ]] || [[ -z "$max_speed" ]]; then
            continue
        fi
        
        # 转换速度为数值进行比较
        local speed_val=${current_speed%%.*}
        local max_speed_val=${max_speed%%.*}
        
        # 检查速度或宽度降级
        local is_abnormal=false
        local reason=""
        
        # 速度检查 (Gen1=2.5, Gen2=5, Gen3=8, Gen4=16, Gen5=32)
        if [[ -n "$speed_val" ]] && [[ -n "$max_speed_val" ]]; then
            if (( $(echo "$speed_val < $max_speed_val" | bc -l) )); then
                is_abnormal=true
                reason="速度降级: $current_speed (最大 $max_speed)"
            fi
        fi
        
        # 宽度检查
        if [[ -n "$current_width" ]] && [[ -n "$max_width" ]]; then
            if [[ $current_width -lt $max_width ]]; then
                is_abnormal=true
                reason="$reason 宽度降级: x$current_width (最大 x$max_width)"
            fi
        fi
        
        # 只输出异常设备
        if [[ "$is_abnormal" == true ]]; then
            ((abnormal_count++))
            has_issue=true
            print_fail "[$dev] $dev_name"
            print_detail "$reason"
            
            # 检查降级原因
            local degraded_reason
            degraded_reason=$(echo "$link_info" | grep "LnkSta:" | grep -oP "Disabled|Training|Detect|Unknown")
            if [[ -n "$degraded_reason" ]]; then
                print_detail "状态: $degraded_reason"
            fi
        fi
    done
    
    if [[ "$has_issue" == false ]]; then
        print_pass "所有 PCI-E 设备运行在正常速率"
    else
        print_warn "共发现 $abnormal_count 个 PCI-E 设备速率异常"
        print_detail "提示: 速率降级可能是由于插槽限制或节能模式导致"
    fi
    
    return 0
}

#==============================================================================
# 密码猜解检查
#==============================================================================
check_brute_force() {
    print_header "密码猜解/暴力破解检查"
    
    local has_issue=false
    local check_sources=""
    
    # 检查 SSH 登录失败
    local ssh_failures=0
    local ssh_source=""
    local attack_ips=""
    
    # 从 journalctl 检查（systemd 系统）
    if cmd_exists journalctl; then
        ssh_failures=$(journalctl -u sshd --since "1 hour ago" 2>/dev/null | grep -c "Failed password" | tr -d '\n' || echo 0)
        if [[ $ssh_failures -gt 0 ]]; then
            ssh_source="journalctl"
            # 统计攻击来源 IP
            attack_ips=$(journalctl -u sshd --since "1 hour ago" 2>/dev/null | grep "Failed password" | grep -oP "from \K[0-9.]+" | sort | uniq -c | sort -rn | head -5)
        fi
    fi
    
    # 从日志文件检查
    if [[ $ssh_failures -eq 0 ]]; then
        if [[ -f /var/log/secure ]]; then
            ssh_failures=$(grep -c "Failed password" /var/log/secure 2>/dev/null)
            ssh_failures=${ssh_failures//[^0-9]/}
            ssh_failures=${ssh_failures:-0}
            ssh_source="/var/log/secure"
            if [[ $ssh_failures -gt 0 ]]; then
                attack_ips=$(grep "Failed password" /var/log/secure 2>/dev/null | grep -oP "from \K[0-9.]+" | sort | uniq -c | sort -rn | head -5)
            fi
        elif [[ -f /var/log/auth.log ]]; then
            ssh_failures=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null)
            ssh_failures=${ssh_failures//[^0-9]/}
            ssh_failures=${ssh_failures:-0}
            ssh_source="/var/log/auth.log"
            if [[ $ssh_failures -gt 0 ]]; then
                attack_ips=$(grep "Failed password" /var/log/auth.log 2>/dev/null | grep -oP "from \K[0-9.]+" | sort | uniq -c | sort -rn | head -5)
            fi
        fi
    fi
    
    # 检查 lastb 登录失败记录
    local lastb_count=0
    if cmd_exists lastb; then
        lastb_count=$(lastb 2>/dev/null | grep -v "^$" | grep -v "btmp" | wc -l)
        lastb_count=${lastb_count//[^0-9]/}
        lastb_count=${lastb_count:-0}
    fi
    
    # 评估风险
    if [[ $ssh_failures -ge $BRUTE_FORCE_THRESHOLD ]]; then
        has_issue=true
        print_fail "检测到大量 SSH 登录失败: $ssh_failures 次 (1小时内)"
        print_detail "数据来源: $ssh_source"
        
        if [[ -n "$attack_ips" ]]; then
            print_detail "主要攻击来源:"
            echo "$attack_ips" | while read -r line; do
                print_detail "  $line"
            done
        fi
        
        # 检查是否有成功登录的异常
        local recent_success
        if cmd_exists journalctl; then
            recent_success=$(journalctl -u sshd --since "1 hour ago" 2>/dev/null | grep "Accepted")
        elif [[ -f /var/log/secure ]]; then
            recent_success=$(grep "Accepted" /var/log/secure 2>/dev/null | tail -5)
        elif [[ -f /var/log/auth.log ]]; then
            recent_success=$(grep "Accepted" /var/log/auth.log 2>/dev/null | tail -5)
        fi
        
        if [[ -n "$recent_success" ]]; then
            print_warn "同时检测到成功登录:"
            echo "$recent_success" | while read -r line; do
                print_detail "  $line"
            done
        fi
        
    elif [[ $ssh_failures -gt 0 ]]; then
        print_warn "检测到少量 SSH 登录失败: $ssh_failures 次"
        print_detail "建议: 监控登录模式，考虑使用 fail2ban"
    else
        print_pass "近期无 SSH 登录失败记录"
    fi
    
    # 检查其他服务的失败登录
    # FTP
    local ftp_failures=0
    if [[ -f /var/log/vsftpd.log ]]; then
        ftp_failures=$(grep -c "FAIL LOGIN" /var/log/vsftpd.log 2>/dev/null)
        ftp_failures=${ftp_failures//[^0-9]/}
        ftp_failures=${ftp_failures:-0}
    elif [[ -f /var/log/proftpd/proftpd.log ]]; then
        ftp_failures=$(grep -c "Login failed" /var/log/proftpd/proftpd.log 2>/dev/null)
        ftp_failures=${ftp_failures//[^0-9]/}
        ftp_failures=${ftp_failures:-0}
    fi
    
    if [[ $ftp_failures -gt 0 ]]; then
        has_issue=true
        print_warn "检测到 FTP 登录失败: $ftp_failures 次"
    fi
    
    # 检查是否有被锁定的账户
    if cmd_exists pam_tally2; then
        local locked_users
        locked_users=$(pam_tally2 --reset 2>/dev/null | grep -v "User" | awk '$2 > 0 {print $1}' | head -5)
        if [[ -n "$locked_users" ]]; then
            print_warn "有账户因多次失败被锁定:"
            echo "$locked_users" | while read -r user; do
                print_detail "  $user"
            done
        fi
    fi
    
    # 检查当前登录的用户
    local current_users
    current_users=$(who | wc -l)
    print_info "当前登录用户数: $current_users"
    if [[ $current_users -gt 0 ]]; then
        who | while read -r line; do
            print_detail "  $line"
        done
    fi
    
    if [[ "$has_issue" == false ]] && [[ $ssh_failures -eq 0 ]]; then
        print_pass "未检测到密码猜解攻击迹象"
    fi
    
    return 0
}

#==============================================================================
# 硬件概览显示
#==============================================================================
show_hardware_summary() {
    print_header "服务器硬件概览"
    
    # 主机信息
    echo -e "${COLOR_BLUE}主机信息:${COLOR_RESET}"
    print_detail "主机名: $(hostname)"
    print_detail "操作系统: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
    print_detail "内核版本: $(uname -r)"
    print_detail "运行时间: $(uptime -p 2>/dev/null || uptime | awk -F',' '{print $1}')"
    echo
    
    # CPU 信息
    echo -e "${COLOR_BLUE}处理器:${COLOR_RESET}"
    local cpu_model
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    local cpu_sockets
    cpu_sockets=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l)
    cpu_sockets=${cpu_sockets//[^0-9]/}
    cpu_sockets=${cpu_sockets:-1}
    local cpu_cores
    cpu_cores=$(grep "cpu cores" /proc/cpuinfo | head -1 | awk '{print $4}')
    local cpu_threads
    cpu_threads=$(grep -c "processor" /proc/cpuinfo)
    local cpu_freq
    cpu_freq=$(grep "cpu MHz" /proc/cpuinfo | head -1 | awk '{printf "%.2f", $4/1000}')
    
    printf "  %-20s %s\n" "型号:" "$cpu_model"
    printf "  %-20s %s\n" "插槽数:" "${cpu_sockets} 个"
    printf "  %-20s %s\n" "每颗核心数:" "${cpu_cores} 核"
    printf "  %-20s %s\n" "总线程数:" "${cpu_threads} 线程"
    printf "  %-20s %s GHz\n" "频率:" "$cpu_freq"
    echo
    
    # 内存信息
    echo -e "${COLOR_BLUE}内存:${COLOR_RESET}"
    local mem_total
    mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_count=0
    if cmd_exists dmidecode; then
        mem_count=$(dmidecode -t memory 2>/dev/null | grep -c "Size: [0-9]* MB\|Size: [0-9]* GB" || echo 0)
        mem_count=${mem_count//[^0-9]/}
        mem_count=${mem_count:-0}
    fi
    local mem_speed=""
    if cmd_exists dmidecode; then
        mem_speed=$(dmidecode -t memory 2>/dev/null | grep "Speed:" | grep -v "Unknown" | head -1 | awk '{print $2}')
    fi
    
    printf "  %-20s %s\n" "总容量:" "$mem_total"
    printf "  %-20s %s\n" "内存条数:" "${mem_count} 条"
    [[ -n "$mem_speed" ]] && printf "  %-20s %s MHz\n" "频率:" "$mem_speed"
    echo
    
    # 存储信息
    echo -e "${COLOR_BLUE}存储设备:${COLOR_RESET}"
    local disk_count=0
    local disk_list=""
    
    # 统计所有块设备
    while read -r name size type; do
        [[ "$type" != "disk" ]] && continue
        ((disk_count++))
        local model=""
        if [[ -f /sys/block/$name/device/model ]]; then
            model=$(cat /sys/block/$name/device/model 2>/dev/null | xargs)
        fi
        [[ -z "$model" ]] && model="Unknown"
        disk_list="${disk_list}  [${name}] ${size} - ${model}\n"
    done <<< "$(lsblk -d -n -o NAME,SIZE,TYPE 2>/dev/null)"
    
    printf "  %-20s %s\n" "磁盘数量:" "${disk_count} 块"
    echo -e "${COLOR_GRAY}${disk_list}${COLOR_RESET}"
    
    # RAID 信息
    local raid_info=""
    if cmd_exists storcli64 || cmd_exists storcli; then
        local storcli_cmd=""
        cmd_exists storcli64 && storcli_cmd="storcli64" || storcli_cmd="storcli"
        local ctrl_count=$($storcli_cmd show 2>/dev/null | grep -c "^[[:space:]]*[0-9]" || echo 0)
        if [[ ${ctrl_count//[^0-9]/} -gt 0 ]]; then
            raid_info="LSI/Broadcom MegaRAID (${ctrl_count} 控制器)"
        fi
    elif cmd_exists perccli; then
        raid_info="Dell PERC"
    elif cmd_exists ssacli; then
        raid_info="HP Smart Array"
    elif [[ -f /proc/mdstat ]] && grep -q "md" /proc/mdstat 2>/dev/null; then
        local md_count
        md_count=$(grep -c "^md" /proc/mdstat 2>/dev/null || echo 0)
        raid_info="Linux 软件 RAID (${md_count} 阵列)"
    fi
    
    if [[ -n "$raid_info" ]]; then
        printf "  %-20s %s\n" "RAID 控制器:" "$raid_info"
    fi
    echo
    
    # GPU 信息
    if cmd_exists nvidia-smi; then
        echo -e "${COLOR_BLUE}显卡:${COLOR_RESET}"
        local gpu_count
        gpu_count=$(nvidia-smi -L 2>/dev/null | wc -l)
        nvidia-smi -L 2>/dev/null | while read -r line; do
            print_detail "$line"
        done
        echo
    fi
    
    # 网卡信息
    echo -e "${COLOR_BLUE}网络接口:${COLOR_RESET}"
    local nic_count=0
    local nic_list=""
    
    while read -r name speed vendor device; do
        [[ -z "$name" ]] && continue
        ((nic_count++))
        local speed_display=""
        if [[ "$speed" != "unknown" ]] && [[ -n "$speed" ]]; then
            speed_display="(${speed})"
        fi
        printf "  %-10s %s\n" "[$name]" "${vendor} ${device} ${speed_display}"
    done <<< "$(lspci -mm 2>/dev/null | grep -i "ethernet\|network" | awk '{
        gsub(/"/,"")
        print $1, $4, $5, $6
    }')"
    
    if [[ $nic_count -eq 0 ]]; then
        # 备选方案使用 ip 命令
        ip -o link show 2>/dev/null | grep -v "lo:" | while read -r line; do
            local ifname
            ifname=$(echo "$line" | awk -F': ' '{print $2}')
            [[ -n "$ifname" ]] && print_detail "[$ifname]"
        done
    fi
    echo
    
    # BMC/IPMI 信息
    if cmd_exists ipmitool && timeout 2 ipmitool mc info &>/dev/null; then
        echo -e "${COLOR_BLUE}BMC/IPMI:${COLOR_RESET}"
        local bmc_vendor
        bmc_vendor=$(ipmitool mc info 2>/dev/null | grep "Manufacturer Name" | cut -d: -f2 | xargs)
        local bmc_version
        bmc_version=$(ipmitool mc info 2>/dev/null | grep "Firmware Revision" | cut -d: -f2 | xargs)
        local ipmi_version
        ipmi_version=$(ipmitool mc info 2>/dev/null | grep "IPMI Version" | cut -d: -f2 | xargs)
        
        [[ -n "$bmc_vendor" ]] && printf "  %-20s %s\n" "厂商:" "$bmc_vendor"
        [[ -n "$bmc_version" ]] && printf "  %-20s %s\n" "固件版本:" "$bmc_version"
        [[ -n "$ipmi_version" ]] && printf "  %-20s %s\n" "IPMI版本:" "$ipmi_version"
        
        # IPMI 网络配置
        local ipmi_ip
        ipmi_ip=$(ipmitool lan print 1 2>/dev/null | grep "IP Address" | grep -v "Source" | head -1 | awk '{print $4}')
        [[ -n "$ipmi_ip" ]] && [[ "$ipmi_ip" != "0.0.0.0" ]] && printf "  %-20s %s\n" "管理IP:" "$ipmi_ip"
        echo
    fi
}

#==============================================================================
# 汇总报告
#==============================================================================
print_summary() {
    print_header "检查汇总"
    
    echo -e "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "主机名:   $HOSTNAME"
    echo
    
    case $OVERALL_STATUS in
        $STATUS_PASS)
            echo -e "整体状态: ${COLOR_GREEN}✓ PASS${COLOR_RESET} - 所有检查项正常"
            ;;
        $STATUS_WARN)
            echo -e "整体状态: ${COLOR_YELLOW}⚠ WARNING${COLOR_RESET} - 存在警告项，需要关注"
            ;;
        $STATUS_FAIL)
            echo -e "整体状态: ${COLOR_RED}✗ FAIL${COLOR_RESET} - 存在严重问题，需要立即处理"
            ;;
        *)
            echo -e "整体状态: ${COLOR_GRAY}UNKNOWN${COLOR_RESET}"
            ;;
    esac
    
    echo
    echo -e "${COLOR_BLUE}建议操作:${COLOR_RESET}"
    
    case $OVERALL_STATUS in
        $STATUS_PASS)
            echo "  - 系统硬件健康状态良好"
            echo "  - 建议定期运行此检查"
            ;;
        $STATUS_WARN)
            echo "  - 查看上述警告信息"
            echo "  - 根据建议采取相应措施"
            echo "  - 监控趋势变化"
            ;;
        $STATUS_FAIL)
            echo "  - 立即处理 FAIL 级别的问题"
            echo "  - 检查硬件是否需要更换"
            echo "  - 联系硬件供应商（如需）"
            ;;
    esac
    
    echo
    echo -e "${COLOR_GRAY}提示: 使用 collect_diagnostic.sh 脚本收集详细诊断信息${COLOR_RESET}"
}

#==============================================================================
# 主函数
#==============================================================================
main() {
    echo -e "${COLOR_BLUE}"
    cat << 'EOF'
    _   _   _   _   _   _   _   _  
   / \ / \ / \ / \ / \ / \ / \ / \ 
  ( H | a | r | d | w | a | r | e )
   \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ 
        Health Check v1.0
EOF
    echo -e "${COLOR_RESET}"
    
    # 检查 root 权限
    check_root
    
    # 显示硬件概览
    show_hardware_summary
    
    # 执行各项检查
    check_ipmi_sensors
    check_raid_status
    check_smart_disks
    check_cpu_memory
    check_ipmi_sel
    check_pcie_speed
    check_brute_force
    
    # 输出汇总
    print_summary
    
    # 返回整体状态码
    exit $OVERALL_STATUS
}

# 执行主函数
main "$@"
