#!/bin/bash
. ../env.sh
#SERVERSN=`ipmitool fru list | grep -i "Product Serial" | awk -F ":" '{print $2}' | awk -F " " '{print $1}'`
./run.sh > $SERVERSN.txt
echo "文件已保存为 $SERVERSN.txt"
