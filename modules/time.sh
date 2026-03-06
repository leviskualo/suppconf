#!/bin/bash

run_time() {
    local run_module=false

    if [[ " $* " =~ " -all " ]] || [[ " $* " =~ " -timeinfo " ]] || [[ $# -eq 0 ]]; then
        run_module=true
    fi

    if ! $run_module; then return 0; fi

    local ntp_file="$TARGET_DIR/ntp.txt"
    local output_file="$RCA_ANALYSIS_DIR/server_time_info.txt"

    if [[ ! -f "$ntp_file" ]]; then
        show_progress "Extracting time info..."
        log_fail "ntp.txt not found"
        return 1
    fi

    show_progress "Extracting timedatectl info..."
    
    sed -n '/^# \/usr\/bin\/timedatectl/,/^#==/{/Local time:/p; /Universal time:/p; /RTC time:/p; /Time zone:/p; /System clock synchronized:/p; /NTP service:/p; /RTC in local TZ:/p}' "$ntp_file" | sed 's/^# \/usr\/bin\/timedatectl//; s/^#==//' > "$output_file.tmp"

    if [[ -s "$output_file.tmp" ]]; then
        mv "$output_file.tmp" "$output_file"
        log_success
    else
        log_fail "Output empty"
        rm "$output_file.tmp" 2>/dev/null
    fi
}
