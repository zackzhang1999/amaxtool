#!/bin/bash

# 运行 arp-scan -l 命令并将结果存储在变量中
arp_scan_result=$(arp-scan -l)

# 检查 arp-scan 命令是否成功运行
if [ $? -ne 0 ]; then
    echo "arp-scan 命令运行失败，请检查权限或网络连接。"
    exit 1
fi

# 使用 awk 提取 IP 地址和 MAC 地址
ip_mac_pairs=$(echo "$arp_scan_result" | awk '/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s+([0-9A-Fa-f:]+)/{print $1 " " $2}')

# 使用关联数组存储 IP 地址和 MAC 地址的映射
declare -A ip_mac_map

# 冲突标志，初始化为 false
conflict_detected=false

# 遍历 IP-MAC 对
while read -r ip mac; do
    if [ -n "$ip" ] && [ -n "$mac" ]; then
        if [ -n "${ip_mac_map[$ip]}" ] && [ "${ip_mac_map[$ip]}"!= "$mac" ]; then
            echo "IP 地址冲突：$ip 被多个 MAC 地址使用：${ip_mac_map[$ip]} 和 $mac"
            conflict_detected=true
        else
            ip_mac_map["$ip"]="$mac"
        fi
    fi
done <<< "$ip_mac_pairs"

# 检查是否存在冲突
if [ "$conflict_detected" = false ]; then
    echo "不冲突"
fi
