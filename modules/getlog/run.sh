#!/bin/bash
#
# 文件名: collect_diagnostic.sh
# 描述: 服务器故障诊断信息收集脚本
# 支持: CentOS, RHEL, Ubuntu, Debian
# 作者: System Administrator
# 版本: 1.0
#

set -o pipefail

#==============================================================================
# 全局变量定义
#==============================================================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTNAME="$(hostname -s)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="/tmp/${HOSTNAME}_${TIMESTAMP}"
LOG_FILE="${OUTPUT_DIR}/collection.log"
MIN_FREE_SPACE_MB=500
TIMEOUT_SECONDS=30

#==============================================================================
# ANSI 颜色定义
#==============================================================================
readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'

#==============================================================================
# 日志输出函数
#==============================================================================
log_info() {
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET}  $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}  $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo -e "\n${COLOR_CYAN}========================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}  $1${COLOR_RESET}"
    echo -e "${COLOR_CYAN}========================================${COLOR_RESET}\n" | tee -a "$LOG_FILE"
}

#==============================================================================
# 执行环境检查
#==============================================================================
check_root() {
    log_section "执行环境检查"
    
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 用户身份运行"
        exit 1
    fi
    log_info "已确认以 root 用户运行"
    
    # 创建临时目录
    if ! mkdir -p "$OUTPUT_DIR"; then
        log_error "无法创建临时目录: $OUTPUT_DIR"
        exit 1
    fi
    log_info "已创建临时目录: $OUTPUT_DIR"
    
    # 初始化日志文件
    touch "$LOG_FILE" 2>/dev/null || {
        log_error "无法在临时目录创建日志文件"
        exit 1
    }
    
    # 检查 /tmp 剩余空间
    local free_space_mb
    free_space_mb=$(df -m /tmp | awk 'NR==2 {print $4}')
    if [[ -z "$free_space_mb" ]] || [[ "$free_space_mb" -lt "$MIN_FREE_SPACE_MB" ]]; then
        log_error "/tmp 目录剩余空间不足 ${MIN_FREE_SPACE_MB}MB (当前: ${free_space_mb}MB)"
        exit 1
    fi
    log_info "/tmp 目录剩余空间充足: ${free_space_mb}MB"
    
    # 创建子目录结构
    mkdir -p "$OUTPUT_DIR"/{system,logs,hardware,network,resources,raid,gpu}
    log_info "目录结构初始化完成"
}

#==============================================================================
# 安全执行命令（带超时）
#==============================================================================
safe_exec() {
    local cmd="$1"
    local output_file="$2"
    local description="${3:-$cmd}"
    
    log_info "正在执行: $description"
    
    # 使用 timeout 命令防止命令卡死
    if timeout "$TIMEOUT_SECONDS" bash -c "$cmd" > "$output_file" 2>&1; then
        log_info "✓ $description 完成"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warn "✗ $description 执行超时 (${TIMEOUT_SECONDS}秒)"
            echo "[TIMEOUT] 命令执行超过 ${TIMEOUT_SECONDS} 秒" >> "$output_file"
        else
            log_warn "✗ $description 执行失败 (退出码: $exit_code)"
            echo "[ERROR] 命令执行失败，退出码: $exit_code" >> "$output_file"
        fi
        return 1
    fi
}

#==============================================================================
# 检测命令是否存在
#==============================================================================
cmd_exists() {
    command -v "$1" &>/dev/null
}

