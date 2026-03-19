#!/bin/bash

. col.sh

TEMP=`tools/storcli64 /c0 show all | grep -i "ROC temperature(Degree Celsius)" | awk -F "=" '{print $2}' |  awk -F " " '{print $1}'`

LOADING ()
{
process() {
    pid=$1
    i=0
    while kill -0 $pid 2>/dev/null
    do
        i=$(((i+1) % 4))
        printf "."
        sleep 1
    done
}

cmd_with_process() {
    $1 &
    pid=$!
    process $pid &
    wait $pid
    if [ $? -eq 0 ]; then
        echo_green "[ok]"
    else
        echo_red "[fail]"
    fi
}

case $1 in
    check_cmd)
        shift
        cmd_with_process "$*"
    ;;
    *)
        echo_blue "AMAX 磁盘阵列修复系统"
        echo_yellow "正在检查"
        cmd_with_process "sleep 5"
    ;;
esac
}



DISKCHECK ()
{
LOADING
echo "以下为阵列中磁盘运行状态:"
echo "-------------------------------------------"
for i in `seq 0 7`
do
	DISKSTAT=`storcli64 /c0/eall/s$i show | grep -i 252 | awk '{print $3}'`
	if [[ $DISKSTAT != "Onln" ]]
	then
		echo_red "The disk$i status is $DISKSTAT"
	else
		echo_green "The disk$i status is $DISKSTAT"
	fi
done
}


SETGOOD ()
{
echo "开始检查并修复:"
echo "-------------------------------------------"
	for l in `seq 0 4`
do
	DISKSTAT=`storcli64 /c0/eall/s$l show | grep -i 252 | awk '{print $3}'`
	if [[ $DISKSTAT != "Onln"  ]]
	then
		echo_red  "The disk$l status is $DISKSTAT"
		echo_cyan "重新设定磁盘状态"
		sleep 3
		storcli64 /c0/eall/s$l set good >/dev/null 2>&1
		storcli64 /c0/eall/s$l set online >/dev/null 2>&1

	else
		echo_green "The disk$l status is $DISKSTAT"
	fi
done
storcli64 /c0/fall import >/dev/null 2>&1
storcli64 /c0  set   alarm=silence  >/dev/null 2>&1
sleep 2
}

ALLCHECK ()
{
	echo "sda状态"
	lsblk | grep -i sda
	sleep 2
	echo ""
	echo "raid阵列状态"
	storcli64 /c0/v0 show | sed -n '11,15p'
	sleep 2
	echo ""
	storcli64 /c0 show alilog | sed -n '64,172p'
}


DISKCHECK
echo ""
echo ""

SETGOOD
echo ""
echo "再次检查磁盘状态"
echo "-------------------------------------------"

DISKCHECK
echo "-------------------------------------------"
echo ""

ALLCHECK

echo_red Raid卡温度目前为$TEMP,若超过90度,请注意加强散热


