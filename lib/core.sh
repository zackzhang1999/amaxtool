#!/bin/bash
#===============================================================================
# AMAX Tool - Core Library
# Description: Common functions for color output, logging, and utilities
# Author: AMAX Team
# Version: 2.0
#===============================================================================

set -o pipefail

#-------------------------------------------------------------------------------
# Color Definitions
#-------------------------------------------------------------------------------
readonly COLOR_BLACK="0"
readonly COLOR_RED="1"
readonly COLOR_GREEN="2"
readonly COLOR_YELLOW="3"
readonly COLOR_BLUE="4"
readonly COLOR_MAGENTA="5"
readonly COLOR_CYAN="6"
readonly COLOR_WHITE="7"
readonly COLOR_RESET="\e[0m"

#-------------------------------------------------------------------------------
# Internal: Set color and print
#-------------------------------------------------------------------------------
_color_print() {
    local fg="3$1"
    local bg="4$2"
    shift 2
    printf "\033[%s;%sm%s\033[0m\n" "$fg" "$bg" "$*"
}

#-------------------------------------------------------------------------------
# Color Echo Functions
#-------------------------------------------------------------------------------
echo_black() { _color_print "$COLOR_BLACK" 9 "$*"; }
echo_red() { _color_print "$COLOR_RED" 9 "$*"; }
echo_green() { _color_print "$COLOR_GREEN" 9 "$*"; }
echo_yellow() { _color_print "$COLOR_YELLOW" 9 "$*"; }
echo_blue() { _color_print "$COLOR_BLUE" 9 "$*"; }
echo_magenta() { _color_print "$COLOR_MAGENTA" 9 "$*"; }
echo_cyan() { _color_print "$COLOR_CYAN" 9 "$*"; }
echo_white() { _color_print "$COLOR_WHITE" 9 "$*"; }

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------
readonly LOG_DIR="/var/log/amax-tool"
readonly LOG_FILE="$LOG_DIR/amax-tool.log"

log_init() {
    [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR" 2>/dev/null || {
        echo "Warning: Cannot create log directory $LOG_DIR" >&2
        return 1
    }
    touch "$LOG_FILE" 2>/dev/null || {
        echo "Warning: Cannot write to log file $LOG_FILE" >&2
        return 1
    }
}

log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    echo_red "$*" >&2
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    echo_yellow "$*" >&2
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null
    echo_green "$*"
}

#-------------------------------------------------------------------------------
# Check Functions
#-------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请以 root 用户运行此脚本"
        return 1
    fi
    return 0
}

check_command() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_internet() {
    ping -c 1 -W 3 8.8.8.8 &>/dev/null || \
    ping -c 1 -W 3 114.114.114.114 &>/dev/null
}

#-------------------------------------------------------------------------------
# UI Functions
#-------------------------------------------------------------------------------
print_header() {
    echo_cyan "=================================="
    echo_cyan "  $1"
    echo_cyan "=================================="
}

print_separator() {
    echo "----------------------------------------"
}

# 显示进度条
show_progress() {
    local duration=${1:-5}
    local message="${2:-Processing...}"
    local width=50
    
    echo -n "$message "
    for ((i = 0; i <= width; i++)); do
        local percent=$((i * 100 / width))
        printf "\r%s [%s%s] %d%%" "$message" \
            "$(printf '%*s' "$i" '' | tr ' ' '=')" \
            "$(printf '%*s' $((width - i)) '' | tr ' ' ' ')" \
            "$percent"
        sleep "$(echo "scale=3; $duration / $width" | bc 2>/dev/null || echo 0.1)"
    done
    echo
}

# 显示旋转等待动画
show_spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local delay=0.1
    local spinstr='|/-\'
    
    echo -n "$message "
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    wait "$pid"
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo "[OK]"
    else
        echo "[FAIL]"
    fi
    return $exit_code
}

#-------------------------------------------------------------------------------
# Menu Functions
#-------------------------------------------------------------------------------
show_menu() {
    local title="$1"
    shift
    
    print_header "$title"
    local i=1
    for item in "$@"; do
        echo "  $i. $item"
        ((i++))
    done
    echo "  q. 退出"
    print_separator
}

#-------------------------------------------------------------------------------
# Utility Functions
#-------------------------------------------------------------------------------
confirm() {
    local message="${1:-确认执行此操作?}"
    read -rp "$message [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

read_input() {
    local prompt="$1"
    local var_name="$2"
    local required="${3:-false}"
    
    while true; do
        read -rp "$prompt: " value
        if [[ -n "$value" ]]; then
            printf -v "$var_name" '%s' "$value"
            return 0
        elif [[ "$required" != "true" ]]; then
            printf -v "$var_name" '%s' ""
            return 0
        else
            echo_red "此项为必填项，请重新输入"
        fi
    done
}

# 获取脚本所在目录
get_script_dir() {
    local script_path="${BASH_SOURCE[0]}"
    while [[ -L "$script_path" ]]; do
        local dir=$(dirname "$script_path")
        script_path=$(readlink "$script_path")
        [[ "$script_path" == /* ]] || script_path="$dir/$script_path"
    done
    dirname "$(cd "$(dirname "$script_path")" && pwd)"
}

# 清理函数（在脚本退出时调用）
cleanup() {
    log_info "脚本执行结束"
}

trap cleanup EXIT

# 初始化日志
log_init