#==============================================================================
# 系统基础信息收集
#==============================================================================
collect_system_info() {
    log_section "收集系统基础信息"
    
    local sys_dir="$OUTPUT_DIR/system"
    
    # 操作系统版本
    log_info "收集操作系统版本信息..."
    {
        echo "=== /etc/os-release ==="
        cat /etc/os-release 2>/dev/null || echo "文件不存在"
        
        echo -e "\n=== /etc/redhat-release ==="
        cat /etc/redhat-release 2>/dev/null || echo "文件不存在"
        
        echo -e "\n=== /etc/debian_version ==="
        cat /etc/debian_version 2>/dev/null || echo "文件不存在"
        
        echo -e "\n=== uname -a ==="
        uname -a
        
        echo -e "\n=== 系统运行时间 ==="
        uptime
    } > "$sys_dir/os_version.txt"
    
    # CPU 信息
    log_info "收集 CPU 信息..."
    {
        echo "=== lscpu ==="
        lscpu 2>/dev/null || echo "lscpu 命令不可用"
        
        echo -e "\n=== /proc/cpuinfo ==="
        cat /proc/cpuinfo
    } > "$sys_dir/cpu_info.txt"
    
    # 内存信息
    log_info "收集内存信息..."
    {
        echo "=== free -h ==="
        free -h
        
        echo -e "\n=== free -m ==="
        free -m
        
        echo -e "\n=== /proc/meminfo ==="
        cat /proc/meminfo
    } > "$sys_dir/memory_info.txt"
    
    # dmidecode 内存信息（如可用）
    if cmd_exists dmidecode; then
        safe_exec "dmidecode -t memory" "$sys_dir/dmidecode_memory.txt" "dmidecode 内存信息"
    else
        log_warn "dmidecode 命令不可用，跳过详细内存信息收集"
    fi
    
    # 磁盘布局
    log_info "收集磁盘布局信息..."
    {
        echo "=== lsblk ==="
        lsblk -a -f -o +MODEL,SERIAL 2>/dev/null || lsblk
        
        echo -e "\n=== df -hT ==="
        df -hT
        
        echo -e "\n=== blkid ==="
        blkid 2>/dev/null || echo "blkid 命令不可用"
    } > "$sys_dir/disk_layout.txt"
    
    # fdisk -l 需要特殊处理，可能输出到 stderr
    safe_exec "fdisk -l" "$sys_dir/fdisk_info.txt" "fdisk 分区信息"
    
    # 网络配置
    log_info "收集网络配置信息..."
    local net_dir="$OUTPUT_DIR/network"
    {
        echo "=== ip addr ==="
        ip addr 2>/dev/null || ifconfig -a 2>/dev/null || echo "ip/ifconfig 命令不可用"
        
        echo -e "\n=== ip route ==="
        ip route 2>/dev/null || route -n 2>/dev/null || echo "ip/route 命令不可用"
        
        echo -e "\n=== ip link ==="
        ip link 2>/dev/null || echo "ip link 不可用"
        
        echo -e "\n=== /etc/resolv.conf ==="
        cat /etc/resolv.conf
        
        echo -e "\n=== 网络接口统计 ==="
        cat /proc/net/dev 2>/dev/null || echo "无法读取网络统计"
    } > "$net_dir/network_config.txt"
    
    # 当前负载
    log_info "收集系统负载信息..."
    {
        echo "=== top -b -n 1 (前30行) ==="
        top -b -n 1 | head -n 30
        
        echo -e "\n=== 进程统计 ==="
        echo "总进程数: $(ps aux | wc -l)"
        echo "僵尸进程: $(ps aux | grep -c 'Z')"
        
        echo -e "\n=== 系统限制 ==="
        ulimit -a 2>/dev/null || echo "ulimit 信息不可用"
    } > "$sys_dir/system_load.txt"
    
    # 已安装包列表
    log_info "收集已安装软件包列表..."
    if cmd_exists rpm; then
        safe_exec "rpm -qa | sort" "$sys_dir/installed_packages.txt" "RPM 软件包列表"
    elif cmd_exists dpkg; then
        safe_exec "dpkg -l" "$sys_dir/installed_packages.txt" "DPKG 软件包列表"
    else
        log_warn "无法确定包管理器类型"
    fi
}

