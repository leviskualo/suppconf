#!/bin/bash

# Configuration
RCA_ANALYSIS_DIR="rca_analysis"
CONFIG_FILE="suppconf.conf"

# Default log file names
MESSAGES_FILE_DEFAULT="messages.txt"
BOOT_FILE_DEFAULT="boot.txt"
NTP_FILE_DEFAULT="ntp.txt"
SYSTEMD_FILE_DEFAULT="systemd.txt"
CRON_FILE_DEFAULT="cron.txt"

MESSAGES_FILE="$MESSAGES_FILE_DEFAULT"
BOOT_FILE="$BOOT_FILE_DEFAULT"
NTP_FILE="$NTP_FILE_DEFAULT"
SYSTEMD_FILE="$SYSTEMD_FILE_DEFAULT"
CRON_FILE="$CRON_FILE_DEFAULT"

# Load configuration from file
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loading configuration from $CONFIG_FILE"
    while IFS='=' read -r key value; do
        case "$key" in
            MESSAGES_FILE|BOOT_FILE|NTP_FILE|SYSTEMD_FILE|CRON_FILE)
                # Remove potential surrounding quotes from value if any
                value="${value%"}"
                value="${value#"}"
                # Ensure value is not empty before overriding
                if [[ -n "$value" ]]; then
                    declare "$key=$value" # Use declare to set the variable
                    echo "  $key set to: $(eval echo \$$key)" # Confirm value
                else
                    echo "  Warning: Empty value for $key in $CONFIG_FILE. Using default."
                fi
                ;;
            ""|\#*) # Ignore empty lines and comments
                ;;
            *)
                echo "  Warning: Unknown key '$key' in $CONFIG_FILE. Ignoring."
                ;;
        esac
    done < "$CONFIG_FILE"
else
    echo "Warning: Configuration file '$CONFIG_FILE' not found. Using default file names."
fi

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create directory if it doesn't exist
mkdir -p "$RCA_ANALYSIS_DIR"

# --- Helper function to convert various date strings to epoch ---
_get_epoch() {
    local date_str="$1"
    LC_ALL=C date -d "$date_str" +%s 2>/dev/null
}

# --- Helper function to parse a valued command-line option ---
# usage: value=$(_parse_valued_option "option_name" "value_candidate")
#        if [[ \$? -ne 0 ]]; then exit 1; fi
# On success: echoes the value_candidate and returns 0.
# On failure: prints error to stderr, echoes nothing, and returns 1.
_parse_valued_option() {
    local option_name="$1"
    local value_candidate="$2"

    if [[ -n "$value_candidate" && ! "$value_candidate" =~ ^- ]]; then
        echo "$value_candidate"
        return 0
    else
        echo -e "${RED}Error: $option_name requires a value, or value is another option.${NC}" >&2
        # Echo nothing on failure so caller assigning to variable gets empty string if not checking exit code first
        return 1
    fi
}

# --- Function to show progress ---
show_progress() {
    local message="$1"
    printf "%s" "$message"
    for ((i=0; i<3; i++)); do
        sleep 0.5
        printf "."
    done
}

# --- Helper function to check file existence ---
# usage: check_file_exists "filepath" "description for error message"
# returns 0 if file exists, 1 otherwise
check_file_exists() {
    local filepath="$1"
    local description="$2"
    if [[ ! -f "$filepath" ]]; then
        echo -e "${RED}Error: File '$filepath' ($description) not found!${NC}"
        return 1
    fi
    return 0
}

# --- Helper function to execute a command and report status ---
# usage: execute_and_report "progress_message" "command_to_execute" "output_file" "status_if_empty (FAIL|YELLOW)"
# returns 0 on success (output file created), 1 on failure (command failed or output file not created)
execute_and_report() {
    local progress_message="$1"
    local command_string="$2"
    local output_file="$3"
    local empty_output_status="$4" # "FAIL" or "YELLOW"

    show_progress "$progress_message"

    # Execute the command. Using eval for flexibility, but ensure command_string is well-formed.
    # Consider security implications if command_string could come from untrusted sources (not an issue here).
    if eval "$command_string"; then
        if [[ -s "$output_file" ]]; then
            echo -e " ${GREEN}Done${NC}"
            return 0
        else
            if [[ "$empty_output_status" == "FAIL" ]]; then
                echo -e " ${RED}Fail (Output file $output_file is empty or not created)${NC}"
                return 1
            elif [[ "$empty_output_status" == "YELLOW" ]]; then
                echo -e " ${YELLOW}No relevant logs found or $output_file is empty.${NC}"
                # For YELLOW, an empty output file is not a script failure, so return 0.
                return 0
            else
                echo -e " ${RED}Error: Invalid empty_output_status '$empty_output_status' provided.${NC}"
                return 1
            fi
        fi
    else
        echo -e " ${RED}Fail (Command execution failed for: $command_string)${NC}"
        # Also remove potentially empty output file if command failed before creating it properly
        rm -f "$output_file"
        return 1
    fi
}

