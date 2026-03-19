#!/bin/bash

# 提示用户输入磁盘盘符
read -p "请输入要测试的目录（例如 /data1）: " disk

# 检查输入的磁盘是否存在
if [ ! -d "$disk" ]; then
	    echo "错误：输入的磁盘 $disk 不存在。"
	        exit 1
fi

# 定义测试文件路径，这里在根目录下创建一个临时测试文件
test_file="$disk/test_file_fio"

# 顺序写测试
echo "开始顺序写测试..."
fio --name=seq_write_test --ioengine=libaio --rw=write --bs=1M --size=10G --numjobs=8 --runtime=60 --time_based --group_reporting --filename=$test_file --direct=1 --iodepth=64 --output=/tmp/seq_write_result.txt

# 顺序读测试
echo "开始顺序读测试..."
fio --name=seq_read_test --ioengine=libaio --rw=read --bs=1M --size=10G --numjobs=8 --runtime=60 --time_based --group_reporting --filename=$test_file --direct=1 --iodepth=64 --output=/tmp/seq_read_result.txt

# 随机写测试
echo "开始随机写测试..."
fio --name=rand_write_test --ioengine=libaio --rw=randwrite --bs=4k --size=10G --numjobs=8 --runtime=60 --time_based --group_reporting --filename=$test_file --direct=1 --iodepth=64 --output=/tmp/rand_write_result.txt

# 随机读测试
#echo "开始随机读测试..."
fio --name=rand_read_test --ioengine=libaio --rw=randread --bs=4k --size=10G --numjobs=8 --runtime=60 --time_based --group_reporting --filename=$test_file --direct=1 --iodepth=64 --output=/tmp/rand_read_result.txt

# 删除测试文件
rm -f $test_file

echo "测试完成，结果已保存到/tmp下的 seq_write_result.txt, seq_read_result.txt, rand_write_result.txt, rand_read_result.txt 文件中。"