#==============================================================================
# 系统日志收集
#==============================================================================
collect_logs() {
    log_section "收集系统日志"
    
    local logs_dir="$OUTPUT_DIR/logs"
    local log_files=(
        "/var/log/messages"
        "/var/log/syslog"
        "/var/log/dmesg"
        "/var/log/kern.log"
        "/var/log/boot.log"
        "/var/log/cron"
        "/var/log/secure"
        "/var/log/auth.log"
        "/var/log/audit/audit.log"
        "/var/log/yum.log"
        "/var/log/dpkg.log"
        "/var/log/apt/history.log"
    )
    
    # 复制日志文件
    for logfile in "${log_files[@]}"; do
        if [[ -f "$logfile" ]] && [[ -r "$logfile" ]]; then
            local basename
            basename=$(basename "$logfile")
            # 限制单个日志文件大小（最多10MB）
            if [[ $(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo 0) -gt 10485760 ]]; then
                log_warn "日志文件 $logfile 超过 10MB，只复制最后 5000 行"
                tail -n 5000 "$logfile" > "$logs_dir/${basename}.tail" 2>/dev/null && \
                    log_info "已复制: $logfile (最后5000行)" || \
                    log_warn "无法读取: $logfile"
            else
                cp "$logfile" "$logs_dir/" 2>/dev/null && \
                    log_info "已复制: $logfile" || \
                    log_warn "无法复制: $logfile"
            fi
        fi
    done
    
    # dmesg 命令输出
    safe_exec "dmesg" "$logs_dir/dmesg_cmd.txt" "dmesg 命令输出"
    
    # systemd 日志（如果系统使用 systemd）
    if cmd_exists journalctl; then
        log_info "收集 systemd 日志..."
        safe_exec "journalctl -xe --no-pager | tail -n 2000" "$logs_dir/journalctl_recent.txt" "systemd 最近日志"
        safe_exec "journalctl --no-pager -p err | tail -n 500" "$logs_dir/journalctl_errors.txt" "systemd 错误日志"
        safe_exec "journalctl -k --no-pager | tail -n 500" "$logs_dir/journalctl_kernel.txt" "systemd 内核日志"
    else
        log_warn "journalctl 不可用，跳过 systemd 日志收集"
    fi
    
    # 最近登录记录
    log_info "收集登录记录..."
    {
        echo "=== last ==="
        last 2>/dev/null || echo "last 命令不可用"
        
        echo -e "\n=== lastb ==="
        lastb 2>/dev/null || echo "lastb 命令不可用"
        
        echo -e "\n=== 当前登录用户 ==="
        who
        
        echo -e "\n=== 登录失败记录 ==="
        grep -i "fail\|error\|invalid" /var/log/secure /var/log/auth.log 2>/dev/null | tail -n 50 || echo "无登录失败记录"
    } > "$logs_dir/login_history.txt"
}

#==============================================================================
# IPMI/BMC 硬件日志收集
#==============================================================================
collect_ipmi() {
    log_section "收集 IPMI/BMC 日志"
    
    local hw_dir="$OUTPUT_DIR/hardware"
    
    # 检测 ipmitool 是否存在
    if ! cmd_exists ipmitool; then
        log_warn "ipmitool 未安装，跳过 IPMI 日志收集"
        log_warn "如需收集 IPMI 日志，请安装 ipmitool: yum install ipmitool 或 apt-get install ipmitool"
        return 0
    fi
    
    # 检测 IPMI 是否可用
    if ! timeout 5 ipmitool mc info &>/dev/null; then
        log_warn "IPMI 设备不可用或无法访问（可能需要加载 ipmi_si 内核模块）"
        return 0
    fi
    
    log_info "开始收集 IPMI/BMC 信息..."
    
    # 系统事件日志 (SEL)
    safe_exec "ipmitool sel list" "$hw_dir/ipmi_sel_list.txt" "IPMI SEL 列表"
    safe_exec "ipmitool sel elist" "$hw_dir/ipmi_sel_elist.txt" "IPMI SEL 扩展列表"
    safe_exec "ipmitool sel info" "$hw_dir/ipmi_sel_info.txt" "IPMI SEL 信息"
    
    # 传感器状态
    safe_exec "ipmitool sensor" "$hw_dir/ipmi_sensor.txt" "IPMI 传感器状态"
    safe_exec "ipmitool sensor list" "$hw_dir/ipmi_sensor_list.txt" "IPMI 传感器列表"
    
    # BMC 控制器信息
    safe_exec "ipmitool mc info" "$hw_dir/ipmi_mc_info.txt" "BMC 控制器信息"
    safe_exec "ipmitool mc getenables" "$hw_dir/ipmi_mc_enables.txt" "BMC 启用功能"
    
    # 其他有用信息
    safe_exec "ipmitool lan print" "$hw_dir/ipmi_lan.txt" "IPMI LAN 配置"
    safe_exec "ipmitool fru print" "$hw_dir/ipmi_fru.txt" "IPMI FRU 信息"
    safe_exec "ipmitool sdr list" "$hw_dir/ipmi_sdr.txt" "IPMI SDR 列表"
    safe_exec "ipmitool chassis status" "$hw_dir/ipmi_chassis.txt" "IPMI 机箱状态"
    safe_exec "ipmitool power status" "$hw_dir/ipmi_power.txt" "IPMI 电源状态"
}

