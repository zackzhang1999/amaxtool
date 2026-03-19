# AMAX Tool - 详细使用说明

## 目录

1. [项目概述](#项目概述)
2. [安装部署](#安装部署)
3. [快速开始](#快速开始)
4. [功能模块详解](#功能模块详解)
   - [系统信息](#系统信息)
   - [日志收集](#日志收集)
   - [软件安装](#软件安装)
   - [系统维护](#系统维护)
   - [硬件测试](#硬件测试)
   - [磁盘检查](#磁盘检查)
   - [运行环境检测](#运行环境检测)
5. [常见问题](#常见问题)
6. [故障排查](#故障排查)
7. [附录](#附录)

---

## 项目概述

AMAX Tool 是一个专为服务器管理和维护设计的综合性工具集，适用于数据中心和服务器运维场景。它集成了系统信息查看、日志收集、硬件测试、系统维护等多种功能，帮助管理员快速诊断和维护服务器。

### 主要特性

- **一站式管理**：整合多种常用运维工具，无需记忆复杂命令
- **交互式操作**：菜单驱动的交互界面，操作简单直观
- **自动化脚本**：自动化执行复杂的检查和配置任务
- **详细报告**：生成详细的检测报告和日志文件
- **硬件兼容**：支持多种服务器硬件（LSI RAID、NVIDIA GPU、IPMI 等）

### 适用场景

- 服务器日常巡检和维护
- 硬件故障诊断和排查
- 新服务器部署和验收
- 系统性能测试和评估
- 日志收集和故障分析

---

## 安装部署

### 系统要求

- **操作系统**：Ubuntu 18.04/20.04/22.04, CentOS 7/8, RHEL 7/8
- **权限要求**：root 或具有 sudo 权限的用户
- **硬件支持**：支持 x86_64 架构服务器
- **依赖工具**：bash, python3, 基础系统工具

### 安装步骤

#### 方式一：直接克隆安装

```bash
# 克隆项目到 /opt 目录
cd /opt
git clone <repository_url> amaxtool

# 赋予执行权限
chmod +x amaxtool/bin/amax-tool
chmod +x amaxtool/modules/*/run.sh
chmod +x amaxtool/modules/hwtest/benchmark/*.sh
```

#### 方式二：使用安装脚本

```bash
cd /opt/amaxtool
sudo ./install.sh
```

#### 创建快捷方式（可选）

```bash
# 创建全局命令
sudo ln -s /opt/amaxtool/bin/amax-tool /usr/local/bin/amax-tool

# 现在可以直接运行
amax-tool
```

### 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y \
    fio ipmitool stress-ng screen arp-scan smartmontools \
    pciutils ethtool dmidecode bc lsb-release

# CentOS/RHEL
sudo yum install -y \
    fio ipmitool stress-ng screen arp-scan smartmontools \
    pciutils ethtool dmidecode bc redhat-lsb-core
```

### 安装可选工具

```bash
# 安装 StorCLI (RAID 管理工具)
cd /tmp
wget https://docs.broadcom.com/docs-and-downloads/raid-controllers/raid-controllers-common-files/007-007-099-00_1_StorCLI.zip
unzip 007-007-099-00_1_StorCLI.zip
chmod +x storcli64
sudo cp storcli64 /opt/amaxtool/tools/

# 编译 STREAM 内存测试工具
cd /opt/amaxtool/modules/hwtest/stream
gcc -O3 -fopenmp -DSTREAM_ARRAY_SIZE=80000000 stream.c -o stream

# 编译 GPU 压力测试工具 (如服务器有 NVIDIA GPU)
cd /opt/amaxtool/modules/hwtest/benchmark/gpu-burn
make
```

---

## 快速开始

### 启动工具

```bash
# 方式一：使用完整路径
sudo /opt/amaxtool/bin/amax-tool

# 方式二：使用快捷方式（如已创建）
sudo amax-tool
```

### 主菜单

启动后将看到如下主菜单：

```
========================================
        AMAX 服务器管理工具 v2.0
========================================
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

### 基本操作流程

1. 输入对应的数字选择功能模块
2. 根据子菜单提示选择具体功能
3. 按提示输入必要的信息（如 IP 地址、路径等）
4. 查看结果并按提示继续或返回

---

## 功能模块详解

### 系统信息

**功能描述**：查看服务器的详细硬件配置信息，包括 CPU、内存、磁盘、RAID、GPU 等。

**使用路径**：主菜单 → 1. 系统信息

**子菜单功能**：

| 选项 | 功能 | 说明 |
|------|------|------|
| 1 | 查看所有信息 | 显示完整的系统信息汇总 |
| 2 | CPU 信息 | 显示 CPU 型号、核心数、缓存、频率等 |
| 3 | 内存信息 | 显示内存总量、内存条详情、频率等 |
| 4 | 磁盘信息 | 列出所有磁盘设备及容量 |
| 5 | RAID 信息 | 显示 RAID 卡状态和磁盘阵列信息 |
| 6 | GPU 信息 | 显示 NVIDIA GPU 状态（如有） |
| 7 | 网络信息 | 显示网卡信息和配置 |
| 8 | 保存到文件 | 将系统信息保存到文件 |

**使用示例**：

```
请选择: 1
[INFO] 正在收集系统信息...

========== 基本信息 ==========
主机名: server01
序列号: ABC123456789
厂商: Supermicro
操作系统: Ubuntu 20.04.5 LTS
内核版本: 5.4.0-100-generic

========== CPU 信息 ==========
型号: Intel(R) Xeon(R) Gold 6248R CPU @ 3.00GHz
插槽数: 2
每颗核心: 24
总核心数: 48
线程数: 96

...（更多信息）
```

**输出保存**：
- 保存路径：`/var/log/amax-tool/sysinfo/`
- 文件名格式：`sysinfo_YYYYMMDD_HHMMSS.txt`

---

### 日志收集

**功能描述**：收集各类系统日志用于故障排查，自动打包为压缩文件。

**使用路径**：主菜单 → 2. 日志收集

**收集内容**：

| 日志类型 | 内容说明 |
|----------|----------|
| IPMI 日志 | SEL 事件日志、SDR 传感器数据、传感器实时值 |
| RAID 日志 | RAID 卡状态、事件日志、磁盘信息 |
| GPU 日志 | nvidia-smi 输出、GPU 进程信息 |
| 系统日志 | dmesg、syslog、硬件信息 |

**使用步骤**：

1. 选择 `2. 日志收集` 进入子菜单
2. 选择要收集的日志类型（建议全选）
3. 选择是否上传到其他服务器
4. 等待收集完成

**输出文件**：
- 保存路径：`/var/log/amax-tool/logs/`
- 文件名格式：`server_logs_<hostname>_<timestamp>.tar.gz`

**上传到远程服务器**：

如果选择上传，需要配置以下信息：
- 远程服务器 IP
- 用户名
- 密码
- 目标路径（默认 `/tmp/`）

---

### 软件安装

**功能描述**：自动化安装常用软件和驱动。

**使用路径**：主菜单 → 3. 软件安装

**可安装软件**：

| 选项 | 软件 | 说明 |
|------|------|------|
| 1 | NVIDIA 驱动 | 自动检测并安装最新驱动 |
| 2 | Anaconda + PyTorch | 深度学习环境一键安装 |
| 3 | Docker + GPU 支持 | 安装 Docker 并配置 GPU 支持 |
| 4 | Mellanox 网卡配置 | InfiniBand/Ethernet 模式切换、PXE 配置 |

**使用示例 - 安装 NVIDIA 驱动**：

```
请选择: 1
[INFO] 检测显卡型号...
[INFO] 发现显卡: NVIDIA A100-SXM4-40GB
[INFO] 正在下载驱动...
[INFO] 安装驱动中，请耐心等待...
[SUCCESS] NVIDIA 驱动安装完成
[INFO] 请重启系统以生效
```

**使用示例 - 安装 Docker**：

```
请选择: 3
[INFO] 安装 Docker CE...
[INFO] 配置 Docker 服务...
[INFO] 安装 nvidia-docker2...
[SUCCESS] Docker 安装完成
[INFO] 运行 'docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi' 测试
```

---

### 系统维护

**功能描述**：系统配置和维护工具。

**使用路径**：主菜单 → 4. 系统维护

**功能列表**：

| 选项 | 功能 | 说明 |
|------|------|------|
| 1 | 关闭系统自动更新 | 禁用 Ubuntu 自动更新服务 |
| 2 | 锁定当前内核 | 设置 GRUB 默认启动当前内核 |
| 3 | 配置 IPMI | 设置 IPMI 网络和用户 |
| 4 | IP 冲突检测 | 使用 arp-scan 检测 IP 冲突 |
| 5 | 配置 rc.local 服务 | 配置开机启动脚本 |
| 6 | 更换为阿里云软件源 | 更换为阿里云镜像源 |
| 7 | 综合检测 | 服务器硬件健康综合检查 |

#### 功能详解

**关闭系统自动更新**：

禁用系统的自动更新服务，适用于生产环境服务器。

```
请选择: 1
[INFO] 停止自动更新服务...
[INFO] 修改配置文件...
[SUCCESS] 系统自动更新已关闭
```

**锁定当前内核**：

设置 GRUB 默认启动项为当前内核版本，防止自动升级后启动新内核。

```
请选择: 2
[INFO] 当前内核: 5.4.0-100-generic
[INFO] 设置 GRUB 默认启动项...
[SUCCESS] 内核已锁定
```

**配置 IPMI**：

交互式配置 IPMI 网络和用户。

```
请选择: 3
========== 配置 IPMI ==========
请输入 IP 地址: 192.168.1.100
请输入子网掩码: 255.255.255.0
请输入网关地址: 192.168.1.1
请输入用户名: admin
请输入密码: ********
[INFO] 配置网络...
[INFO] 创建用户...
[SUCCESS] IPMI 配置完成
```

**IP 冲突检测**：

扫描局域网检测是否存在 IP 地址冲突。

```
请选择: 4
[INFO] 扫描网络...
Interface: eth0, datalink type: EN10MB (Ethernet)
Starting arp-scan 1.9.5 with 256 hosts
192.168.1.1    00:11:22:33:44:55    Dell Inc.
192.168.1.100  00:aa:bb:cc:dd:ee    Super Micro
192.168.1.100  00:aa:bb:cc:dd:ff    Super Micro  <-- 冲突!
[ERROR] IP 冲突: 192.168.1.100 被多个 MAC 使用
```

**综合检测**：

执行全面的服务器硬件健康检查，包括：

- IPMI 传感器状态（温度、电压、风扇）
- RAID 卡状态检查
- 硬盘 SMART 健康检查
- CPU 和内存状态
- IPMI 系统事件日志分析
- PCI-E 设备速率检查
- 安全事件检查（SSH 暴力破解等）

```
请选择: 7
[INFO] 启动服务器硬件健康综合检测...
此检测将检查以下项目:
  - IPMI 传感器状态（温度、电压、风扇）
  - RAID 卡及磁盘状态
  - 硬盘 SMART 健康
  - CPU 和内存状态
  - IPMI 系统事件日志
  - PCI-E 设备速率
  - 安全事件（SSH暴力破解等）

是否继续? (y/n): y

========================================
  IPMI 传感器检查
========================================
[PASS] 所有 IPMI 传感器正常

关键传感器状态:
  CPU1 Temp            45.0       degrees C
  CPU2 Temp            47.0       degrees C
  System Temp          32.0       degrees C
  FAN1                 4500       RPM
...

========================================
  检查汇总
========================================
检查时间: 2026-03-19 10:30:00
主机名: server01

整体状态: ✓ PASS - 所有检查项正常

建议操作:
  - 系统硬件健康状态良好
  - 建议定期运行此检查
```

---

### 硬件测试

**功能描述**：硬件性能测试和压力测试。

**使用路径**：主菜单 → 5. 硬件测试

**功能列表**：

| 选项 | 功能 | 说明 |
|------|------|------|
| 1 | 磁盘 I/O 性能测试 | FIO 顺序/随机读写测试 |
| 2 | 内存带宽测试 | STREAM 内存性能测试 |
| 3 | GPU 压力测试 | gpu-burn CUDA 压力测试 |
| 4 | CPU 压力测试 | stress-ng 多算法压力测试 |
| 5 | PCI-E 设备扫描 | 检查 PCI-E 设备链接状态 |
| 6 | 综合测试 | CPU+内存+GPU 同时压力测试 |

#### 功能详解

**磁盘 I/O 性能测试**：

使用 FIO 工具测试磁盘性能，需要指定测试目录。

```
请选择: 1
========== 磁盘 I/O 性能测试 ==========
请输入测试目录 (例如 /data1): /data1
[INFO] 开始顺序写测试 (1MB block, 10GB)...
[INFO] 开始顺序读测试 (1MB block, 10GB)...
[INFO] 开始随机写测试 (4KB block, 10GB)...
[INFO] 开始随机读测试 (4KB block, 10GB)...
[SUCCESS] 测试完成
结果保存在: /tmp/fio_results_20260319_103000

性能摘要:
seq_write: IOPS=1024, BW=1024MiB/s
seq_read: IOPS=2048, BW=2048MiB/s
...
```

**内存带宽测试**：

使用 STREAM 工具测试内存带宽。

```
请选择: 2
[INFO] 开始内存带宽测试...

STREAM version $Revision: 5.10 $
...
Function    Best Rate MB/s  Avg time     Min time     Max time
Copy:           45000.0     0.0152       0.0142       0.0165
Scale:          44800.0     0.0153       0.0143       0.0166
Add:            47000.0     0.0154       0.0145       0.0167
Triad:          46800.0     0.0155       0.0146       0.0168
```

**GPU 压力测试**：

使用 gpu-burn 对 NVIDIA GPU 进行压力测试。

```
请选择: 3
========== GPU 压力测试 ==========
请输入测试时间(秒，1小时=3600): 3600
请选择运行方式:
  1. 当前进程直接运行
  2. screen 后台运行
选择: 1
[INFO] 开始 GPU 压力测试...
...
```

**CPU 压力测试**：

使用 stress-ng 进行 CPU 压力测试。

```
请选择: 4
========== CPU 压力 测试 ==========
请输入测试时间(秒): 300
请选择测试方式:
  1. 快速测试 (多种算法, 每项10秒)
  2. 持续压力测试
  3. 自定义时间压力测试
选择: 1
[INFO] 开始快速测试...
测试算法: int8
...
测试算法: float
...
```

**综合测试**：

Python 实现的综合压力测试工具，支持同时测试 CPU、内存和 GPU。

```
请选择: 6
========== 综合压力测试 ==========

========================================
          Linux系统综合压力测试工具 v2.0
              CPU+内存+GPU全压力测试
========================================
[提示!!!]
本工具仅供技术测试使用，请遵守相关法律法规!
警告: 压力测试可能导致系统不稳定，请确保重要数据已备份!

请选择测试模式:
[1] 仅CPU压力测试 (100%全核满载)
[2] 仅内存压力测试 (90%容量占用)
[3] 仅GPU压力测试 (核心+显存双烤)
[4] 组合测试 (CPU+内存+GPU同时)
[5] 退出

请输入选项 (1-5): 4
请输入测试时长（分钟，默认5分钟）: 10

========================================
系统综合压力测试监控 | 剩余时间: 10分0秒
========================================

【CPU状态】
当前温度: CPU1:45.2°C(峰值:52.1°C) CPU2:47.8°C(峰值:54.3°C)
当前使用率: 100.0% (峰值: 100.0%)

【内存状态】
总容量: 512.0 GB | 已用: 468.5 GB
使用率: [██████████████████████████████████████████████████] 91.5% (峰值: 91.5%)

【GPU状态】
GPU   功耗(W)     温度(°C)    核心(%)     显存(%)    
------------------------------------------------------------
0     395.2       82          100         95.2      
      峰值: 398.5W  82°C  100%  95.2%

========================================
按 Ctrl+C 终止所有测试
正在监控: CPU(96核) | 内存(460.8GB) | GPU(1块)
```

---

### 磁盘检查

**功能描述**：RAID 和磁盘健康检查。

**使用路径**：主菜单 → 6. 磁盘检查

**功能列表**：

| 选项 | 功能 | 说明 |
|------|------|------|
| 1 | 检查 RAID 状态 | 查看 RAID 卡温度和磁盘状态 |
| 2 | 自动修复 RAID | 自动恢复异常磁盘状态 |
| 3 | SMART 检查 | 检查磁盘健康指标 |

**使用示例**：

```
请选择: 1
========== RAID 状态检查 ==========
控制器: 0
  状态: Optimal
  温度: 45°C

虚拟磁盘:
  VD 0: RAID5, Optimal, 10.9TB

物理磁盘:
  EID:Slt  State    Size       Model
  8:0      Onln     3.637 TB   ST4000NM0035-1V4
  8:1      Onln     3.637 TB   ST4000NM0035-1V4
  8:2      Onln     3.637 TB   ST4000NM0035-1V4
  8:3      Onln     3.637 TB   ST4000NM0035-1V4

[SUCCESS] RAID 状态正常
```

---

### 运行环境检测

**功能描述**：检查运行环境是否满足要求。

**使用路径**：主菜单 → 7. 运行环境检测

**检测内容**：

- 依赖命令检查（fio、ipmitool、stress-ng 等）
- Python 模块检查（GPUtil 等）
- 硬件检测（RAID、GPU、IPMI）
- 网络连接检查

**使用示例**：

```
请选择: 7
========== 运行环境检测 ==========

[依赖命令检查]
[PASS] fio: 已安装
[PASS] ipmitool: 已安装
[PASS] stress-ng: 已安装
[PASS] smartctl: 已安装
[WARN] arp-scan: 未安装

[Python 模块检查]
[PASS] GPUtil: 已安装
[INFO] Python 版本: 3.8.10

[硬件检测]
[PASS] RAID 控制器: 检测到 LSI MegaRAID
[PASS] GPU: 检测到 NVIDIA GPU
[PASS] IPMI: 设备可用

[网络检查]
[PASS] 外网连接: 正常

检测完成！
```

---

## 常见问题

### 1. 工具无法启动

**问题**：运行 `amax-tool` 时提示权限不足

**解决**：确保使用 root 用户或 sudo 运行

```bash
sudo /opt/amaxtool/bin/amax-tool
```

### 2. 某些功能无法使用

**问题**：部分菜单项显示错误或无法执行

**解决**：先运行"运行环境检测"检查依赖是否完整，然后安装缺失的依赖

```bash
sudo apt-get install -y fio ipmitool stress-ng arp-scan smartmontools
```

### 3. RAID 检测失败

**问题**：无法检测 RAID 卡或显示"未找到 storcli64"

**解决**：
1. 确认 storcli64 工具已放置在 `/opt/amaxtool/tools/` 目录
2. 确认 RAID 卡被系统识别：`lspci | grep -i lsi`

### 4. GPU 测试失败

**问题**：GPU 压力测试无法启动

**解决**：
1. 确认 NVIDIA 驱动已安装：`nvidia-smi`
2. 确认 gpu-burn 已编译：`cd /opt/amaxtool/modules/hwtest/benchmark/gpu-burn && make`

### 5. 日志收集失败

**问题**：日志收集时提示权限不足

**解决**：确保以 root 用户运行，并检查日志目录权限

```bash
sudo mkdir -p /var/log/amax-tool/logs
sudo chmod 755 /var/log/amax-tool
```

---

## 故障排查

### 查看工具日志

工具运行日志保存在：
```
/var/log/amax-tool/amax-tool.log
```

查看日志排查问题：
```bash
tail -f /var/log/amax-tool/amax-tool.log
```

### 手动执行模块

如果某个模块出现问题，可以手动执行对应的脚本来查看详细错误：

```bash
# 系统信息模块
sudo bash /opt/amaxtool/modules/sysinfo/run.sh

# 硬件测试模块
sudo bash /opt/amaxtool/modules/hwtest/run.sh

# 系统维护模块
sudo bash /opt/amaxtool/modules/system/run.sh
```

### 调试模式

在调试模式下运行可以查看更多输出信息：

```bash
# 添加 -x 参数启用调试
sudo bash -x /opt/amaxtool/bin/amax-tool
```

### 联系支持

如遇到无法解决的问题，请收集以下信息并联系支持：

1. 系统信息输出：`/opt/amaxtool/modules/sysinfo/run.sh`
2. 运行环境检测输出：`/opt/amaxtool/modules/check/run.sh`
3. 工具日志：`/var/log/amax-tool/amax-tool.log`
4. 系统日志：`dmesg | tail -100`

---

## 附录

### A. 目录结构说明

```
/opt/amaxtool/
├── bin/
│   └── amax-tool          # 主入口脚本
├── lib/                   # 公共库函数
│   ├── core.sh            # 核心函数（颜色输出、日志等）
│   ├── env.sh             # 环境配置
│   └── utils.sh           # 工具函数
├── modules/               # 功能模块
│   ├── check/             # 运行环境检测
│   ├── diskcheck/         # 磁盘检查
│   ├── getlog/            # 日志收集
│   ├── hwtest/            # 硬件测试
│   │   ├── benchmark/     # 性能测试工具
│   │   │   ├── all.py     # 综合压力测试
│   │   │   ├── cpu.sh     # CPU 压力测试
│   │   │   ├── gpu-burn/  # GPU 压力测试工具
│   │   │   └── stream/    # 内存带宽测试
│   │   └── run.sh
│   ├── soft/              # 软件安装
│   ├── sysinfo/           # 系统信息
│   └── system/            # 系统维护
│       ├── autocheck.sh   # 综合检测脚本
│       ├── rc/            # rc.local 配置模板
│       └── run.sh
├── tools/                 # 二进制工具
│   ├── ipmicfg
│   ├── storcli64
│   └── sum
├── Doc.md                 # 本说明文档
├── DOCUMENTATION.md       # 技术文档
├── OPTIMIZATION.md        # 优化指南
└── README.md              # 项目简介
```

### B. 环境变量

工具使用以下环境变量：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `AMAX_BASE_DIR` | 工具根目录 | `/opt/amaxtool` |
| `AMAX_LOG_DIR` | 日志输出目录 | `/var/log/amax-tool` |
| `AMAX_TOOLS_DIR` | 二进制工具目录 | `/opt/amaxtool/tools` |

### C. 配置文件

工具在运行时会读取/生成以下配置文件：

- `/etc/amax-tool/config` - 全局配置（如有需要可创建）
- `/var/log/amax-tool/amax-tool.log` - 运行日志
- `/tmp/fio_results_*` - FIO 测试结果
- `/tmp/stress_test_reports/` - 压力测试报告

### D. 更新日志

#### v2.0 (2025-03-04)

- 重构代码结构，统一库函数
- 添加完善的错误处理和日志记录
- 优化菜单交互体验
- 标准化代码风格
- 添加 README 和详细使用文档
- 新增综合测试功能（CPU+内存+GPU）
- 新增综合检测功能（硬件健康检查）

#### v1.0 (原始版本)

- 基础功能实现

---

**文档版本**: 2.0  
**最后更新**: 2026-03-19
