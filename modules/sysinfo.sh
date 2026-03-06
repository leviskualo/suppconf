#!/bin/bash
# modules/sysinfo.sh

run_sysinfo() {
    local run_module=false

    if [[ " $* " =~ " -all " ]] || [[ " $* " =~ " -sysinfo " ]] || [[ $# -eq 0 ]]; then
        run_module=true
    fi

    if ! $run_module; then return 0; fi

    local basic_env="$TARGET_DIR/basic-environment.txt"
    local fs_disk="$TARGET_DIR/fs-disk.txt"
    local network="$TARGET_DIR/network.txt"
    local out_file="$RCA_ANALYSIS_DIR/system_overview.out"

    echo "--- System Overview ---" > "$out_file"

    show_progress "Extracting OS and Hardware Info..."
    if [[ -f "$basic_env" ]]; then
        echo -e "\n[ OS Release ]" >> "$out_file"
        sed -n '/^# \/bin\/cat \/etc\/os-release/,/^#==/p' "$basic_env" | grep -v "^#" >> "$out_file"
        log_success
    else
        log_fail "basic-environment.txt missing"
    fi

    show_progress "Extracting Disk Space (df -h)..."
    if [[ -f "$fs_disk" ]]; then
        echo -e "\n[ Disk Space Usage ]" >> "$out_file"
        # Efficiently grab df -h output using sed
        sed -n '/^# \/bin\/df -h/,/^#==/p' "$fs_disk" | head -n -1 | sed '1d' >> "$out_file"
        log_success
    else
        log_fail "fs-disk.txt missing"
    fi
    
    show_progress "Extracting IP Addresses..."
    if [[ -f "$network" ]]; then
        echo -e "\n[ IP Configuration ]" >> "$out_file"
        sed -n '/^# \/sbin\/ip -o addr show/,/^#==/p' "$network" | grep -v "^#" >> "$out_file"
        log_success
    else
        log_fail "network.txt missing"
    fi
}