#==============================================================================
# GPU 显卡日志收集
#==============================================================================
collect_gpu() {
    log_section "收集 GPU 信息"
    
    local gpu_dir="$OUTPUT_DIR/gpu"
    
    # 检测 nvidia-smi 是否存在
    if ! cmd_exists nvidia-smi; then
        log_warn "nvidia-smi 未找到，跳过 NVIDIA GPU 日志收集"
        
        # 检查是否有其他 GPU
        if lspci 2>/dev/null | grep -qi "vga\|3d\|display"; then
            log_info "检测到显示设备，收集 lspci GPU 信息..."
            lspci | grep -i "vga\|3d\|display" > "$gpu_dir/pci_gpu.txt"
        fi
        return 0
    fi
    
    log_info "检测到 NVIDIA 驱动，开始收集 GPU 信息..."
    
    # 基本 GPU 概览
    safe_exec "nvidia-smi" "$gpu_dir/nvidia_smi.txt" "NVIDIA GPU 概览"
    
    # 详细查询
    safe_exec "nvidia-smi -q" "$gpu_dir/nvidia_smi_query.txt" "NVIDIA GPU 详细查询"
    
    # 显示更详细的信息
    safe_exec "nvidia-smi -q -d MEMORY" "$gpu_dir/nvidia_smi_memory.txt" "NVIDIA GPU 内存信息"
    safe_exec "nvidia-smi -q -d UTILIZATION" "$gpu_dir/nvidia_smi_utilization.txt" "NVIDIA GPU 利用率"
    safe_exec "nvidia-smi -q -d TEMPERATURE" "$gpu_dir/nvidia_smi_temperature.txt" "NVIDIA GPU 温度"
    safe_exec "nvidia-smi -q -d POWER" "$gpu_dir/nvidia_smi_power.txt" "NVIDIA GPU 电源"
    safe_exec "nvidia-smi -q -d CLOCK" "$gpu_dir/nvidia_smi_clock.txt" "NVIDIA GPU 时钟"
    
    # ECC 错误信息
    safe_exec "nvidia-smi -q -d ECC" "$gpu_dir/nvidia_smi_ecc.txt" "NVIDIA GPU ECC 错误"
    
    # 进程信息
    safe_exec "nvidia-smi pmon -s um -c 1" "$gpu_dir/nvidia_smi_processes.txt" "NVIDIA GPU 进程监控"
    
    # Xorg 日志（如有图形界面）
    for xorg_log in /var/log/Xorg.*.log; do
        if [[ -f "$xorg_log" ]]; then
            local basename
            basename=$(basename "$xorg_log")
            cp "$xorg_log" "$gpu_dir/${basename}" 2>/dev/null && \
                log_info "已复制: $xorg_log" || \
                log_warn "无法复制: $xorg_log"
        fi
    done
}

