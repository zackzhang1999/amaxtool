#!/bin/bash
mst start
for MST in $(ls /dev/mst/* | egrep -v '\.1'); do
    echo ${MST}
    mlxconfig -d ${MST} -y set EXP_ROM_UEFI_x86_ENABLE=1
    mlxconfig -d ${MST} -y set EXP_ROM_PXE_ENABLE=1
    mlxconfig -d ${MST} q | egrep "EXP_ROM"
done

