#!/bin/bash

# Create directory if it doesn't exist
RCA_ANALYSIS_DIR="rca_analysis" 
mkdir -p "$RCA_ANALYSIS_DIR"   

# --- Helper function to convert various date strings to epoch ---
_get_epoch() {
    local date_str="$1"
    # LC_TIME is set to C for date parsing by 'date'
    LC_ALL=C date -d "$date_str" +%s 2>/dev/null
}


# --- Function to filter /var/log/messages ---
filter_messages() {
    local messages_file="messages.txt"
    local output_file="$RCA_ANALYSIS_DIR/log-messages.out" 
    local start_time="$1"
    local end_time="$2"

    if [[ ! -f "$messages_file" ]]; then
        echo "Error: $messages_file not found!"
        return 1
    fi

    echo "Filtering /var/log/messages..."
    if [[ -n "$start_time" && -n "$end_time" ]]; then
        echo "Applying time filter: $start_time to $end_time"
        start_time_escaped="${start_time//\//\\/}"
        end_time_escaped="${end_time//\//\\/}"
        sed -n "/${start_time_escaped}/,/${end_time_escaped}/{/^#==/q;p}" "$messages_file" > "$output_file"
    elif [[ -n "$start_time" && -z "$end_time" ]]; then
        echo "Applying time filter: from $start_time"
        start_time_escaped="${start_time//\//\\/}"
        sed -n "/${start_time_escaped}/,/#==/{/^#==/q;p}" "$messages_file" > "$output_file"
    else
        sed -n '/\/var\/log\/messages/,/#==/{/^#==/q;p}' "$messages_file" > "$output_file"
    fi

    if [[ -s "$output_file" ]]; then
        echo "Filtered messages saved to $output_file"
    elif [[ -f "$output_file" ]]; then
        echo "No messages found for the specified criteria in $messages_file. Output file $output_file is empty."
    else
        echo "Failed to create $output_file."
    fi
}

# --- Function to filter specific boot log sections ---
_filter_single_boot_log() {
    local boot_file="$1"
    local search_pattern="$2" 
    local output_file="$3" 
    local description="$4"

    echo "Filtering $description from $boot_file..."
    # FIX: Properly escape the search pattern for sed and use quotes correctly
    search_pattern_escaped=$(echo "$search_pattern" | sed 's/\//\\\//g')
    sed -n "/# ${search_pattern_escaped}/,/#==/ p" "$boot_file" > "$output_file.tmp"

    if [[ -s "$output_file.tmp" ]]; then
        cp "$output_file.tmp" "$output_file" 
        rm "$output_file.tmp"
        echo "Filtered $description saved to $output_file"
    elif [[ -f "$output_file.tmp" ]]; then 
        echo "No logs found for $description in $boot_file using pattern '${search_pattern}'. Output file $output_file is empty."
        rm "$output_file.tmp" 
    else
        echo "Failed to create temporary file for $description. Check permissions or disk space."
    fi
}

filter_boot_logs() {
    local boot_file="boot.txt"
    local filter_type="$1" 

    if [[ ! -f "$boot_file" ]]; then
        echo "Error: $boot_file not found!"
        return 1
    fi

    local run_journal=false
    local run_log=false
    local run_dmesg=false

    case "$filter_type" in
        journal) run_journal=true ;;
        log) run_log=true ;;
        dmesg) run_dmesg=true ;;
        all)
            run_journal=true
            run_log=true
            run_dmesg=true
            ;;
        *)
            echo "Error: Invalid filter type '$filter_type' for -boot."
            echo "Valid types are: journal, log, dmesg, all."
            return 1
            ;;
    esac

    if $run_journal; then
        _filter_single_boot_log "$boot_file" "/usr/bin/journalctl --no-pager --boot 0" "$RCA_ANALYSIS_DIR/journalctl_no_pager.out" "journalctl --no-pager --boot 0"
    fi

    if $run_log; then
        _filter_single_boot_log "$boot_file" "/var/log/boot.log" "$RCA_ANALYSIS_DIR/var_log_boot.out" "/var/log/boot.log"
    fi

    if $run_dmesg; then
        _filter_single_boot_log "$boot_file" "/bin/dmesg -T" "$RCA_ANALYSIS_DIR/dmesg.out" "dmesg -T"
    fi
}

# --- Function to show server time and timezone ---
show_server_time() {
    local ntp_file="ntp.txt"
    local output_file="$RCA_ANALYSIS_DIR/server_time_info.txt"
    if [[ ! -f "$ntp_file" ]]; then
        echo "Error: $ntp_file not found!"
        return 1
    fi

    echo "Extracting server time and timezone information..."
    sed -n '/^# \/usr\/bin\/timedatectl/,/^#==/{p;}' "$ntp_file" | sed '$d' > "$output_file.tmp"
    if [[ -s "$output_file.tmp" ]]; then
        mv "$output_file.tmp" "$output_file"
        echo "Server time and timezone information (from timedatectl output):"
        cat "$output_file"
        echo "Full output saved to $output_file"
    else
        grep "timedatectl" "$ntp_file" -A8 > "$output_file"
        if [[ -s "$output_file" ]]; then
             echo "Server time and timezone information (using grep -A8 timedatectl):"
             cat "$output_file"
             echo "Full output saved to $output_file"
        else
            echo "Could not find 'timedatectl' output in $ntp_file."
            rm "$output_file.tmp" 2>/dev/null
        fi
    fi
}