#==============================================================================
# RAID 卡日志收集
#==============================================================================
collect_raid() {
    log_section "收集 RAID 卡日志"
    
    local raid_dir="$OUTPUT_DIR/raid"
    local raid_found=false
    
    # 收集 lspci 存储控制器信息
    log_info "检测存储控制器..."
    lspci | grep -i "raid\|scsi\|sata\|sas\|nvme" > "$raid_dir/storage_controllers.txt" 2>/dev/null || true
    
    #============================================================================
    # LSI MegaRAID / Broadcom (storcli64/storcli/perccli)
    #============================================================================
    # 优先检测 storcli64，如果不存在则尝试 storcli
    local storcli_cmd=""
    if cmd_exists storcli64; then
        storcli_cmd="storcli64"
        log_info "检测到 storcli64 工具 (LSI/Broadcom MegaRAID)"
        raid_found=true
    elif cmd_exists storcli; then
        storcli_cmd="storcli"
        log_info "检测到 storcli 工具 (LSI/Broadcom MegaRAID)"
        raid_found=true
    fi
    
    if [[ -n "$storcli_cmd" ]]; then
        safe_exec "$storcli_cmd show" "$raid_dir/storcli_show.txt" "storcli 控制器概览"
        safe_exec "$storcli_cmd /c0 show all" "$raid_dir/storcli_c0_all.txt" "storcli C0 详细信息"
        safe_exec "$storcli_cmd /c0 /vall show all" "$raid_dir/storcli_vd_all.txt" "storcli 虚拟磁盘信息"
        safe_exec "$storcli_cmd /c0 /eall /sall show" "$raid_dir/storcli_physical.txt" "storcli 物理磁盘信息"
        safe_exec "$storcli_cmd /c0 /eall /sall show rebuild" "$raid_dir/storcli_rebuild.txt" "storcli 重建状态"
        safe_exec "$storcli_cmd /c0 show events" "$raid_dir/storcli_events.txt" "storcli 事件日志"
    fi
    
    #============================================================================
    # Dell PERC (perccli)
    #============================================================================
    if cmd_exists perccli; then
        log_info "检测到 perccli 工具 (Dell PERC)"
        raid_found=true
        
        safe_exec "perccli show" "$raid_dir/perccli_show.txt" "perccli 控制器概览"
        safe_exec "perccli /c0 show all" "$raid_dir/perccli_c0_all.txt" "perccli C0 详细信息"
        safe_exec "perccli /c0 /vall show all" "$raid_dir/perccli_vd_all.txt" "perccli 虚拟磁盘信息"
        safe_exec "perccli /c0 /eall /sall show" "$raid_dir/perccli_physical.txt" "perccli 物理磁盘信息"
    fi
    
    #============================================================================
    # LSI MegaRAID (旧版 megacli)
    #============================================================================
    if cmd_exists MegaCli; then
        log_info "检测到 MegaCli 工具 (旧版 LSI MegaRAID)"
        raid_found=true
        
        local megacli="MegaCli"
        
        safe_exec "$megacli -AdpAllInfo -aALL" "$raid_dir/megacli_adp_info.txt" "MegaCLI 适配器信息"
        safe_exec "$megacli -LDInfo -Lall -aALL" "$raid_dir/megacli_ld_info.txt" "MegaCLI 逻辑磁盘信息"
        safe_exec "$megacli -PDList -aALL" "$raid_dir/megacli_pd_list.txt" "MegaCLI 物理磁盘列表"
        safe_exec "$megacli -AdpBbuCmd -aALL" "$raid_dir/megacli_bbu.txt" "MegaCLI BBU 信息"
        safe_exec "$megacli -FwTermLog -Dsply -aALL" "$raid_dir/megacli_fw_log.txt" "MegaCLI 固件日志"
        
    elif cmd_exists megacli; then
        log_info "检测到 megacli 工具 (旧版 LSI MegaRAID)"
        raid_found=true
        
        safe_exec "megacli -AdpAllInfo -aALL" "$raid_dir/megacli_adp_info.txt" "MegaCLI 适配器信息"
        safe_exec "megacli -LDInfo -Lall -aALL" "$raid_dir/megacli_ld_info.txt" "MegaCLI 逻辑磁盘信息"
        safe_exec "megacli -PDList -aALL" "$raid_dir/megacli_pd_list.txt" "MegaCLI 物理磁盘列表"
    fi
    
    #============================================================================
    # Adaptec (arcconf)
    #============================================================================
    if cmd_exists arcconf; then
        log_info "检测到 arcconf 工具 (Adaptec RAID)"
        raid_found=true
        
        safe_exec "arcconf getversion" "$raid_dir/arcconf_version.txt" "arcconf 版本信息"
        safe_exec "arcconf getconfig 1" "$raid_dir/arcconf_config.txt" "arcconf 配置信息"
        safe_exec "arcconf getsmartstats 1" "$raid_dir/arcconf_smart.txt" "arcconf SMART 统计"
        safe_exec "arcconf getstatus 1" "$raid_dir/arcconf_status.txt" "arcconf 状态"
        safe_exec "arcconf getlog 1" "$raid_dir/arcconf_log.txt" "arcconf 日志"
    fi
    
    #============================================================================
    # HP Smart Array (ssacli/hpacucli)
    #============================================================================
    if cmd_exists ssacli; then
        log_info "检测到 ssacli 工具 (HP Smart Array)"
        raid_found=true
        
        safe_exec "ssacli ctrl all show detail" "$raid_dir/ssacli_controller.txt" "SSACLI 控制器信息"
        safe_exec "ssacli ctrl all show config detail" "$raid_dir/ssacli_config.txt" "SSACLI 配置详情"
        safe_exec "ssacli ctrl all diag file=/tmp/ssacli_diag.txt" "$raid_dir/ssacli_diag.txt" "SSACLI 诊断信息"
        
    elif cmd_exists hpacucli; then
        log_info "检测到 hpacucli 工具 (HP Smart Array 旧版)"
        raid_found=true
        
        safe_exec "hpacucli ctrl all show detail" "$raid_dir/hpacucli_controller.txt" "HPACUCLI 控制器信息"
        safe_exec "hpacucli ctrl all show config" "$raid_dir/hpacucli_config.txt" "HPACUCLI 配置信息"
    fi
    
    #============================================================================
    # mdadm (Linux 软件 RAID)
    #============================================================================
    if [[ -f /proc/mdstat ]] && grep -q "md" /proc/mdstat 2>/dev/null; then
        log_info "检测到 Linux 软件 RAID (mdadm)"
        raid_found=true
        
        {
            echo "=== /proc/mdstat ==="
            cat /proc/mdstat
            
            echo -e "\n=== mdadm --detail (所有阵列) ==="
            for md in /dev/md*; do
                if [[ -b "$md" ]]; then
                    echo -e "\n--- $md ---"
                    mdadm --detail "$md" 2>/dev/null || echo "无法获取 $md 详情"
                fi
            done
            
            echo -e "\n=== mdadm 配置 ==="
            cat /etc/mdadm/mdadm.conf 2>/dev/null || cat /etc/mdadm.conf 2>/dev/null || echo "配置文件未找到"
        } > "$raid_dir/mdadm_info.txt"
        
        log_info "✓ mdadm 信息收集完成"
    fi
    
    #============================================================================
    # LVM 信息
    #============================================================================
    if cmd_exists lvm || cmd_exists pvdisplay; then
        log_info "收集 LVM 信息..."
        
        {
            echo "=== PV 显示 ==="
            pvdisplay 2>/dev/null || echo "pvdisplay 失败"
            
            echo -e "\n=== VG 显示 ==="
            vgdisplay 2>/dev/null || echo "vgdisplay 失败"
            
            echo -e "\n=== LV 显示 ==="
            lvdisplay 2>/dev/null || echo "lvdisplay 失败"
            
            echo -e "\n=== PV 扫描 ==="
            pvs 2>/dev/null || echo "pvs 失败"
            
            echo -e "\n=== VG 扫描 ==="
            vgs 2>/dev/null || echo "vgs 失败"
            
            echo -e "\n=== LV 扫描 ==="
            lvs 2>/dev/null || echo "lvs 失败"
        } > "$raid_dir/lvm_info.txt"
        
        log_info "✓ LVM 信息收集完成"
    fi
    
    # 如果没有找到 RAID 控制器
    if [[ "$raid_found" == false ]]; then
        log_warn "未检测到 RAID 管理工具，跳过 RAID 详细日志收集"
        log_warn "支持的 RAID 工具: storcli, perccli, MegaCli, arcconf, ssacli, hpacucli"
        echo "未检测到 RAID 工具" > "$raid_dir/no_raid_detected.txt"
    fi
}

