kernel=`uname -a |awk {'print $3'}`

kernel="Advanced options for Ubuntu>Ubuntu, with Linux "$kernel
echo $kernel

sed -i "s/GRUB_DEFAULT=0/GRUB_DEFAULT=\"$kernel\""/g /etc/default/grub
cat /etc/default/grub
update-grub
