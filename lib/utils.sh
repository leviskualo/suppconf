#!/bin/bash

# Shared helper functions (colors, epoch conversion)
# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper function to convert various date strings to epoch
_get_epoch() {
    local date_str="$1"
    LC_ALL=C date -d "$date_str" +%s 2>/dev/null
}

# Progress indicator
show_progress() {
    local message="$1"
    printf "${CYAN}%s${NC}" "$message"
    for ((i=0; i<3; i++)); do
        sleep 0.2
        printf "."
    done
}

# Logging helpers
log_success() { echo -e " ${GREEN}Done${NC}"; }
log_fail() { echo -e " ${RED}Fail - $1${NC}"; }