#==============================================================================
# 资源快照收集
#==============================================================================
collect_resources() {
    log_section "收集资源快照"
    
    local res_dir="$OUTPUT_DIR/resources"
    
    # 当前资源使用率
    log_info "收集当前资源使用率..."
    {
        echo "=== 当前时间 ==="
        date
        
        echo -e "\n=== CPU 使用率 ==="
        cat /proc/loadavg
        echo ""
        mpstat -P ALL 1 1 2>/dev/null || echo "mpstat 不可用"
        
        echo -e "\n=== 内存使用率 ==="
        free -m
        echo ""
        echo "内存使用率计算:"
        awk '/Mem:/ {printf "已用: %.2f%%\n", $3/$2 * 100}' <(free)
        
        echo -e "\n=== 磁盘使用率 ==="
        df -h
        
        echo -e "\n=== Inode 使用率 ==="
        df -i
    } > "$res_dir/resource_usage.txt"
    
    # 高占用进程
    log_info "收集 TOP 进程信息..."
    {
        echo "=== CPU 占用最高的 20 个进程 ==="
        ps aux --sort=-%cpu | head -n 21
        
        echo -e "\n=== 内存占用最高的 20 个进程 ==="
        ps aux --sort=-%mem | head -n 21
        
        echo -e "\n=== 进程树 ==="
        pstree -p 2>/dev/null || ps auxf | head -n 50
        
        echo -e "\n=== 僵尸进程 ==="
        ps aux | awk '$8 ~ /^Z/ { print $0 }' || echo "无僵尸进程"
    } > "$res_dir/top_processes.txt"
    
    # iostat（如可用）
    if cmd_exists iostat; then
        safe_exec "iostat -x 1 3" "$res_dir/iostat.txt" "IO 统计信息"
    else
        log_warn "iostat 不可用，尝试从 /proc/diskstats 收集信息"
        cat /proc/diskstats > "$res_dir/diskstats.txt" 2>/dev/null || true
    fi
    
    # vmstat 快照
    safe_exec "vmstat 1 3" "$res_dir/vmstat.txt" "虚拟内存统计"
    
    # 网络连接
    log_info "收集网络连接信息..."
    {
        echo "=== 活动连接数统计 ==="
        ss -s 2>/dev/null || netstat -s 2>/dev/null || echo "ss/netstat 不可用"
        
        echo -e "\n=== 各状态连接数 ==="
        ss -ant | awk '{print $1}' | sort | uniq -c | sort -rn 2>/dev/null || \
        netstat -ant | awk '{print $6}' | sort | uniq -c | sort -rn 2>/dev/null || \
        echo "无法获取连接统计"
        
        echo -e "\n=== TIME_WAIT 连接 (TOP 10) ==="
        ss -ant | grep TIME_WAIT | wc -l 2>/dev/null || echo "0"
        
        echo -e "\n=== 监听端口 ==="
        ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || echo "无法获取监听端口"
        
        echo -e "\n=== 网络接口错误 ==="
        ifconfig -a 2>/dev/null | grep -E "(RX|TX).*errors" || ip -s link 2>/dev/null || echo "无法获取接口错误"
    } > "$res_dir/network_stats.txt"
    
    # 文件描述符使用情况
    {
        echo "=== 系统级文件描述符限制 ==="
        cat /proc/sys/fs/file-nr
        
        echo -e "\n=== 各进程文件描述符使用 (TOP 10) ==="
        for pid in $(ls /proc | grep -E '^[0-9]+$' | head -n 50); do
            if [[ -d "/proc/$pid/fd" ]]; then
                count=$(ls "/proc/$pid/fd" 2>/dev/null | wc -l)
                cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' | cut -c1-50)
                echo "$count $pid $cmdline"
            fi
        done | sort -rn | head -n 10
    } > "$res_dir/file_descriptors.txt"
}

