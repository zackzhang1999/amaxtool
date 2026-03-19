#!/bin/bash

# 使用nproc命令获取CPU核心数
cpu_cores=$(nproc)


for m in int8 int16 int32 int64 crc16 float longdouble 
do 
    echo "start test $m performance"	
    stress-ng --cpu $cpu_cores  --cpu-method $m -t 10s --metrics-brief
    echo "-------------------------------------------------------------------------------------------------------------------"
done
