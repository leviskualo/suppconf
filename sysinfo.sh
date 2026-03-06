#!/bin/bash
# ==============================================================================
# SLES 15 Supportconfig RCA Analysis Tool
# ==============================================================================

# Ensure Bash 4+ for associative arrays
if (( BASH_VERSINFO[0] < 4 )); then
    echo -e "\033[0;31m[ERROR]\033[0m This script requires Bash version 4 or newer." >&2
    exit 1
fi

# --- Global Configuration & Colors ---
RCA_ANALYSIS_DIR="rca_analysis"

MESSAGES_FILE="messages.txt"
BOOT_FILE="boot.txt"
NTP_FILE="ntp.txt"
HARDWARE_FILE="hardware.txt"
NETWORK_FILE="network.txt"
BASIC_ENV_FILE="basic-environment.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

START_DATE_TIME=""
END_DATE_TIME=""

# --- Module Registry ---
declare -a REGISTERED_MODULES
declare -A RUN_MODULES
RUN_ALL=false

# --- Core Framework Functions ---

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_err()     { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Registers a module to the framework
register_module() {
    REGISTERED_MODULES+=("$1")
}

# Fast awk-based section extractor for supportconfig files
# Usage: extract_section <file> <command_string> <output_file>
extract_section() {
    local file="$1"
    local search_str="$2"
    local out="$3"

    if [[ ! -f "$file" ]]; then return 1; fi

    # AWK uses literal substr matching which is immune to regex escaping issues (e.g., paths, flags)
    awk -v str="# ${search_str}" '
        /^#==\[/ { if(in_section) exit }
        in_section { print }
        substr($0, 1, length(str)) == str { in_section=1 }
    ' "$file" > "$out"

    if [[ -s "$out" ]]; then return 0; else rm -f "$out"; return 1; fi
}

_get_epoch() {
    local date_str="$1"
    LC_ALL=C date -d "$date_str" +%s 2>/dev/null
}


# ==============================================================================
# RCA MODULES (Add new modules below this line)
# ==============================================================================

# --- MODULE: SYSINFO ---
register_module "sysinfo"
mod_sysinfo_desc="Extract basic OS release and Hardware info (CPU, Memory)"
mod_sysinfo_run() {
    log_info "Running module: sysinfo"
    extract_section "$BASIC_ENV_FILE" "/bin/cat /etc/os-release" "$RCA_ANALYSIS_DIR/os-release.out"
    extract_section "$HARDWARE_FILE" "/usr/bin/lscpu" "$RCA_ANALYSIS_DIR/lscpu.out"
    extract_section "$HARDWARE_FILE" "/usr/bin/free -m" "$RCA_ANALYSIS_DIR/free.out"
    log_success "System info extracted."
}

# --- MODULE: NETWORK ---
register_module "network"
mod_network_desc="Extract IP configurations and routing tables"
mod_network_run() {
    log_info "Running module: network"
    extract_section "$NETWORK_FILE" "/usr/sbin/ip -details -statistics addr" "$RCA_ANALYSIS_DIR/ip_addr.out"
    extract_section "$NETWORK_FILE" "/usr/sbin/ip -details -statistics route" "$RCA_ANALYSIS_DIR/ip_route.out"
    log_success "Network info extracted."
}

# --- MODULE: OOM ---
register_module "oom"
mod_oom_desc="Scan for Out-Of-Memory (OOM) killer events"
mod_oom_run() {
    log_info "Running module: oom"
    local out_file="$RCA_ANALYSIS_DIR/oom_events.out"
    if [[ -f "$MESSAGES_FILE" ]]; then
        if grep -iE "out of memory|killed process" "$MESSAGES_FILE" > "$out_file" 2>/dev/null; then
            log_warn "OOM events detected! Details saved to oom_events.out"
        else
            log_success "No OOM events found."
            rm -f "$out_file"
        fi
    else
        log_err "$MESSAGES_FILE not found for OOM scanning."
    fi
}

# --- MODULE: MESSAGES ---
register_module "messages"
mod_messages_desc="Extract and optionally time-filter /var/log/messages"
mod_messages_run() {
    log_info "Running module: messages"
    local tmp_out="$RCA_ANALYSIS_DIR/messages_full.tmp"
    local final_out="$RCA_ANALYSIS_DIR/log-messages.out"

    if ! extract_section "$MESSAGES_FILE" "/bin/cat /var/log/messages" "$tmp_out"; then
        cp "$MESSAGES_FILE" "$tmp_out" 2>/dev/null || { log_err "Could not find messages."; return; }
    fi

    if [[ -n "$START_DATE_TIME" && -n "$END_DATE_TIME" ]]; then
        sed -n "/${START_DATE_TIME//\//\\/}/,/${END_DATE_TIME//\//\\/}/p" "$tmp_out" > "$final_out"
    elif [[ -n "$START_DATE_TIME" ]]; then
        sed -n "/${START_DATE_TIME//\//\\/}/,\$p" "$tmp_out" > "$final_out"
    else
        mv "$tmp_out" "$final_out"
    fi
    rm -f "$tmp_out"
    
    [[ -s "$final_out" ]] && log_success "Messages successfully filtered." || log_err "Message filtering yielded empty results."
}

# --- MODULE: BOOT ---
register_module "boot"
mod_boot_desc="Extract journalctl, boot.log, and dmesg outputs"
mod_boot_run() {
    log_info "Running module: boot logs"
    extract_section "$BOOT_FILE" "/usr/bin/journalctl --no-pager --boot 0" "$RCA_ANALYSIS_DIR/journalctl_no_pager.out"
    extract_section "$BOOT_FILE" "/var/log/boot.log" "$RCA_ANALYSIS_DIR/var_log_boot.out"
    extract_section "$BOOT_FILE" "/bin/dmesg -T" "$RCA_ANALYSIS_DIR/dmesg.out"
    log_success "Boot logs extracted."
}

# --- MODULE: TIMEINFO ---
register_module "timeinfo"
mod_timeinfo_desc="Extract server time and timezone sync info"
mod_timeinfo_run() {
    log_info "Running module: timeinfo"
    local out="$RCA_ANALYSIS_DIR/server_time_info.txt"
    if extract_section "$NTP_FILE" "/usr/bin/timedatectl" "$out"; then
        log_success "Time info extracted. Current status:"
        grep -E "Local time|Universal time|Time zone|System clock synchronized|NTP service|RTC in local TZ" "$out" | \
            while read -r line; do echo -e "    $line"; done
    else
        log_err "Could not find timedatectl output in $NTP_FILE."
    fi
}

# --- MODULE: REBOOT ---
register_module "reboot"
mod_reboot_desc="Identify the exact last reboot time"
mod_reboot_run() {
    log_info "Running module: reboot"
    local out="$RCA_ANALYSIS_DIR/last_reboot.out"
    
    if [[ ! -f "$BOOT_FILE" ]]; then
        log_err "$BOOT_FILE not found!"
        return 1
    fi

    local max_epoch=0
    local max_line=""
    local max_source=""

    # 1. Check `last`
    local last_section; last_section=$(awk '/^# \/usr\/bin\/last -wxF/{flag=1; next} /^#==/{flag=0} flag' "$BOOT_FILE")
    echo "$last_section" | grep -E "reboot[[:space:]]+system[[:space:]]+boot" | while read -r line; do
        local date_str_match; date_str_match=$(echo "$line" | grep -oE '[A-Za-z]{3}[[:space:]]+[A-Za-z]{3}[[:space:]]+[0-9]{1,2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+[0-9]{4}')
        [[ -n "$date_str_match" ]] && echo "$(_get_epoch "$date_str_match")|$line|last -wxF" >> "${out}.tmp"
    done

    # 2. Check `who -b`
    local who_b; who_b=$(awk '/^# \/usr\/bin\/who -b/ {getline; print; exit}' "$BOOT_FILE")
    if [[ -n "$who_b" ]]; then
        local date_str; date_str=$(echo "$who_b" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}(:[0-9]{2})?')
        [[ -n "$date_str" ]] && echo "$(_get_epoch "$date_str")|$who_b|who -b" >> "${out}.tmp"
    fi

    # Read collected potential dates and find highest
    if [[ -f "${out}.tmp" ]]; then
        while IFS='|' read -r ep line src; do
            if [[ -n "$ep" && "$ep" -gt "$max_epoch" ]]; then
                max_epoch="$ep"; max_line="$line"; max_source="$src"
            fi
        done < "${out}.tmp"
        rm -f "${out}.tmp"
    fi

    if [[ "$max_epoch" -gt 0 ]]; then
        log_success "Last reboot found via '$max_source' at $(LC_ALL=C date -d "@$max_epoch" +"%a %b %d %T %Y %Z")"
        {
            echo "Last reboot determined to be (from '$max_source'):"
            echo "$max_line"
            echo "(Epoch: $max_epoch, Date: $(LC_ALL=C date -d "@$max_epoch" +"%a %b %d %T %Y %Z"))"
        } > "$out"
    else
        log_warn "Could not reliably determine last reboot time."
    fi
}


# ==============================================================================
# MAIN SCRIPT LOGIC
# ==============================================================================

print_help() {
    echo -e "${YELLOW}Usage: $0 [options]${NC}\n"
    echo "Core Options:"
    echo "  --all                  Run all available RCA modules"
    echo "  -from YYYY-MM-DD HH:MM Specify start date/time for log filters"
    echo "  -to   YYYY-MM-DD HH:MM Specify end date/time for log filters"
    echo "  -h, --help             Show this help message"
    echo -e "\nAvailable Modules:"
    for mod in "${REGISTERED_MODULES[@]}"; do
        local desc_var="mod_${mod}_desc"
        printf "  --%-20s %s\n" "$mod" "${!desc_var}"
    done
    echo -e "\nExample: $0 --sysinfo --oom --messages -from 'Mar  6 08:00'"
}

# Parse Arguments
if [[ $# -eq 0 ]]; then
    RUN_ALL=true
fi

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --all) RUN_ALL=true; shift ;;
        -from) START_DATE_TIME="$2"; shift 2 ;;
        -to)   END_DATE_TIME="$2"; shift 2 ;;
        -h|--help) print_help; exit 0 ;;
        --*)
            mod_name="${key#--}"
            found=false
            for mod in "${REGISTERED_MODULES[@]}"; do
                if [[ "$mod" == "$mod_name" ]]; then
                    RUN_MODULES["$mod"]=true
                    found=true
                    break
                fi
            done
            if ! $found; then
                log_err "Unknown module: $key"
                exit 1
            fi
            shift
            ;;
        *)
            # Backward compatibility check for single dash args
            if [[ "$key" == "-messages" || "$key" == "-boot" || "$key" == "-timeinfo" || "$key" == "-reboot" ]]; then
                RUN_MODULES["${key#-}"]=true
                shift
                # Ignore specific boot types from old script (we now grab all automatically)
                if [[ "$1" == "journal" || "$1" == "log" || "$1" == "dmesg" || "$1" == "all" ]]; then shift; fi
            else
                log_err "Unknown argument: $key"
                print_help
                exit 1
            fi
            ;;
    esac
done

# Execute initialization
mkdir -p "$RCA_ANALYSIS_DIR"
echo -e "\n${CYAN}Starting RCA Processing on $(date)...${NC}\n"

# Execute requested modules
for mod in "${REGISTERED_MODULES[@]}"; do
    if [[ "${RUN_MODULES[$mod]}" == "true" ]] || [[ "$RUN_ALL" == "true" ]]; then
        "mod_${mod}_run"
    fi
done

echo -e "\n${GREEN}Completed! Full details saved in ./${RCA_ANALYSIS_DIR}${NC}\n"