#==============================================================================
# 打包与交付
#==============================================================================
package_logs() {
    log_section "打包日志文件"
    
    local tarball_name="${HOSTNAME}_${TIMESTAMP}.tar.gz"
    local tarball_path="/tmp/${tarball_name}"
    
    # 创建压缩包
    log_info "正在打包到: $tarball_path"
    
    if tar -czf "$tarball_path" -C /tmp "$(basename "$OUTPUT_DIR")" 2>/dev/null; then
        log_info "✓ 打包成功"
        
        # 计算文件大小
        local file_size
        file_size=$(du -h "$tarball_path" | cut -f1)
        log_info "压缩包大小: $file_size"
        
        # 计算 MD5
        local md5sum
        md5sum=$(md5sum "$tarball_path" | awk '{print $1}')
        log_info "MD5 校验值: $md5sum"
        
        # 输出最终信息
        echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
        echo -e "${COLOR_GREEN}  日志收集完成${COLOR_RESET}"
        echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}压缩包路径:${COLOR_RESET} $tarball_path"
        echo -e "${COLOR_CYAN}文件大小:${COLOR_RESET}  $file_size"
        echo -e "${COLOR_CYAN}MD5 校验:${COLOR_RESET}  $md5sum"
        echo -e "${COLOR_GREEN}========================================${COLOR_RESET}\n"
        
        # 清理临时目录
        log_info "清理临时目录: $OUTPUT_DIR"
        rm -rf "$OUTPUT_DIR"
        
        # 输出可复制路径
        echo -e "${COLOR_YELLOW}可使用以下命令下载:${COLOR_RESET}"
        echo "  scp root@$(hostname -I | awk '{print $1}'):$tarball_path ./"
        
        return 0
    else
        log_error "打包失败"
        log_info "临时目录保留在: $OUTPUT_DIR"
        return 1
    fi
}