# --- Helper function for generic grep-based filtering ---
# usage: generic_grep_filter "input_file" "output_file" "grep_pattern" "progress_message_suffix" "empty_output_status" "input_file_description"
# returns 0 on success, 1 on failure
generic_grep_filter() {
    local input_file="$1"
    local output_file="$2"
    local grep_pattern="$3"
    local progress_message_suffix="$4" # e.g., "systemd logs"
    local empty_output_status="$5"     # "YELLOW" or "FAIL"
    local input_file_description="$6"  # e.g., "for systemd logs"

    check_file_exists "$input_file" "$input_file_description" || return 1

    local cmd="grep -E -i '$grep_pattern' '$input_file' > '$output_file'"

    execute_and_report "Filtering $progress_message_suffix from $input_file..." "$cmd" "$output_file" "$empty_output_status"
    return $? # Return the status of execute_and_report
}

# --- Helper function to get a new epoch if it's greater ---
# usage: new_epoch_val=$(_get_newer_epoch "date_string_to_parse" current_max_epoch)
_get_newer_epoch() {
    local date_str_to_parse="$1"
    local current_max_epoch="$2"
    local new_epoch

    new_epoch=$(_get_epoch "$date_str_to_parse")

    if [[ -n "$new_epoch" && "$new_epoch" -gt "$current_max_epoch" ]]; then
        echo "$new_epoch"
    else
        echo "$current_max_epoch"
    fi
}

# --- Function to filter /var/log/messages ---
filter_messages() {
    local output_file="$RCA_ANALYSIS_DIR/log-messages.out"
    local start_time="$1"
    local end_time="$2"

    check_file_exists "$MESSAGES_FILE" "for /var/log/messages" || return 1

    local cmd
    if [[ -n "$start_time" && -n "$end_time" ]]; then
        start_time_escaped="${start_time//\//\\/}"
        end_time_escaped="${end_time//\//\\/}"
        cmd="sed -n '/${start_time_escaped}/,/${end_time_escaped}/{/^#==/q;p}' '$MESSAGES_FILE' > '$output_file'"
    elif [[ -n "$start_time" && -z "$end_time" ]]; then
        start_time_escaped="${start_time//\//\\/}"
        cmd="sed -n '/${start_time_escaped}/,/#==/{/^#==/q;p}' '$MESSAGES_FILE' > '$output_file'"
    else
        cmd="sed -n '/\/var\/log\/messages/,/#==/{/^#==/q;p}' '$MESSAGES_FILE' > '$output_file'"
    fi
    execute_and_report "Filtering /var/log/messages..." "$cmd" "$output_file" "FAIL"
}

# --- Function to filter specific boot log sections ---
_filter_single_boot_log() {
    local boot_file="$1"
    local search_pattern="$2"
    local output_file="$3"
    local description="$4"

    search_pattern_escaped=$(echo "$search_pattern" | sed 's/\//\\\//g')
    local cmd="sed -n '/# ${search_pattern_escaped}/,/#==/ p' '$boot_file' > '$output_file.tmp'"
    if execute_and_report "Filtering $description from $boot_file..." "$cmd" "$output_file.tmp" "FAIL"; then
        cp "$output_file.tmp" "$output_file"
        rm "$output_file.tmp"
    else
        rm -f "$output_file.tmp" # Cleanup if execute_and_report indicated failure
        return 1 # Propagate failure
    fi
}

