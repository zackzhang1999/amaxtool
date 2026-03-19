#!/bin/bash

# 确保以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行此脚本"
    exit 1
fi

# 检查是否安装lspci命令
if ! command -v lspci &> /dev/null; then
    echo "未找到lspci命令，请先安装pciutils包"
    exit 1
fi

# 检查是否安装ethtool命令(用于网卡设备)
if ! command -v ethtool &> /dev/null; then
    echo "未找到ethtool命令，网卡设备的详细信息可能无法显示"
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 恢复默认颜色

# 解析命令行参数
target_busid=""
show_help=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help=1
            shift
            ;;
        -b|--busid)
            if [[ -z "$2" ]]; then
                echo "错误：$1 选项需要一个参数" >&2
                exit 1
            fi
            target_busid="$2"
            shift 2
            ;;
        *)
            echo "错误：未知选项 $1" >&2
            exit 1
            ;;
    esac
done

# 显示帮助信息
if [[ $show_help -eq 1 ]]; then
    echo "PCI-E设备扫描工具"
    echo "用法: $0 [-h|--help] [-b|--busid BUSID]"
    echo "选项:"
    echo "  -h, --help        显示此帮助信息"
    echo "  -b, --busid BUSID 只显示指定BUSID的设备信息"
    exit 0
fi

echo -e "${BLUE}===== PCI-E设备扫描报告 ====${NC}"
echo -e "${BLUE}扫描时间: $(date)${NC}"
echo -e "${BLUE}系统信息: $(uname -a)${NC}"

if [[ -n "$target_busid" ]]; then
    echo -e "${BLUE}目标设备: $target_busid${NC}"
fi

echo -e "${BLUE}=================================${NC}\n"

# 获取所有PCI设备列表
pci_devices=$(lspci -D | awk '{print $1}')

# 初始化计数器
total_devices=0
pcie_devices=0
found_target=0

# 遍历所有PCI设备
for device in $pci_devices; do
    # 如果指定了目标BUSID且不匹配，则跳过
    if [[ -n "$target_busid" && "$device" != "$target_busid" ]]; then
        continue
    fi
    
    total_devices=$((total_devices + 1))
    
    # 检查设备是否为PCI-E设备
    if [ -f "/sys/bus/pci/devices/$device/device" ]; then
        pcie_devices=$((pcie_devices + 1))
        
        # 如果是指定的目标设备，标记已找到
        if [[ "$device" == "$target_busid" ]]; then
            found_target=1
        fi
        
        # 获取设备详细信息
        device_info=$(lspci -s $device -vmm)
        vendor=$(echo "$device_info" | grep "Vendor" | awk -F '\t' '{print $2}')
        device_name=$(echo "$device_info" | grep "Device" | awk -F '\t' '{print $2}')
        class=$(echo "$device_info" | grep "Class" | awk -F '\t' '{print $2}')
        
        # 获取PCI-E链接信息
        max_link_speed=$(cat /sys/bus/pci/devices/$device/max_link_speed 2>/dev/null || echo "Unknown")
        max_link_width=$(cat /sys/bus/pci/devices/$device/max_link_width 2>/dev/null || echo "Unknown")
        current_link_speed=$(cat /sys/bus/pci/devices/$device/current_link_speed 2>/dev/null || echo "Unknown")
        current_link_width=$(cat /sys/bus/pci/devices/$device/current_link_width 2>/dev/null || echo "Unknown")
        
        # 打印设备信息
        echo -e "${GREEN}设备: $device${NC}"
        echo -e "  厂商: $vendor"
        echo -e "  名称: $device_name"
        echo -e "  类别: $class"
        
        # 只在最大速率和最大通道数都不为Unknown时输出
        if [ "$max_link_speed" != "Unknown" ] && [ "$max_link_width" != "Unknown" ]; then
            echo -e "  PCI-E最大速率: $max_link_speed, 最大通道数: $max_link_width"
        fi
        
        # 判断当前速率是否达到最大
        if [ "$current_link_speed" != "Unknown" ] && [ "$current_link_width" != "Unknown" ]; then
            if [ "$current_link_speed" == "$max_link_speed" ] && [ "$current_link_width" == "$max_link_width" ]; then
                echo -e "  ${GREEN}PCI-E当前速率: $current_link_speed, 当前通道数: $current_link_width (已达到最大潜力)${NC}"
            else
                echo -e "  ${YELLOW}PCI-E当前速率: $current_link_speed, 当前通道数: $current_link_width (未达到最大潜力)${NC}"
            fi
        else
            echo -e "  ${YELLOW}PCI-E当前速率: $current_link_speed, 当前通道数: $current_link_width${NC}"
        fi
        
        # 特殊处理网卡设备，获取更详细的速率信息
        if [[ "$class" == *"Ethernet controller"* ]]; then
            # 获取网卡接口名称
            if_name=$(ls /sys/bus/pci/devices/$device/net/ 2>/dev/null | head -1)
            if [ -n "$if_name" ]; then
                echo -e "  网卡接口: $if_name"
                if command -v ethtool &> /dev/null; then
                    # 使用ethtool获取网卡协商速率
                    eth_speed=$(ethtool $if_name 2>/dev/null | grep "Speed" | awk '{print $2}')
                    if [ -n "$eth_speed" ]; then
                        echo -e "  网卡协商速率: $eth_speed"
                    fi
                fi
            fi
        fi
        
        echo "----------------------------------------"
    fi
done

# 如果指定了目标BUSID但未找到，输出提示
if [[ -n "$target_busid" && $found_target -eq 0 ]]; then
    echo -e "${RED}错误：未找到指定的BUSID: $target_busid${NC}"
fi

echo -e "\n${BLUE}扫描结果总结:${NC}"
if [[ -z "$target_busid" ]]; then
    echo -e "  总共发现 ${YELLOW}$total_devices${NC} 个PCI设备"
    echo -e "  其中 ${GREEN}$pcie_devices${NC} 个PCI-E设备"
else
    echo -e "  在PCI设备中查找: $target_busid"
    if [[ $found_target -eq 1 ]]; then
        echo -e "  ${GREEN}已找到并显示指定设备信息${NC}"
    else
        echo -e "  ${RED}未找到指定设备${NC}"
    fi
fi    
