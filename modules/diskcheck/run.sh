#!/bin/bash
#===============================================================================
# AMAX Tool - Disk Check Module
# Description: RAID disk health check and repair
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/utils.sh"

#-------------------------------------------------------------------------------
# Check RAID Disk Status
#-------------------------------------------------------------------------------
check_raid_disks() {
    if [[ -z "$HW_RAID" ]]; then
        log_warn "未检测到 RAID 卡"
        return 1
    fi
    
    if [[ ! -x "$TOOL_STORCLI64" ]]; then
        log_error "storcli64 工具不可用"
        return 1
    fi
    
    print_header "RAID 磁盘状态检查"
    
    local temp
    temp=$($TOOL_STORCLI64 /c0 show all 2>/dev/null | \
        grep -i "ROC temperature" | awk -F '=' '{print $2}' | awk '{print $1}')
    
    echo "磁盘状态:"
    echo "-------------------------------------------"
    
    local all_online=true
    for i in {0..7}; do
        local status
        status=$(raid_get_disk_status "$i")
        
        if [[ "$status" == "Onln" ]]; then
            echo_green "  磁盘 $i: $status"
        else
            echo_red "  磁盘 $i: ${status:-Unknown}"
            all_online=false
        fi
    done
    
    echo "-------------------------------------------"
    
    # Show RAID temperature
    if [[ -n "$temp" ]]; then
        if [[ "$temp" -gt 90 ]]; then
            echo_red "RAID 卡温度: ${temp}°C (过热警告!)"
        else
            echo "RAID 卡温度: ${temp}°C"
        fi
    fi
    
    # Show RAID status
    echo ""
    echo "RAID 阵列状态:"
    $TOOL_STORCLI64 /c0/v0 show 2>/dev/null | sed -n '11,15p'
    
    [[ "$all_online" == "true" ]]
}

#-------------------------------------------------------------------------------
# Repair RAID Disks
#-------------------------------------------------------------------------------
repair_raid_disks() {
    if [[ -z "$HW_RAID" ]]; then
        log_warn "未检测到 RAID 卡"
        return 1
    fi
    
    print_header "修复 RAID 磁盘"
    
    log_info "开始检查和修复..."
    echo "-------------------------------------------"
    
    for i in {0..7}; do
        local status
        status=$(raid_get_disk_status "$i")
        
        if [[ "$status" != "Onln" ]]; then
            echo_red "磁盘 $i 状态异常: ${status:-Unknown}"
            log_info "尝试修复磁盘 $i..."
            
            raid_set_good "$i"
            sleep 1
        else
            echo_green "磁盘 $i 状态正常: $status"
        fi
    done
    
    # Import foreign configs
    log_info "导入外部配置..."
    raid_import_foreign
    
    # Silence alarm
    raid_silence_alarm
    
    sleep 2
    
    echo ""
    log_success "修复完成"
    
    # Re-check
    echo ""
    echo "重新检查磁盘状态:"
    check_raid_disks
}

#-------------------------------------------------------------------------------
# Check Disk Health with SMART
#-------------------------------------------------------------------------------
check_disk_smart() {
    print_header "磁盘 SMART 健康检查"
    
    if ! check_command smartctl; then
        log_info "安装 smartmontools..."
        install_package smartmontools || {
            log_error "安装失败"
            return 1
        }
    fi
    
    log_info "扫描磁盘..."
    local disks
    disks=$(smartctl --scan 2>/dev/null | awk '{print $1}')
    
    if [[ -z "$disks" ]]; then
        log_warn "未发现磁盘"
        return 1
    fi
    
    local has_error=false
    
    for disk in $disks; do
        echo ""
        echo "磁盘: $disk"
        echo "---------------------------------------------------------"
        
        local info
        info=$(smartctl -s on -a "$disk" 2>/dev/null)
        
        if [[ $? -ne 0 ]]; then
            echo_yellow "  无法读取 SMART 信息"
            continue
        fi
        
        local sn model
        sn=$(echo "$info" | grep -i "Serial Number" | head -1)
        model=$(echo "$info" | grep -i "Device Model\|Product" | head -1)
        
        echo "  $sn"
        echo "  $model"
        
        # Check critical attributes
        local reallocated pending offline uncorrect
        reallocated=$(echo "$info" | grep -i "Reallocated_Sector_Ct" | awk '{print $10}')
        pending=$(echo "$info" | grep -i "Current_Pending_Sector" | awk '{print $10}')
        offline=$(echo "$info" | grep -i "Offline_Uncorrectable" | awk '{print $10}')
        uncorrect=$(echo "$info" | grep -i "Reported_Uncorrect" | awk '{print $10}')
        
        # Display with color coding
        echo -n "  重映射扇区数: "
        if [[ "${reallocated:-0}" -gt 0 ]]; then
            echo_red "${reallocated:-0}"
            has_error=true
        else
            echo_green "0"
        fi
        
        echo -n "  待处理扇区: "
        if [[ "${pending:-0}" -gt 0 ]]; then
            echo_red "${pending:-0}"
            has_error=true
        else
            echo_green "0"
        fi
        
        echo -n "  离线不可修复: "
        if [[ "${offline:-0}" -gt 0 ]]; then
            echo_red "${offline:-0}"
            has_error=true
        else
            echo_green "0"
        fi
        
        echo -n "  报告不可修复: "
        if [[ "${uncorrect:-0}" -gt 0 ]]; then
            echo_red "${uncorrect:-0}"
            has_error=true
        else
            echo_green "0"
        fi
        
        sleep 1
    done
    
    echo ""
    if [[ "$has_error" == "true" ]]; then
        echo_red "警告: 检测到磁盘错误，建议更换有问题的磁盘"
        return 1
    else
        log_success "所有磁盘健康状态正常"
        return 0
    fi
}

#-------------------------------------------------------------------------------
# Auto Repair Function
#-------------------------------------------------------------------------------
auto_repair() {
    print_header "自动磁盘检查与修复"
    
    if [[ -z "$HW_RAID" ]]; then
        log_warn "未检测到 RAID 卡，跳过 RAID 修复"
    else
        log_info "检查 RAID 状态..."
        if ! check_raid_disks; then
            log_info "发现异常，开始修复..."
            repair_raid_disks
        fi
    fi
    
    echo ""
    log_info "检查 SMART 状态..."
    check_disk_smart
}

#-------------------------------------------------------------------------------
# Menu
#-------------------------------------------------------------------------------
show_menu() {
    while true; do
        clear
        print_header "磁盘检查"
        echo "  1. 检查并修复 RAID 磁盘"
        echo "  2. 检查硬盘 SMART 状态"
        echo "  3. 自动检查与修复"
        echo "  b. 返回主菜单"
        print_separator
        
        read -rp "请选择: " choice
        case "$choice" in
            1)
                check_raid_disks
                if [[ $? -ne 0 ]]; then
                    confirm "是否尝试修复?" && repair_raid_disks
                fi
                read -r
                ;;
            2) check_disk_smart; read -r ;;
            3) auto_repair; read -r ;;
            b|B) break ;;
            *) log_warn "无效选择"; sleep 1 ;;
        esac
    done
}

show_menu
