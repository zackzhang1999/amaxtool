#!/bin/bash
# 检查是否提供了正确的参数
if [ $# -ne 1 ]; then
    echo "用法: $0 <模式(ib/eth)>"
    exit 1
fi

MODE=$1

# 检查模式参数是否合法
if [ "$MODE" != "ib" ] && [ "$MODE" != "eth" ]; then
    echo "错误: 模式必须是 'ib' 或者 'eth'。"
    exit 1
fi

mst start

for MST in $(ls /dev/mst/*); do
    echo ${MST}
    # 根据模式切换
    if [ "$MODE" == "ib" ]; then
        sudo mlxconfig -y -d $MST set LINK_TYPE_P1=1 LINK_TYPE_P2=1
    elif [ "$MODE" == "eth" ]; then
        sudo mlxconfig -y -d $MST set LINK_TYPE_P1=2 LINK_TYPE_P2=2
    fi
done

