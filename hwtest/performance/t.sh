#!/bin/bash

# 定义要执行的浮点运算次数
iterations=10000000

# 记录开始时间
start_time=$(date +%s%N)

# 执行浮点运算
for ((i = 0; i < iterations; i++)); do
	    result=$(echo "scale=10; $i * 3.14159 + 2.71828" | bc)
    done

    # 记录结束时间
    end_time=$(date +%s%N)

    # 计算执行时间（单位：纳秒）
    elapsed_time=$((end_time - start_time))

    # 将执行时间转换为秒
    elapsed_seconds=$(echo "scale=9; $elapsed_time / 1000000000" | bc)

    # 输出结果
    echo "执行 $iterations 次浮点运算花费的时间: $elapsed_seconds 秒"
