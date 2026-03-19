#!/bin/bash

# 提示用户输入测试时间
read -p "请输入压力测试的时间（单位：秒）: " test_time

# 检查输入是否为有效的整数
if ! [[ $test_time =~ ^[0-9]+$ ]]; then
    echo "输入无效，请输入一个有效的整数作为测试时间。"
    exit 1
fi

# 获取 CPU 核心数
cpu_cores=$(nproc)

# 定义多种 stress-ng 算法，使用通用的算法选项
algorithms=(
    "cpu"
)

# 构建 stress-ng 命令
stress_command="stress-ng"
for algo in "${algorithms[@]}"; do
    stress_command="$stress_command --$algo $cpu_cores"
done
stress_command="$stress_command --timeout $test_time"

# 输出即将执行的命令
echo "即将执行的命令: $stress_command"

# 询问用户是否确认执行
read -p "是否确认开始压力测试？(y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "测试已取消。"
    exit 0
fi

# 提示用户选择运行方式
read -p "请选择运行方式：(1) 当前进程直接运行；(2) 调用 screen 在后台执行: " run_choice

case $run_choice in
    1)
        echo "开始压力测试..."
        eval $stress_command
        echo "压力测试结束。"
        ;;
    2)
        if ! command -v screen &> /dev/null; then
            echo "screen 未安装，请先安装 screen 再选择此运行方式。"
            exit 1
        fi
        screen -dmS stress_test $stress_command
        echo "压力测试已在 screen 会话 'stress_test' 中后台启动。"
        echo "你可以使用 'screen -r stress_test' 恢复会话查看测试情况。"
        ;;
    *)
        echo "无效的选择，请输入 1 或 2。"
        exit 1
        ;;
esac
