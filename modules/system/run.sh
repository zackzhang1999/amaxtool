#!/bin/bash
#===============================================================================
# AMAX Tool - System Maintenance Module
# Description: System configuration and maintenance tasks
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/utils.sh"

#-------------------------------------------------------------------------------
# Disable Ubuntu Auto Update
#-------------------------------------------------------------------------------
disable_auto_update() {
    print_header "关闭系统自动更新"
    check_root || return 1
    
    log_info "停止自动更新服务..."
    service_disable apt-daily-upgrade.timer
    service_disable apt-daily-upgrade.service
    service_disable apt-daily.timer
    service_disable apt-daily.service
    
    log_info "修改配置文件..."
    
    if [[ -f /etc/apt/apt.conf.d/10periodic ]]; then
        cat > /etc/apt/apt.conf.d/10periodic <<EOF
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
    fi
    
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
    fi
    
    log_success "系统自动更新已关闭"
    
    # Show status
    echo ""
    echo "服务状态:"
    systemctl status apt-daily.timer --no-pager 2>/dev/null | grep Active || true
}

#-------------------------------------------------------------------------------
# Lock Kernel
#-------------------------------------------------------------------------------
lock_kernel() {
    print_header "锁定当前内核"
    check_root || return 1
    
    local current_kernel
    current_kernel=$(uname -r)
    local grub_entry="Advanced options for Ubuntu>Ubuntu, with Linux $current_kernel"
    
    log_info "当前内核: $current_kernel"
    log_info "设置 GRUB 默认启动项..."
    
    sed -i "s/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"$grub_entry\"/g" /etc/default/grub
    update-grub
    
    log_success "内核已锁定"
}

#-------------------------------------------------------------------------------
# Configure IPMI
#-------------------------------------------------------------------------------
config_ipmi() {
    print_header "配置 IPMI"
    check_root || return 1
    
    local ip netmask gateway username password
    
    read_input "请输入 IP 地址" ip true
    read_input "请输入子网掩码" netmask true
    read_input "请输入网关地址" gateway true
    read_input "请输入用户名" username true
    read_input "请输入密码" password true
    
    log_info "配置网络..."
    ipmi_config_network "$ip" "$netmask" "$gateway"
    
    log_info "创建用户..."
    ipmi_create_user 6 "$username" "$password"
    
    echo ""
    log_success "IPMI 配置完成"
    echo "当前用户列表:"
    ipmitool user list 1
}

#-------------------------------------------------------------------------------
# IP Conflict Check
#-------------------------------------------------------------------------------
check_ip_conflict() {
    print_header "IP 冲突检测"
    
    if ! check_command arp-scan; then
        log_error "请先安装 arp-scan"
        return 1
    fi
    
    log_info "扫描网络..."
    local result
    result=$(arp-scan -l 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log_error "扫描失败"
        return 1
    fi
    
    # Parse and check conflicts
    declare -A ip_mac_map
    local conflict=false
    
    while read -r ip mac _; do
        [[ -z "$ip" || -z "$mac" ]] && continue
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        
        if [[ -n "${ip_mac_map[$ip]}" && "${ip_mac_map[$ip]}" != "$mac" ]]; then
            log_error "IP 冲突: $ip 被多个 MAC 使用: ${ip_mac_map[$ip]} 和 $mac"
            conflict=true
        else
            ip_mac_map[$ip]="$mac"
        fi
    done <<< "$(echo "$result" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/{print $1, $2}')"
    
    if [[ "$conflict" == "false" ]]; then
        log_success "未发现 IP 冲突"
    fi
}

#-------------------------------------------------------------------------------
# Setup rc.local
#-------------------------------------------------------------------------------
setup_rclocal() {
    print_header "配置 rc.local 服务"
    check_root || return 1
    
    log_info "创建 rc.local..."
    cat > /etc/rc.local <<'EOF'
#!/bin/bash
# rc.local - Custom startup script

# Add your custom commands here

exit 0
EOF
    chmod +x /etc/rc.local
    
    log_info "创建 systemd 服务..."
    cat > /etc/systemd/system/rc-local.service <<'EOF'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable rc-local
    systemctl start rc-local
    
    log_success "rc.local 服务已配置"
    systemctl status rc-local --no-pager 2>/dev/null | head -5
}

#-------------------------------------------------------------------------------
# Replace Sources to Aliyun
#-------------------------------------------------------------------------------
replace_sources() {
    print_header "更换软件源为阿里云"
    check_root || return 1
    
    local release
    release=$(lsb_release -cs 2>/dev/null)
    
    if [[ -z "$release" ]]; then
        log_error "无法检测系统版本"
        return 1
    fi
    
    local source_file="/etc/apt/sources.list"
    backup_file "$source_file"
    
    log_info "设置 $release 版本的阿里源..."
    
    cat > "$source_file" <<EOF
# 阿里云镜像源 - Ubuntu $release
deb http://mirrors.aliyun.com/ubuntu/ $release main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ $release main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ $release-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ $release-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ $release-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ $release-updates main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ $release-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ $release-backports main restricted universe multiverse
EOF
    
    log_info "更新软件包索引..."
    if apt-get update; then
        log_success "源更换成功"
    else
        log_error "更新失败，请检查网络或手动恢复备份"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Comprehensive Health Check
#-------------------------------------------------------------------------------
run_comprehensive_check() {
    print_header "综合检测"
    
    local autocheck_script="$SCRIPT_DIR/modules/system/autocheck.sh"
    
    if [[ ! -f "$autocheck_script" ]]; then
        log_error "未找到综合检测脚本: $autocheck_script"
        return 1
    fi
    
    if [[ $EUID -ne 0 ]]; then
        log_error "综合检测需要 root 权限运行"
        return 1
    fi
    
    log_info "启动服务器硬件健康综合检测..."
    echo ""
    echo "此检测将检查以下项目:"
    echo "  - IPMI 传感器状态（温度、电压、风扇）"
    echo "  - RAID 卡及磁盘状态"
    echo "  - 硬盘 SMART 健康"
    echo "  - CPU 和内存状态"
    echo "  - IPMI 系统事件日志"
    echo "  - PCI-E 设备速率"
    echo "  - 安全事件（SSH暴力破解等）"
    echo ""
    confirm "是否继续?" || return 1
    
    # 执行检测脚本
    bash "$autocheck_script"
}

#-------------------------------------------------------------------------------
# Menu
#-------------------------------------------------------------------------------
show_menu() {
    while true; do
        clear
        print_header "系统维护"
        echo "  1. 关闭系统自动更新"
        echo "  2. 锁定当前内核"
        echo "  3. 配置 IPMI"
        echo "  4. IP 冲突检测"
        echo "  5. 配置 rc.local 服务"
        echo "  6. 更换为阿里云软件源"
        echo "  7. 综合检测 (硬件健康检查)"
        echo "  b. 返回主菜单"
        print_separator
        
        read -rp "请选择: " choice
        case "$choice" in
            1) disable_auto_update; read -r ;;
            2) lock_kernel; read -r ;;
            3) config_ipmi; read -r ;;
            4) check_ip_conflict; read -r ;;
            5) setup_rclocal; read -r ;;
            6) replace_sources; read -r ;;
            7) run_comprehensive_check; read -r ;;
            b|B) break ;;
            *) log_warn "无效选择"; sleep 1 ;;
        esac
    done
}

show_menu
