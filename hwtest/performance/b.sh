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

# 定义多种 stress-ng 算法，这里列举了几种常见的
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

	    # 执行 stress-ng 命令
	    echo "开始压力测试..."
	    eval $stress_command
	    echo "压力测试结束。"