filter_boot_logs() {
    local filter_type="$1"

    check_file_exists "$BOOT_FILE" "for boot logs" || return 1

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
            echo -e "${RED}Error: Invalid filter type '$filter_type' for -boot.${NC}"
            echo "Valid types are: journal, log, dmesg, all."
            return 1
            ;;
    esac

    if $run_journal; then
        _filter_single_boot_log "$BOOT_FILE" "/usr/bin/journalctl --no-pager --boot 0" "$RCA_ANALYSIS_DIR/journalctl_no_pager.out" "journalctl --no-pager --boot 0"
    fi

    if $run_log; then
        _filter_single_boot_log "$BOOT_FILE" "/var/log/boot.log" "$RCA_ANALYSIS_DIR/var_log_boot.out" "/var/log/boot.log"
    fi

    if $run_dmesg; then
        _filter_single_boot_log "$BOOT_FILE" "/bin/dmesg -T" "$RCA_ANALYSIS_DIR/dmesg.out" "dmesg -T"
    fi
}

# --- Function to filter systemd logs ---
filter_systemd_logs() {
    local output_file="$RCA_ANALYSIS_DIR/systemd_analysis.out"
    local pattern='daemon|service|unit|failed|starting|stopping|activated|deactivated'
    generic_grep_filter "$SYSTEMD_FILE" "$output_file" "$pattern" "systemd logs" "YELLOW" "for systemd logs"
    return $?
}

# --- Function to filter cron logs ---
filter_cron_logs() {
    local output_file="$RCA_ANALYSIS_DIR/cron_analysis.out"
    local pattern='CROND|CMD|RUN|job|error|failed|executed'
    generic_grep_filter "$CRON_FILE" "$output_file" "$pattern" "cron logs" "YELLOW" "for cron logs"
    return $?
}

# --- Function to show server time and timezone ---
show_server_time() {
    local output_file="$RCA_ANALYSIS_DIR/server_time_info.txt"
    check_file_exists "$NTP_FILE" "for ntp/timedatectl data" || return 1

    echo "Server time and timezone information (from timedatectl output):"
    # Extract only the relevant lines from timedatectl output
    sed -n '/^# \/usr\/bin\/timedatectl/,/^#==/{/Local time:/p; /Universal time:/p; /RTC time:/p; /Time zone:/p; /System clock synchronized:/p; /NTP service:/p; /RTC in local TZ:/p}' "$NTP_FILE" | sed 's/^# \/usr\/bin\/timedatectl//; s/^#==//' > "$output_file.tmp"

    if [[ -s "$output_file.tmp" ]]; then
        mv "$output_file.tmp" "$output_file"
        cat "$output_file"
    else
        echo "Could not find 'timedatectl' output in $NTP_FILE."
        rm "$output_file.tmp" 2>/dev/null
    fi
}

# --- Function to find last reboot time ---
find_last_reboot() {
    local output_file="$RCA_ANALYSIS_DIR/last_reboot.out"

    if ! check_file_exists "$BOOT_FILE" "for boot information (for last reboot)"; then
        echo -e "${RED}Error: $BOOT_FILE not found!${NC}" > "$output_file" # Keep original behavior of writing to output_file
        return 1
    fi

    show_progress "Scanning for last reboot information..."
    local max_epoch=0
    local max_line=""
    local max_source=""
    local prev_max_epoch # To help check if max_epoch was updated by the helper

    local last_output_section
    last_output_section=$(sed -n '/^# \/usr\/bin\/last -wxF | egrep "reboot|shutdown|runlevel|system"/,/#==/p' "$BOOT_FILE")

    if [[ -n "$last_output_section" ]]; then
        echo "$last_output_section" | while IFS= read -r line; do
            if [[ "$line" =~ reboot[[:space:]]+system[[:space:]]+boot ]]; then
                local date_str_match
                date_str_match=$(echo "$line" | grep -oE '[A-Za-z]{3}[[:space:]]+[A-Za-z]{3}[[:space:]]+[0-9]{1,2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+[0-9]{4}')
                if [[ -n "$date_str_match" ]]; then
                    prev_max_epoch=$max_epoch
                    max_epoch=$(_get_newer_epoch "$date_str_match" "$max_epoch")
                    if [[ "$max_epoch" != "$prev_max_epoch" ]]; then
                        max_line="$line"
                        max_source="last -wxF output"
                    fi
                fi
            fi
        done
    fi

    local who_b_content
    who_b_content=$(sed -n -e '/^# \(\/usr\)\?\/bin\/who -b/{n;p;q}' "$BOOT_FILE")
    if [[ -n "$who_b_content" ]]; then
        local date_str_match
        date_str_match=$(echo "$who_b_content" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}(:[0-9]{2})?')
        if [[ -n "$date_str_match" ]]; then
            prev_max_epoch=$max_epoch
            max_epoch=$(_get_newer_epoch "$date_str_match" "$max_epoch")
            if [[ "$max_epoch" != "$prev_max_epoch" ]]; then
                max_line="$who_b_content"
                max_source="who -b output"
            fi
        fi
    fi

    local dmesg_first_log_line
    dmesg_first_log_line=$(sed -n '/^# \/bin\/dmesg -T/,/#==/{p;}' "$BOOT_FILE" | sed '1d;$d' | head -n 1)
    if [[ "$dmesg_first_log_line" =~ ^\[[[:space:]]*(.*)[[:space:]]*\] ]]; then
        local date_str_match="${BASH_REMATCH[1]}"
        date_str_match=$(echo "$date_str_match" | sed 's/^[ \t]*//;s/[ \t]*$//')

        prev_max_epoch=$max_epoch
        max_epoch=$(_get_newer_epoch "$date_str_match" "$max_epoch")
        if [[ "$max_epoch" != "$prev_max_epoch" ]]; then
            max_line="$dmesg_first_log_line"
            max_source="dmesg -T (first log line)"
        fi
    fi

    local journal_first_log_line
    journal_first_log_line=$(sed -n '/^# \/usr\/bin\/journalctl --no-pager --boot 0/,/#==/{p;}' "$BOOT_FILE" | sed '1d;$d' | head -n 1)
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
            prev_max_epoch=$max_epoch
            max_epoch=$(_get_newer_epoch "$date_str_match" "$max_epoch")
            if [[ "$max_epoch" != "$prev_max_epoch" ]]; then
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
        echo "Could not reliably determine last reboot time from $BOOT_FILE." > "$output_file"
        echo -e "${RED}No reboot information found or parsed successfully.${NC}"
    fi
}

