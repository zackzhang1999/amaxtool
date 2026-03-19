#!/bin/bash
#===============================================================================
# AMAX Tool - Environment Configuration
# Description: Global environment variables and settings
#===============================================================================

#-------------------------------------------------------------------------------
# Base Paths
#-------------------------------------------------------------------------------
readonly AMAX_BASE_DIR="/opt/amaxtool"
readonly AMAX_LIB_DIR="$AMAX_BASE_DIR/lib"
readonly AMAX_MODULES_DIR="$AMAX_BASE_DIR/modules"
readonly AMAX_TOOLS_DIR="$AMAX_BASE_DIR/tools"
readonly AMAX_LOG_DIR="/opt/amax-log"

#-------------------------------------------------------------------------------
# Tool Paths
#-------------------------------------------------------------------------------
readonly TOOL_IPMICFG="$AMAX_TOOLS_DIR/ipmicfg"
readonly TOOL_STORCLI64="$AMAX_TOOLS_DIR/storcli64"

#-------------------------------------------------------------------------------
# Hardware Detection
#-------------------------------------------------------------------------------
HW_RAID=$(lspci 2>/dev/null | grep -i lsi || true)
HW_NVIDIA=$(lspci 2>/dev/null | grep -i nvidia || true)

#-------------------------------------------------------------------------------
# System Information
#-------------------------------------------------------------------------------
get_server_sn() {
    dmidecode -t system 2>/dev/null | grep -i "Serial Number" | \
        awk -F ":" '{print $2}' | awk '{print $1}' | head -1
}

get_raid_sn() {
    if [[ -x "$TOOL_STORCLI64" ]]; then
        $TOOL_STORCLI64 /c0 show all 2>/dev/null | \
            grep -i "Serial Number" | awk -F "=" '{print $2}' | \
            awk '{print $1}' | head -1
    fi
}

#-------------------------------------------------------------------------------
# Time and Date
#-------------------------------------------------------------------------------
get_timestamp() {
    date +%Y_%m_%d_%H%M%S
}

get_date() {
    date +%Y_%m_%d
}

#-------------------------------------------------------------------------------
# Export variables
#-------------------------------------------------------------------------------
export AMAX_BASE_DIR AMAX_LIB_DIR AMAX_MODULES_DIR AMAX_TOOLS_DIR AMAX_LOG_DIR
export TOOL_IPMICFG TOOL_STORCLI64

# Server identifiers (lazy evaluation)
SERVERSN=""
RAIDSN=""
TIME=$(get_date)

# Initialize hardware info
init_hw_info() {
    SERVERSN=$(get_server_sn)
    RAIDSN=$(get_raid_sn)
    export SERVERSN RAIDSN TIME
}
