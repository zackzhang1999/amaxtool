#!/bin/bash
#build smarttool
which smartctl
ST=`echo $?`

if [ ${ST} -eq 1 ]
then
	tar xf st.tar.gz
	cd smartmontools-7.3 && ./configure && make -j 2 && make install && cd ..
else
	echo "the smartctl is installed"
fi

sleep 2


echo ""
echo ""

echo "------------------------------------------------------------------"
echo "开始检测磁盘错误"
echo "------------------------------------------------------------------"

sleep 2

DISK=`smartctl --scan | awk '{print $3}'`
for i in `echo $DISK`
	do
	echo "---------------------------------------------------------"
	echo "The Disk id is $i"
	SN=`smartctl -s on -a -d $i /dev/sda | grep -i "Serial Number"`
	RT=`smartctl -s on -a -d $i /dev/sda | grep -i Reallocated_Sector_Ct | awk -F " " '{print $10}'`
	RU=`smartctl -s on -a -d $i /dev/sda | grep -i Reported_Uncorrect | awk -F " " '{print $10}'`
	CT=`smartctl -s on -a -d $i /dev/sda | grep -i Command_Timeout | awk -F " " '{print $10}'`
	CP=`smartctl -s on -a -d $i /dev/sda | grep -i Current_Pending_Sector | awk -F " " '{print $10}'`
	OU=`smartctl -s on -a -d $i /dev/sda | grep -i Offline_Uncorrectable | awk -F " " '{print $10}'`
	echo $SN
	echo "Reallocated_Sector_Ct is: $RT"
	echo "Reported_Uncorrect is: $RU"
	echo "Command_Timeout is: $CT"
        echo "Current_Pending_Sector is: $CP"
	echo "Offline_Uncorrectable is: $OU"
	echo ""
	sleep 2
done