# --- Main script logic ---
RUN_ALL=true
RUN_MESSAGES=false
BOOT_FILTER_TYPE=""
RUN_TIME_INFO=false
RUN_REBOOT=false
RUN_SYSTEMD=false
RUN_CRON=false
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
        -systemd)
        RUN_SYSTEMD=true
        RUN_ALL=false
        shift
        ;;
        -cron)
        RUN_CRON=true
        RUN_ALL=false
        shift
        ;;
        -from)
        START_DATE_TIME=$(_parse_valued_option "$key" "$2")
        if [[ $? -ne 0 ]]; then exit 1; fi
        shift # For -from
        shift # For its value
        ;;
        -to)
        END_DATE_TIME=$(_parse_valued_option "$key" "$2")
        if [[ $? -ne 0 ]]; then exit 1; fi
        shift # For -to
        shift # For its value
        ;;
        -h|--help)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  -messages             Filter /var/log/messages from messages.txt"
        echo "  -boot [type]          Filter boot related logs from boot.txt."
        echo "                        [type] can be: journal (default), log, dmesg, all."
        echo "  -timeinfo             Show server time and timezone from ntp.txt"
        echo "  -reboot               Scan boot.txt for the most recent reboot time."
        echo "  -systemd              Filter systemd logs from SYSTEMD_FILE (see suppconf.conf)"
        echo "  -cron                 Filter cron logs from CRON_FILE (see suppconf.conf)"
        echo "  -from YYYY-MM-DDTHH:MM  Specify start date and time for messages filter"
        echo "  -to   YYYY-MM-DDTHH:MM  Specify end date and time for messages filter"
        echo "  -h, --help            Show this help message"
        echo "If no options are specified, all filters (-messages, -boot all, -timeinfo, -reboot, -systemd, -cron) will be run."
        exit 0
        ;;
        *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Run '$0 --help' for usage."
        exit 1
        ;;
    esac
done

if $RUN_ALL || $RUN_MESSAGES; then
    if [[ -n "$START_DATE_TIME" && -z "$END_DATE_TIME" && ($RUN_MESSAGES || $RUN_ALL) ]]; then
        echo -e "${YELLOW}Warning: -from specified without -to for messages. Filtering from $START_DATE_TIME onwards.${NC}"
    elif [[ -z "$START_DATE_TIME" && -n "$END_DATE_TIME" && ($RUN_MESSAGES || $RUN_ALL) ]]; then
        echo -e "${RED}Error: -to specified without -from for messages. Please specify both or neither.${NC}"
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

if $RUN_ALL || $RUN_SYSTEMD; then
    filter_systemd_logs
fi

if $RUN_ALL || $RUN_CRON; then
    filter_cron_logs
fi

echo -e "\nFull details saved in ${YELLOW}./$RCA_ANALYSIS_DIR${NC}"