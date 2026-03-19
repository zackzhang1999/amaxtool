# AMAX Tool 系统技术文档

## 目录

1. [系统概述](#1-系统概述)
2. [系统架构](#2-系统架构)
3. [核心库详解](#3-核心库详解)
4. [功能模块详解](#4-功能模块详解)
5. [使用方法](#5-使用方法)
6. [开发指南](#6-开发指南)
7. [部署与维护](#7-部署与维护)
8. [故障排查](#8-故障排查)

---

## 1. 系统概述

### 1.1 项目简介

AMAX Tool 是一套面向企业级服务器管理的综合性运维工具集，专为 AMAX 品牌服务器设计。该系统集成了系统信息收集、硬件健康检查、日志管理、软件安装、系统维护和压力测试等功能，帮助运维人员快速诊断问题、部署环境和维护服务器。

### 1.2 设计目标

- **一站式管理**：覆盖服务器运维全生命周期
- **自动化**：减少人工操作，降低出错概率
- **可扩展**：模块化设计，易于添加新功能
- **兼容性**：支持 Ubuntu/Debian 等主流 Linux 发行版

### 1.3 适用场景

- 新服务器上架初始化
- 硬件故障诊断
- 系统性能测试
- 软件环境部署
- 日常巡检维护

---

## 2. 系统架构

### 2.1 目录结构

```
/opt/amaxtool/
├── bin/
│   └── amax-tool              # 主入口程序
├── lib/                       # 公共库函数
│   ├── core.sh               # 核心函数库
│   ├── env.sh                # 环境配置
│   └── utils.sh              # 工具函数
├── modules/                   # 功能模块
│   ├── check/                # 环境检查
│   ├── diskcheck/            # 磁盘检查
│   ├── getlog/               # 日志收集
│   ├── hwtest/               # 硬件测试
│   ├── soft/                 # 软件安装
│   ├── sysinfo/              # 系统信息
│   └── system/               # 系统维护
├── tools/                     # 二进制工具
│   ├── ipmicfg               # IPMI 配置工具
│   ├── storcli64             # RAID 管理工具
│   └── sum                   # 系统信息工具
├── README.md                  # 使用说明
├── install.sh                # 安装脚本
└── DOCUMENTATION.md          # 本文档
```

### 2.2 架构分层

```
┌─────────────────────────────────────────────────────────────┐
│                        用户界面层                            │
│                   (主菜单、交互提示)                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        功能模块层                            │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐  │
│  │  sysinfo │ getlog   │ soft     │ system   │ hwtest   │  │
│  │ diskcheck│ check    │          │          │          │  │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        核心库层                              │
│  ┌──────────────────┬──────────────────┬─────────────────┐ │
│  │    core.sh       │    env.sh        │    utils.sh     │ │
│  │  (颜色/日志/UI)  │  (环境/变量)     │  (工具函数)     │ │
│  └──────────────────┴──────────────────┴─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        系统调用层                            │
│  (ipmitool/smartctl/nvidia-smi/storcli64/dmidecode/fio...)  │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 数据流向

```
用户输入 → 主菜单 → 模块分发 → 功能执行 → 结果输出
                ↓
            日志记录 → /var/log/amax-tool/amax-tool.log
```

---

## 3. 核心库详解

### 3.1 core.sh - 核心函数库

#### 3.1.1 颜色输出函数

```bash
# 基本颜色输出
echo_black "文本"        # 黑色
echo_red "文本"          # 红色 - 用于错误
echo_green "文本"        # 绿色 - 用于成功
echo_yellow "文本"       # 黄色 - 用于警告
echo_blue "文本"         # 蓝色
echo_cyan "文本"         # 青色 - 用于标题
echo_magenta "文本"      # 洋红色
echo_white "文本"        # 白色

# 内部实现
_color_print() {
    local fg="3$1"      # 前景色
    local bg="4$2"      # 背景色
    shift 2
    printf "\033[%s;%sm%s\033[0m\n" "$fg" "$bg" "$*"
}
```

**设计特点：**
- 使用 ANSI 转义码实现跨终端兼容
- 统一格式 `\033[FG;BGm...\033[0m`
- 9 表示默认背景色

#### 3.1.2 日志系统

```bash
# 日志级别
log_info "信息"          # 普通信息
log_warn "警告"          # 警告信息（黄色显示）
log_error "错误"         # 错误信息（红色显示）
log_success "成功"       # 成功信息（绿色显示）

# 日志格式
[2024-03-04 10:30:15] [INFO] 操作信息
[2024-03-04 10:30:16] [ERROR] 错误描述
[2024-03-04 10:30:17] [SUCCESS] 操作成功
```

**日志文件：** `/var/log/amax-tool/amax-tool.log`

#### 3.1.3 UI 函数

```bash
# 显示标题
print_header "标题文本"
# 输出：
# ==================================
#   标题文本
# ==================================

# 显示分隔线
print_separator
# 输出：----------------------------------------

# 显示进度条
show_progress 5 "处理中..."
# 5秒后完成，显示进度条动画

# 显示旋转等待
show_spinner $PID "处理中..."
# 显示旋转动画直到进程结束
```

#### 3.1.4 菜单函数

```bash
show_menu "菜单标题" "选项1" "选项2" "选项3"
# 输出：
# ==================================
#   菜单标题
# ==================================
#   1. 选项1
#   2. 选项2
#   3. 选项3
#   q. 退出
# ----------------------------------------
```

#### 3.1.5 通用检查函数

```bash
check_root          # 检查是否以 root 运行
check_command CMD   # 检查命令是否存在
check_internet      # 检查网络连接
```

### 3.2 env.sh - 环境配置

#### 3.2.1 路径定义

```bash
readonly AMAX_BASE_DIR="/opt/amaxtool"
readonly AMAX_LIB_DIR="$AMAX_BASE_DIR/lib"
readonly AMAX_MODULES_DIR="$AMAX_BASE_DIR/modules"
readonly AMAX_TOOLS_DIR="$AMAX_BASE_DIR/tools"
readonly AMAX_LOG_DIR="/opt/amax-log"
```

#### 3.2.2 硬件检测

```bash
# 自动检测硬件
HW_RAID=$(lspci | grep -i lsi)      # 检测 RAID 卡
HW_NVIDIA=$(lspci | grep -i nvidia) # 检测 NVIDIA GPU
```

#### 3.2.3 工具路径

```bash
readonly TOOL_IPMICFG="$AMAX_TOOLS_DIR/ipmicfg"
readonly TOOL_STORCLI64="$AMAX_TOOLS_DIR/storcli64"
```

#### 3.2.4 系统信息获取函数

```bash
get_server_sn       # 获取服务器序列号
get_raid_sn         # 获取 RAID 卡序列号
get_timestamp       # 获取时间戳（YYYY_MM_DD_HHMMSS）
get_date            # 获取日期（YYYY_MM_DD）
```

### 3.3 utils.sh - 工具函数

#### 3.3.1 Python 模块管理

```bash
check_python_module MODULE_NAME      # 检查 Python 模块
install_python_module MODULE_NAME    # 安装 Python 模块
```

#### 3.3.2 包管理

```bash
install_package PACKAGE_NAME         # 安装系统包
```

#### 3.3.3 服务管理

```bash
service_disable SERVICE_NAME         # 禁用并停止服务
service_enable SERVICE_NAME          # 启用并启动服务
```

#### 3.3.4 文件操作

```bash
backup_file FILE_PATH                # 备份文件
safe_write FILE_PATH CONTENT         # 安全写入（自动备份）
```

#### 3.3.5 IPMI 操作

```bash
ipmi_config_network IP NETMASK GW    # 配置 IPMI 网络
ipmi_create_user ID NAME PASS CHAN   # 创建 IPMI 用户
```

#### 3.3.6 RAID 操作

```bash
raid_get_disk_status SLOT            # 获取磁盘状态
raid_set_good SLOT                   # 设置磁盘为 good 状态
raid_import_foreign                  # 导入外部配置
raid_silence_alarm                   # 关闭告警
```

---

## 4. 功能模块详解

### 4.1 系统信息模块 (sysinfo)

**文件位置：** `modules/sysinfo/run.sh`

**功能：** 全面收集服务器硬件和软件信息

#### 4.1.1 信息收集项

| 类别 | 收集内容 |
|------|----------|
| 基本信息 | 服务器 SN、操作系统、内核版本、服务器型号 |
| CPU 信息 | 型号、核心数、逻辑处理器数、缓存大小 |
| 内存信息 | 总容量、内存条数、单条规格 |
| 磁盘信息 | 所有磁盘列表、容量、型号 |
| RAID 信息 | RAID 卡 SN、温度、磁盘状态 |
| GPU 信息 | NVIDIA GPU 型号、温度、显存使用 |

#### 4.1.2 信息来源

```bash
# CPU
cat /proc/cpuinfo
dmidecode -s processor-version

# 内存
dmidecode -t memory
free -m

# 磁盘
lsblk / fdisk -l
smartctl -i

# RAID
storcli64 /c0 show all

# GPU
nvidia-smi
```

#### 4.1.3 子菜单

```
系统信息
  1. 显示所有信息
  2. 基本信息
  3. CPU 信息
  4. 内存信息
  5. 磁盘信息
  6. RAID 信息
  7. GPU 信息
  8. 保存到文件
  b. 返回主菜单
```

### 4.2 日志收集模块 (getlog)

**文件位置：** `modules/getlog/run.sh`

**功能：** 收集系统各类日志用于故障排查

#### 4.2.1 收集内容

| 日志类型 | 文件/命令 | 说明 |
|----------|-----------|------|
| IPMI 日志 | `ipmitool sel list` | 系统事件日志 |
| | `ipmitool sdr` | 传感器数据 |
| RAID 日志 | `storcli64 /c0 show all` | RAID 状态 |
| | `storcli64 /c0 show events` | RAID 事件 |
| | `storcli64 /c0/eall/sall show` | 磁盘详情 |
| GPU 日志 | `nvidia-smi -a` | GPU 详细信息 |
| 系统日志 | `dmidecode` | DMI 信息 |
| | `dmesg` | 内核日志 |
| | `/var/log/syslog` | 系统日志 |
| | `/var/log/kern.log` | 内核日志 |
| | `lspci -vvv` | PCI 设备详情 |

#### 4.2.2 输出格式

```
/opt/amax-log/
├── ipmi/
│   ├── ipmi-sel.log
│   └── ipmi-sdr.log
├── RAID_SN/
│   ├── raid-stat.log
│   ├── raid-term.log
│   ├── raid-all.log
│   ├── events.log
│   ├── raid-disk.log
│   └── raid-bbu.log
├── nvidia-smi.log
├── nvidia-smi-all.log
├── dmidecode.log
├── system-*.log
└── syslog* (复制)
```

#### 4.2.3 打包上传

自动打包为：`/tmp/log_${SERVERSN}_${TIME}.tar.gz`
支持上传到远程服务器（通过 SSH/SCP）

### 4.3 软件安装模块 (soft)

**文件位置：** `modules/soft/run.sh`

**功能：** 自动化安装常用软件和驱动

#### 4.3.1 NVIDIA 驱动安装

**流程：**
1. 检查网络连接
2. 检查 NVIDIA GPU 存在
3. 禁用 nouveau 驱动
4. 下载驱动文件
5. 停止图形界面
6. 安装驱动
7. 恢复图形界面
8. 可选重启

**命令：**
```bash
./nvidia-driver.run --ui=none --no-questions --accept-license \
    --no-nouveau-check --no-x-check
```

#### 4.3.2 Anaconda + PyTorch 安装

**流程：**
1. 获取最新 Anaconda 下载链接
2. 下载安装包
3. 静默安装到 `$HOME/anaconda3`
4. 添加到 PATH
5. 创建 conda 环境（deeplearning）
6. 安装 PyTorch、torchvision、torchaudio
7. 安装常用包（scikit-learn、pandas、matplotlib）

#### 4.3.3 Docker + GPU 支持安装

**流程：**
1. 安装 Docker CE
2. 启动并启用 Docker 服务
3. 添加 NVIDIA Container Toolkit 仓库
4. 安装 nvidia-container-toolkit
5. 配置 Docker runtime
6. 测试 GPU 容器

#### 4.3.4 Mellanox 网卡配置

| 功能 | 命令 |
|------|------|
| 切换 IB 模式 | `mlxconfig -d $DEV set LINK_TYPE_P1=1 LINK_TYPE_P2=1` |
| 切换 Eth 模式 | `mlxconfig -d $DEV set LINK_TYPE_P1=2 LINK_TYPE_P2=2` |
| 启用 PXE | `mlxconfig -d $DEV set EXP_ROM_PXE_ENABLE=1` |

### 4.4 系统维护模块 (system)

**文件位置：** `modules/system/run.sh`

**功能：** 系统配置和日常维护

#### 4.4.1 关闭自动更新

**操作：**
```bash
systemctl disable/stop apt-daily-upgrade.timer
systemctl disable/stop apt-daily.timer
# 修改配置文件 /etc/apt/apt.conf.d/
```

#### 4.4.2 锁定内核

**原理：** 修改 `/etc/default/grub`，设置 `GRUB_DEFAULT` 为当前内核

#### 4.4.3 IPMI 配置

**配置项：**
- IP 地址
- 子网掩码
- 网关
- 用户名/密码

**创建用户 ID：** 6（遵循 IPMI 规范）

#### 4.4.4 IP 冲突检测

**方法：** 使用 `arp-scan -l` 扫描网络，检测同一 IP 对应多个 MAC 地址的情况

#### 4.4.5 rc.local 服务

**功能：** 创建 systemd 服务管理 rc.local，实现开机自定义脚本执行

#### 4.4.6 更换软件源

**支持版本：**
- Ubuntu 16.04 (xenial)
- Ubuntu 18.04 (bionic)
- Ubuntu 20.04 (focal)
- Ubuntu 22.04 (jammy)

### 4.5 硬件测试模块 (hwtest)

**文件位置：** `modules/hwtest/run.sh`

**功能：** 硬件性能测试和压力测试

#### 4.5.1 磁盘 I/O 测试 (FIO)

**测试模式：**

| 模式 | 块大小 | 说明 |
|------|--------|------|
| 顺序写 | 1MB | 测试大文件写入性能 |
| 顺序读 | 1MB | 测试大文件读取性能 |
| 随机写 | 4KB | 测试小文件随机写入 |
| 随机读 | 4KB | 测试小文件随机读取 |

**参数：**
```bash
fio --ioengine=libaio --direct=1 --iodepth=64 \
    --numjobs=8 --runtime=60 --time_based
```

#### 4.5.2 内存带宽测试 (STREAM)

**测试内容：**
- COPY 操作带宽
- SCALE 操作带宽
- SUM 操作带宽
- TRIAD 操作带宽

#### 4.5.3 GPU 压力测试 (gpu-burn)

**功能：** 使用 CUDA 进行 GPU 满载测试

**参数：**
- `-tc SECONDS`：测试持续时间

**运行方式：**
- 前台运行
- screen 后台运行

#### 4.5.4 CPU 压力测试 (stress-ng)

**测试算法：**

| 算法 | 说明 |
|------|------|
| int8/int16/int32/int64 | 整数运算 |
| float/double | 浮点运算 |
| crc16 | CRC 校验 |

**支持运行方式：**
- 快速测试（多种算法，每项 10 秒）
- 持续压力测试
- screen 后台运行

#### 4.5.5 PCI-E 设备扫描

**检查项：**
- 设备基本信息（厂商、型号、类别）
- PCI-E 最大速率/通道数
- PCI-E 当前速率/通道数
- 网卡协商速率（ethtool）

**异常检测：** 当前速率未达到最大潜力时黄色警告

### 4.6 磁盘检查模块 (diskcheck)

**文件位置：** `modules/diskcheck/run.sh`

**功能：** RAID 和磁盘健康状态检查

#### 4.6.1 RAID 磁盘状态检查

**检查内容：**
- RAID 卡温度（>90°C 报警）
- 每个磁盘状态（Onln/Offln）
- RAID 阵列整体状态

**磁盘状态定义：**
- `Onln`：在线正常
- `Offln`：离线
- `UGood`：未配置好
- `GHS`：全局热备

#### 4.6.2 RAID 磁盘修复

**修复流程：**
1. 扫描所有磁盘槽位（0-7）
2. 对非 Online 状态的磁盘执行：
   - `set good`：标记为可用
   - `set online`：设置为在线
3. 导入外部配置
4. 关闭 RAID 告警

#### 4.6.3 SMART 健康检查

**关键指标：**

| 指标 | 说明 | 阈值 |
|------|------|------|
| Reallocated_Sector_Ct | 重映射扇区数 | >0 警告 |
| Current_Pending_Sector | 待处理扇区 | >0 警告 |
| Offline_Uncorrectable | 离线不可修复 | >0 警告 |
| Reported_Uncorrect | 报告不可修复 | >0 警告 |

### 4.7 运行环境检测模块 (check)

**文件位置：** `modules/check/run.sh`

**功能：** 检查系统依赖是否满足

#### 4.7.1 依赖命令检查

检查命令：
- fio - 磁盘测试
- ipmitool - IPMI 管理
- stress-ng - 压力测试
- screen - 后台会话
- storcli64 - RAID 管理
- arp-scan - 网络扫描

#### 4.7.2 Python 模块检查

检查模块：
- GPUtil - GPU 信息获取

#### 4.7.3 硬件检测

检测项目：
- RAID 卡（LSI）
- NVIDIA GPU
- IPMI 设备

#### 4.7.4 网络检查

- 外网连接（ping 8.8.8.8）
- 网络接口列表

---

## 5. 使用方法

### 5.1 安装

```bash
# 进入目录
cd /opt/amaxtool

# 运行安装脚本
sudo ./install.sh

# 安装系统依赖（可选）
# 安装过程中会提示
```

**安装内容：**
1. 语法检查
2. 设置文件权限
3. 创建日志目录
4. 创建系统快捷方式

### 5.2 主程序使用

```bash
# 方式1: 使用快捷方式
sudo amax-tool

# 方式2: 直接运行
sudo /opt/amaxtool/bin/amax-tool

# 方式3: 兼容旧方式
sudo /opt/amaxtool/start
```

### 5.3 主菜单

```
==================================
  AMAX 服务器管理工具 v2.0
==================================
  1. 系统信息
  2. 日志收集
  3. 软件安装
  4. 系统维护
  5. 硬件测试
  6. 磁盘检查
  7. 运行环境检测
  q. 退出
----------------------------------------
请选择操作:
```

### 5.4 各模块使用示例

#### 5.4.1 查看系统信息

```
请选择操作: 1
系统信息
  1. 显示所有信息
  2. 基本信息
  ...
```

#### 5.4.2 收集日志

```
请选择操作: 2
# 自动收集所有日志
# 提示是否上传
是否上传日志到服务器? [y/N]: y
```

#### 5.4.3 安装 NVIDIA 驱动

```
请选择操作: 3
软件安装
  1. 安装 NVIDIA 驱动
  ...
请选择: 1
# 自动完成驱动安装
# 提示是否重启
```

#### 5.4.4 配置 IPMI

```
请选择操作: 4
系统维护
  3. 配置 IPMI
请输入 IP 地址: 192.168.1.100
请输入子网掩码: 255.255.255.0
请输入网关地址: 192.168.1.1
请输入用户名: admin
请输入密码: ********
```

#### 5.4.5 运行 GPU 压力测试

```
请选择操作: 5
硬件测试
  3. GPU 压力测试
请输入测试时间(秒，1小时=3600): 3600
请选择运行方式：
  1. 当前进程直接运行
  2. screen 后台运行
```

### 5.5 查看日志

```bash
# 查看工具日志
cat /var/log/amax-tool/amax-tool.log

# 查看收集的系统日志
ls /opt/amax-log/
```

---

## 6. 开发指南

### 6.1 添加新模块

#### 步骤1: 创建模块目录

```bash
mkdir -p /opt/amaxtool/modules/mymodule
```

#### 步骤2: 创建 run.sh

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# 模块功能
my_function() {
    print_header "我的模块"
    echo "模块内容"
}

# 菜单
show_menu() {
    while true; do
        clear
        print_header "我的模块"
        echo "  1. 功能1"
        echo "  b. 返回主菜单"
        print_separator
        
        read -rp "请选择: " choice
        case "$choice" in
            1) my_function; read -r ;;
            b|B) break ;;
            *) log_warn "无效选择"; sleep 1 ;;
        esac
    done
}

show_menu
```

#### 步骤3: 添加到主菜单

编辑 `/opt/amaxtool/bin/amax-tool`：

```bash
show_main_menu() {
    # ... 现有菜单 ...
    echo "  8. 我的模块"  # 添加新选项
}

main() {
    case "$choice" in
        # ... 现有选项 ...
        8)
            run_module "mymodule"  # 添加处理
            ;;
    esac
}
```

### 6.2 代码规范

#### 6.2.1 文件头

```bash
#!/bin/bash
#===============================================================================
# AMAX Tool - Module Name
# Description: Brief description
#===============================================================================
```

#### 6.2.2 变量命名

```bash
# 只读常量 - 全大写
readonly MAX_RETRIES=3
readonly CONFIG_FILE="/path/to/file"

# 局部变量 - 小写
local counter=0
local temp_file="/tmp/$$.tmp"

# 环境变量 - 全大写前缀
export AMAX_LOG_DIR="/var/log/amax-tool"
```

#### 6.2.3 函数命名

```bash
# 动词_名词 或 动作描述
check_root()
show_menu()
install_package()
get_server_sn()
```

#### 6.2.4 错误处理

```bash
# 检查命令返回值
if ! command -v somecmd &>/dev/null; then
    log_error "命令未找到"
    return 1
fi

# 检查文件存在
if [[ ! -f "$file" ]]; then
    log_error "文件不存在: $file"
    return 1
fi

# 使用 || 处理失败
mkdir -p "$dir" || {
    log_error "创建目录失败"
    return 1
}
```

### 6.3 使用库函数

```bash
# 日志
log_info "信息"
log_warn "警告"
log_error "错误"
log_success "成功"

# 颜色输出
echo_red "错误信息"
echo_green "成功信息"
echo_yellow "警告信息"
echo_cyan "标题"

# UI
print_header "标题"
print_separator
show_progress 5 "等待中..."

# 检查
check_root || exit 1
check_command "fio" || log_warn "fio 未安装"

# 用户交互
if confirm "确认执行?"; then
    # 执行操作
fi

read_input "请输入值" var_name true  # 必填
```

---

## 7. 部署与维护

### 7.1 系统要求

**最低要求：**
- Ubuntu 16.04+ / Debian 9+
- 1GB RAM
- 100MB 磁盘空间

**推荐配置：**
- Ubuntu 20.04 LTS
- 4GB+ RAM
- 500MB+ 磁盘空间

### 7.2 依赖安装

```bash
# 基础依赖
apt-get update
apt-get install -y fio ipmitool stress-ng screen \
    arp-scan smartmontools pciutils ethtool bc

# Python 依赖
pip3 install GPUtil

# RAID 工具（Broadcom 官网下载）
# https://www.broadcom.com/support/download-search
wget https://docs.broadcom.com/.../storcli64
chmod +x storcli64
mv storcli64 /opt/amaxtool/tools/
```

### 7.3 权限配置

```bash
# 设置目录权限
chown -R root:root /opt/amaxtool
chmod 755 /opt/amaxtool/bin/amax-tool
chmod 755 /opt/amaxtool/modules/*/run.sh
chmod 755 /opt/amaxtool/tools/*

# 日志目录
mkdir -p /var/log/amax-tool
chmod 755 /var/log/amax-tool
```

### 7.4 备份策略

```bash
# 备份整个工具目录
tar -czf /backup/amaxtool_$(date +%Y%m%d).tar.gz /opt/amaxtool

# 备份日志
tar -czf /backup/amax_logs_$(date +%Y%m%d).tar.gz /var/log/amax-tool

# 定时备份（添加到 crontab）
0 2 * * * tar -czf /backup/amaxtool_$(date +\%Y\%m\%d).tar.gz /opt/amaxtool
```

### 7.5 更新流程

```bash
# 1. 备份现有版本
cp -r /opt/amaxtool /opt/amaxtool.bak.$(date +%Y%m%d)

# 2. 拉取/解压新版本
cd /opt
tar -xzf amaxtool-new.tar.gz

# 3. 恢复配置文件（如果有）
cp /opt/amaxtool.bak.*/lib/env.sh /opt/amaxtool/lib/env.sh

# 4. 重新安装
sudo /opt/amaxtool/install.sh

# 5. 验证
sudo amax-tool
```

---

## 8. 故障排查

### 8.1 常见问题

#### Q1: 运行时报 "Permission denied"

**原因：** 脚本没有执行权限

**解决：**
```bash
sudo chmod +x /opt/amaxtool/bin/amax-tool
sudo chmod +x /opt/amaxtool/modules/*/run.sh
```

#### Q2: 颜色输出显示乱码

**原因：** 终端不支持 ANSI 转义码

**解决：**
- 使用支持的颜色终端（xterm、gnome-terminal 等）
- 检查 TERM 环境变量：`echo $TERM`

#### Q3: storcli64 命令找不到

**原因：** 工具未安装或不在 PATH

**解决：**
```bash
# 检查工具是否存在
ls -la /opt/amaxtool/tools/storcli64

# 检查 RAID 卡
lspci | grep -i lsi
```

#### Q4: IPMI 配置失败

**原因：**
1. 没有 IPMI 设备
2. IPMI 未启用

**检查：**
```bash
# 检查设备
ls -la /dev/ipmi0

# 加载 IPMI 模块
modprobe ipmi_si
modprobe ipmi_devintf
```

#### Q5: 日志收集失败

**原因：** 磁盘空间不足或权限不足

**解决：**
```bash
# 检查磁盘空间
df -h /tmp
df -h /opt

# 检查权限
ls -ld /var/log
```

### 8.2 调试模式

```bash
# 启用 bash 调试
bash -x /opt/amaxtool/bin/amax-tool

# 查看详细日志
tail -f /var/log/amax-tool/amax-tool.log
```

### 8.3 获取帮助

查看日志文件获取详细的错误信息：
```bash
cat /var/log/amax-tool/amax-tool.log
```

---

## 附录

### A. 命令参考

#### 系统信息
- `dmidecode` - DMI 信息
- `lspci` - PCI 设备
- `lsusb` - USB 设备
- `lscpu` - CPU 信息

#### 磁盘管理
- `smartctl` - SMART 检测
- `fdisk`/`parted` - 分区管理
- `lsblk` - 块设备
- `storcli64` - RAID 管理

#### 网络管理
- `ipmitool` - IPMI 管理
- `arp-scan` - ARP 扫描
- `ethtool` - 网卡配置

#### 性能测试
- `fio` - I/O 测试
- `stress-ng` - 压力测试
- `stream` - 内存带宽

### B. 文件清单

```
/opt/amaxtool/
├── bin/amax-tool              [主程序]
├── lib/
│   ├── core.sh               [核心库]
│   ├── env.sh                [环境配置]
│   └── utils.sh              [工具函数]
├── modules/
│   ├── check/run.sh          [环境检查]
│   ├── diskcheck/run.sh      [磁盘检查]
│   ├── getlog/run.sh         [日志收集]
│   ├── hwtest/run.sh         [硬件测试]
│   ├── soft/run.sh           [软件安装]
│   ├── sysinfo/run.sh        [系统信息]
│   └── system/run.sh         [系统维护]
├── tools/
│   ├── ipmicfg               [IPMI 工具]
│   ├── storcli64             [RAID 工具]
│   └── sum                   [系统工具]
├── install.sh                [安装脚本]
└── README.md                 [使用说明]
```

### C. 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 2.0 | 2025-03 | 重构版本，模块化设计 |
| 1.0 | 2024-02 | 初始版本 |

---

**文档版本：** 2.0  
**最后更新：** 2025-03-04  
**维护者：** AMAX Team
