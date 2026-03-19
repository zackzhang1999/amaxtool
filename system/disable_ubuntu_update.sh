#!/bin/bash

loading ()
{
arr=("|" "/" "-" "\\")
i=0
var=0
ret=""
tmp=""
while [ $i -le 100 ]
do
	printf "\r[%-100s[%s%%]][%s]" ${tmp} ${var} ${arr[(($i%4))]}
	ret=${ret}=
	tmp=${ret}
	let i++
	let var++
	sleep 0.1
done
printf "\n"
echo ""
}


loading2 ()
{
arr=("|" "/" "-" "\\")
i=0
var=0
ret=""
tmp=""
while [ $i -le 100 ]
do
        printf "\r[%-100s[%s%%]][%s]" ${tmp} ${var} ${arr[(($i%4))]}
        ret=${ret}=
        tmp=${ret}
        let i++
        let var++
        sleep 0.01
done
printf "\n"
echo ""
}


systemctl disable apt-daily-upgrade.timer
systemctl stop apt-daily-upgrade.timer
systemctl disable apt-daily-upgrade.service
systemctl stop apt-daily-upgrade.service
systemctl disable apt-daily.timer
systemctl stop apt-daily.timer
systemctl disable apt-daily.service
systemctl stop apt-daily.service
[[ -f /etc/apt/apt.conf.d/10periodic ]] && \
    cat <<EOF > /etc/apt/apt.conf.d/10periodic
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "1";
EOF
[[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] && \
    cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "正在关闭系统自动更新"
loading

echo "正在生成报告"
echo "apt-daily-upgrade.timer server" >> /opt/disable.log
systemctl status apt-daily-upgrade.timer | grep Active >> /opt/disable.log
echo "apt-daily-upgrade.service server" >> /opt/disable.log
systemctl status apt-daily-upgrade.service | grep Active >> /opt/disable.log
echo "apt-daily.timer server" >> /opt/disable.log
systemctl status apt-daily.timer | grep Active >> /opt/disable.log
echo "apt-daily.service server" >>  /opt/disable.log 
systemctl status apt-daily.service | grep Active >> /opt/disable.log
loading2

echo "报告生成在 /opt/disable.log"
echo "文件内容如下:"
cat /opt/disable.log
