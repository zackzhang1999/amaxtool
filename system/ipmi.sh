#!/bin/bash
read -p  "Please input ip address:" IP
read -p  "Please input netmask:" NETMASK
read -p  "Please input gw address:" GW
read -p  "please input username:" USRE
read -p  "please input password:" PASS

ipmitool lan set 1 ipsrc static
ipmitool lan set 1 ipaddr $IP
ipmitool lan set 1 netmask $NETMASK
ipmitool lan set 1 defgw ipaddr $GW

USER=$USER
PASS=$PASS
CHANNEL=1
USERID=6
ipmitool user set name $USERID $USER
ipmitool user set password $USERID $PASS
ipmitool user priv $USERID 4 $CHANNEL
ipmitool channel  setaccess $CHANNEL $USERID callin=on ipmi=on link=on privilege=4
ipmitool sol payload enable $CHANNEL $USERID
ipmitool user enable $USERID
echo "ipmi user list"
ipmitool user list $CHANNEL

