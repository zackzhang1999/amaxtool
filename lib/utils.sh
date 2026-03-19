#!/bin/bash
#===============================================================================
# AMAX Tool - Utility Functions
# Description: Common utility functions for system operations
#===============================================================================

#-------------------------------------------------------------------------------
# Python Module Check
#-------------------------------------------------------------------------------
check_python_module() {
    local module="$1"
    python3 -c "import $module" 2>/dev/null
}

install_python_module() {
    local module="$1"
    log_info "Installing Python module: $module"
    pip3 install "$module" &>/dev/null || pip install "$module" &>/dev/null
}

#-------------------------------------------------------------------------------
# Package Installation
#-------------------------------------------------------------------------------
install_package() {
    local pkg="$1"
    log_info "Installing package: $pkg"
    
    if check_command apt-get; then
        apt-get install -y "$pkg" &>/dev/null
    elif check_command yum; then
        yum install -y "$pkg" &>/dev/null
    elif check_command dnf; then
        dnf install -y "$pkg" &>/dev/null
    else
        log_error "Unsupported package manager"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Service Management
#-------------------------------------------------------------------------------
service_disable() {
    local service="$1"
    systemctl disable "$service" &>/dev/null
    systemctl stop "$service" &>/dev/null
}

service_enable() {
    local service="$1"
    systemctl enable "$service" &>/dev/null
    systemctl start "$service" &>/dev/null
}

#-------------------------------------------------------------------------------
# File Operations
#-------------------------------------------------------------------------------
backup_file() {
    local file="$1"
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    
    if [[ -f "$file" ]]; then
        cp -p "$file" "$backup" || return 1
        log_info "Backed up $file to $backup"
        echo "$backup"
        return 0
    fi
    return 1
}

# 安全写入文件（带备份）
safe_write() {
    local file="$1"
    local content="$2"
    
    [[ -f "$file" ]] && backup_file "$file"
    echo "$content" > "$file"
}

#-------------------------------------------------------------------------------
# System Information
#-------------------------------------------------------------------------------
get_cpu_info() {
    cat /proc/cpuinfo | grep "model name" | uniq | awk -F': ' '{print $2}'
}

get_mem_size() {
    free -m | grep Mem | awk '{print $2}'
}

get_disk_info() {
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null || fdisk -l 2>/dev/null | grep Disk
}

#-------------------------------------------------------------------------------
# IPMI Functions
#-------------------------------------------------------------------------------
ipmi_config_network() {
    local ip="$1"
    local netmask="$2"
    local gateway="$3"
    
    ipmitool lan set 1 ipsrc static
    ipmitool lan set 1 ipaddr "$ip"
    ipmitool lan set 1 netmask "$netmask"
    ipmitool lan set 1 defgw ipaddr "$gateway"
}

ipmi_create_user() {
    local userid="$1"
    local username="$2"
    local password="$3"
    local channel="${4:-1}"
    
    ipmitool user set name "$userid" "$username"
    ipmitool user set password "$userid" "$password"
    ipmitool user priv "$userid" 4 "$channel"
    ipmitool channel setaccess "$channel" "$userid" callin=on ipmi=on link=on privilege=4
    ipmitool sol payload enable "$channel" "$userid"
    ipmitool user enable "$userid"
}

#-------------------------------------------------------------------------------
# RAID Functions
#-------------------------------------------------------------------------------
raid_get_disk_status() {
    local slot="$1"
    if [[ -x "$TOOL_STORCLI64" ]]; then
        $TOOL_STORCLI64 /c0/eall/s"$slot" show 2>/dev/null | \
            grep -i 252 | awk '{print $3}'
    fi
}

raid_set_good() {
    local slot="$1"
    if [[ -x "$TOOL_STORCLI64" ]]; then
        $TOOL_STORCLI64 /c0/eall/s"$slot" set good nolog &>/dev/null
        $TOOL_STORCLI64 /c0/eall/s"$slot" set online nolog &>/dev/null
    fi
}

raid_import_foreign() {
    if [[ -x "$TOOL_STORCLI64" ]]; then
        $TOOL_STORCLI64 /c0/fall import nolog &>/dev/null
    fi
}

raid_silence_alarm() {
    if [[ -x "$TOOL_STORCLI64" ]]; then
        $TOOL_STORCLI64 /c0 set alarm=silence nolog &>/dev/null
    fi
}

#-------------------------------------------------------------------------------
# GPU Functions
#-------------------------------------------------------------------------------
gpu_check() {
    nvidia-smi &>/dev/null
}

gpu_get_info() {
    nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total \
        --format=csv,noheader 2>/dev/null
}
