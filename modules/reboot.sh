#!/bin/bash

run_reboot() {
    local run_module=false
    
    # Check if we should run
    if [[ " $* " =~ " -all " ]] || [[ " $* " =~ " -reboot " ]] || [[ $# -eq 0 ]]; then
        run_module=true
    fi

    if ! $run_module; then return 0; fi

    local boot_file="$TARGET_DIR/boot.txt"
    local output_file="$RCA_ANALYSIS_DIR/last_reboot.out"

    if [[ ! -f "$boot_file" ]]; then
        show_progress "Scanning for last reboot info..."
        log_fail "boot.txt not found"
        return 1
    fi

    show_progress "Scanning for last reboot information..."
    local max_epoch=0
    local max_line=""
    local max_source=""

    # 1. Parse 'last -wxF'
    local last_output_section
    last_output_section=$(sed -n '/^# \/usr\/bin\/last -wxF | egrep "reboot|shutdown|runlevel|system"/,/#==/p' "$boot_file")

    if [[ -n "$last_output_section" ]]; then
        echo "$last_output_section" | while IFS= read -r line; do
            if [[ "$line" =~ reboot[[:space:]]+system[[:space:]]+boot ]]; then
                local date_str_match
                date_str_match=$(echo "$line" | grep -oE '[A-Za-z]{3}[[:space:]]+[A-Za-z]{3}[[:space:]]+[0-9]{1,2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+[0-9]{4}')
                if [[ -n "$date_str_match" ]]; then
                    local current_epoch
                    current_epoch=$(_get_epoch "$date_str_match")
                    if [[ -n "$current_epoch" && "$current_epoch" -gt "$max_epoch" ]]; then
                        max_epoch=$current_epoch
                        max_line="$line"
                        max_source="last -wxF output"
                    fi
                fi
            fi
        done
    fi

    # 2. Parse 'who -b'
    local who_b_content
    who_b_content=$(sed -n -e '/^# \(\/usr\)\?\/bin\/who -b/{n;p;q}' "$boot_file")
    if [[ -n "$who_b_content" ]]; then
        local date_str_match
        date_str_match=$(echo "$who_b_content" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}(:[0-9]{2})?')
        if [[ -n "$date_str_match" ]]; then
            local current_epoch
            current_epoch=$(_get_epoch "$date_str_match")
            if [[ -n "$current_epoch" && "$current_epoch" -gt "$max_epoch" ]]; then
                max_epoch=$current_epoch
                max_line="$who_b_content"
                max_source="who -b output"
            fi
        fi
    fi

    # 3. Parse 'dmesg -T'
    local dmesg_first_log_line
    dmesg_first_log_line=$(sed -n '/^# \/bin\/dmesg -T/,/#==/{p;}' "$boot_file" | sed '1d;$d' | head -n 1)
    if [[ "$dmesg_first_log_line" =~ ^\[[[:space:]]*(.*)[[:space:]]*\] ]]; then
        local date_str_match="${BASH_REMATCH[1]}"
        date_str_match=$(echo "$date_str_match" | sed 's/^[ \t]*//;s/[ \t]*$//')

        local current_epoch
        current_epoch=$(_get_epoch "$date_str_match")
        if [[ -n "$current_epoch" && "$current_epoch" -gt "$max_epoch" ]]; then
            max_epoch=$current_epoch
            max_line="$dmesg_first_log_line"
            max_source="dmesg -T (first log line)"
        fi
    fi

    # 4. Parse 'journalctl --boot 0'
    local journal_first_log_line
    journal_first_log_line=$(sed -n '/^# \/usr\/bin\/journalctl --no-pager --boot 0/,/#==/{p;}' "$boot_file" | sed '1d;$d' | head -n 1)
    if [[ -n "$journal_first_log_line" ]]; then
        local date_str_match
        date_str_match=$(echo "$journal_first_log_line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}:?[0-9]{2})?')
        if [[ -z "$date_str_match" ]]; then
            date_str_match=$(echo "$journal_first_log_line" | grep -oE '^[A-Za-z]{3}[[:space:]]+[0-9]{1,2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([[:space:]]+[0-9]{4})?' | head -n 1)
            if [[ -z "$date_str_match" ]]; then
                 date_str_match=$(echo "$journal_first_log_line" | grep -oE '^[A-Za-z]{3}[[:space:]]+[0-9]{1,2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -n 1)
            fi
        fi

        if [[ -n "$date_str_match" ]]; then
            local current_epoch
            current_epoch=$(_get_epoch "$date_str_match")
            if [[ -n "$current_epoch" && "$current_epoch" -gt "$max_epoch" ]]; then
                max_epoch=$current_epoch
                max_line="$journal_first_log_line"
                max_source="journalctl --boot 0 (first log line)"
            fi
        fi
    fi

    # Output results
    if [[ "$max_epoch" -gt 0 ]]; then
        echo "Last reboot identified by '$max_source':" > "$output_file"
        echo "$max_line" >> "$output_file"
        echo "Timestamp (Epoch): $max_epoch" >> "$output_file"
        echo "" >> "$output_file"
        echo "Last reboot determined to be (from '$max_source'):" >> "$output_file"
        echo "$max_line" >> "$output_file"
        echo "(Epoch: $max_epoch, Date: $(LC_ALL=C date -d "@$max_epoch" +"%a %b %d %T %Y %Z"))" >> "$output_file"
        log_success
    else
        echo "Could not reliably determine last reboot time from $boot_file." > "$output_file"
        log_fail "No parsable reboot info found"
    fi
}