#==============================================================================
# 清理函数（信号捕获）
#==============================================================================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] && [[ -d "$OUTPUT_DIR" ]]; then
        log_warn "脚本异常退出，清理临时目录..."
        rm -rf "$OUTPUT_DIR"
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

#==============================================================================
# 主函数
#==============================================================================
main() {
    echo -e "${COLOR_BLUE}"
    cat << 'EOF'
    ____      _       _         _                  _   _
   / ___|___ | | __ _| |_ ___  | | ___  _   _ _ __| |_(_) ___  _ __
  | |   / _ \| |/ _` | __/ _ \ | |/ _ \| | | | '__| __| |/ _ \| '_ \
  | |__| (_) | | (_| | ||  __/ | | (_) | |_| | |  | |_| | (_) | | | |
   \____\___/|_|\__,_|\__\___| |_|\___/ \__,_|_|   \__|_|\___/|_| |_|
EOF
    echo -e "${COLOR_RESET}"
    
    echo -e "${COLOR_CYAN}服务器故障诊断信息收集脚本 v1.0${COLOR_RESET}"
    echo -e "${COLOR_CYAN}支持系统: CentOS, RHEL, Ubuntu, Debian${COLOR_RESET}\n"
    
    # 执行环境检查
    check_root
    
    # 收集各模块信息
    collect_system_info
    collect_logs
    collect_ipmi
    collect_gpu
    collect_raid
    collect_resources
    
    # 打包
    package_logs
}

# 执行主函数
main "$@"