# --- Function to find last reboot time ---
find_last_reboot() {
    local boot_file="boot.txt"
    local output_file="$RCA_ANALYSIS_DIR/last_reboot.out" 

    if [[ ! -f "$boot_file" ]]; then
        echo "Error: $boot_file not found!" > "$output_file"
        echo "Error: $boot_file not found!"
        return 1
    fi

    echo "Scanning for last reboot information..."

    local max_epoch=0
    local max_line=""
    local max_source=""

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

    if [[ "$max_epoch" -gt 0 ]]; then
        echo "Last reboot identified by '$max_source':" > "$output_file"
        echo "$max_line" >> "$output_file"
        echo "Timestamp (Epoch): $max_epoch" >> "$output_file"
        echo "" >> "$output_file"
        echo "Last reboot determined to be (from '$max_source'):"
        echo "$max_line"
        echo "(Epoch: $max_epoch, Date: $(LC_ALL=C date -d "@$max_epoch" +"%a %b %d %T %Y %Z"))"
    else
        echo "Could not reliably determine last reboot time from $boot_file." > "$output_file"
        echo "No reboot information found or parsed successfully."
    fi
    echo "Full details saved to $output_file"
}


# --- Main script logic ---
RUN_ALL=true
RUN_MESSAGES=false
BOOT_FILTER_TYPE="" 
RUN_TIME_INFO=false
RUN_REBOOT=false
START_DATE_TIME=""
END_DATE_TIME=""

if [[ $# -eq 0 ]]; then
    RUN_MESSAGES=true
    BOOT_FILTER_TYPE="all" 
    RUN_TIME_INFO=true
    RUN_REBOOT=true
else
    RUN_ALL=false
fi

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -messages)
        RUN_MESSAGES=true
        RUN_ALL=false
        shift 
        ;;
        -boot)
        RUN_ALL=false
        shift 
        if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then 
            case "$1" in
                log|dmesg|all|journal)
                    BOOT_FILTER_TYPE="$1"
                    shift 
                    ;;
                *) 
                    BOOT_FILTER_TYPE="journal" 
                    ;;
            esac
        else
            BOOT_FILTER_TYPE="journal" 
        fi
        ;;
        -timeinfo)
        RUN_TIME_INFO=true
        RUN_ALL=false
        shift 
        ;;
        -reboot)
        RUN_REBOOT=true
        RUN_ALL=false
        shift 
        ;;
        -from)
        if [[ -n "$2" ]]; then
            START_DATE_TIME="$2"
            shift 
            shift 
        else
            echo "Error: -from requires a value." >&2; exit 1
        fi
        ;;
        -to)
        if [[ -n "$2" ]]; then
            END_DATE_TIME="$2"
            shift 
            shift 
        else
            echo "Error: -to requires a value." >&2; exit 1
        fi
        ;;
        -h|--help)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  -messages             Filter /var/log/messages from messages.txt"
        echo "  -boot [type]          Filter boot related logs from boot.txt."
        echo "                        [type] can be: journal (default), log, dmesg, all."
        echo "  -timeinfo             Show server time and timezone from ntp.txt"
        echo "  -reboot               Scan boot.txt for the most recent reboot time."
        echo "  -from YYYY-MM-DDTHH:MM  Specify start date and time for messages filter"
        echo "  -to   YYYY-MM-DDTHH:MM  Specify end date and time for messages filter"
        echo "  -h, --help            Show this help message"
        echo "If no options are specified, all filters (-messages, -boot all, -timeinfo, -reboot) will be run."
        exit 0
        ;;
        *)    
        echo "Unknown option: $1"
        echo "Run '$0 --help' for usage."
        exit 1
        ;;
    esac
done

if $RUN_ALL || $RUN_MESSAGES; then
    if [[ -n "$START_DATE_TIME" && -z "$END_DATE_TIME" && ($RUN_MESSAGES || $RUN_ALL) ]]; then 
        echo "Warning: -from specified without -to for messages. Filtering from $START_DATE_TIME onwards."
    elif [[ -z "$START_DATE_TIME" && -n "$END_DATE_TIME" && ($RUN_MESSAGES || $RUN_ALL) ]]; then
        echo "Error: -to specified without -from for messages. Please specify both or neither."
        if ! $RUN_ALL ; then exit 1; fi 
    fi
    filter_messages "$START_DATE_TIME" "$END_DATE_TIME"
fi

if [[ -n "$BOOT_FILTER_TYPE" ]] || $RUN_ALL ; then 
    actual_boot_filter_type="$BOOT_FILTER_TYPE"
    if $RUN_ALL && [[ -z "$BOOT_FILTER_TYPE" ]]; then 
        actual_boot_filter_type="all"
    fi
    if [[ -n "$actual_boot_filter_type" ]]; then
      filter_boot_logs "$actual_boot_filter_type"
    fi
fi

if $RUN_ALL || $RUN_TIME_INFO; then
    show_server_time
fi

if $RUN_ALL || $RUN_REBOOT; then
    find_last_reboot
fi

echo "Log analysis script finished. Outputs are in the '$RCA_ANALYSIS_DIR' directory."