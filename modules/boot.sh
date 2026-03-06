#!/bin/bash
# modules/boot.sh

_filter_single_boot_log() {
    local boot_file="$1"
    local search_pattern="$2"
    local output_file="$3"
    local description="$4"

    show_progress "Filtering $description..."
    local search_pattern_escaped=$(echo "$search_pattern" | sed 's/\//\\\//g')
    sed -n "/# ${search_pattern_escaped}/,/#==/ p" "$boot_file" > "$output_file.tmp"

    if [[ -s "$output_file.tmp" ]]; then
        cp "$output_file.tmp" "$output_file"
        rm "$output_file.tmp"
        log_success
    else
        log_fail "No data found"
        rm "$output_file.tmp" 2>/dev/null
    fi
}

run_boot() {
    local run_module=false
    local filter_type=""

    if [[ " $* " =~ " -all " ]] || [[ $# -eq 0 ]]; then
        run_module=true
        filter_type="all"
    fi

    # Parse arguments for -boot [type]
    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[$i]}" == "-boot" ]]; then
            run_module=true
            local next_idx=$((i+1))
            if [[ $next_idx -lt ${#args[@]} && ! "${args[$next_idx]}" =~ ^- ]]; then
                filter_type="${args[$next_idx]}"
            else
                filter_type="journal" # Default
            fi
        fi
    done

    if ! $run_module; then return 0; fi

    local boot_file="$TARGET_DIR/boot.txt"
    if [[ ! -f "$boot_file" ]]; then
        show_progress "Checking boot logs..."
        log_fail "boot.txt not found"
        return 1
    fi

    local run_journal=false
    local run_log=false
    local run_dmesg=false

    case "$filter_type" in
        journal) run_journal=true ;;
        log) run_log=true ;;
        dmesg) run_dmesg=true ;;
        all) run_journal=true; run_log=true; run_dmesg=true ;;
        *) 
            echo -e "\n${RED}Error: Invalid filter type '$filter_type' for -boot.${NC}"
            return 1 
            ;;
    esac

    if $run_journal; then
        _filter_single_boot_log "$boot_file" "/usr/bin/journalctl --no-pager --boot 0" "$RCA_ANALYSIS_DIR/journalctl_no_pager.out" "journalctl --boot 0"
    fi
    if $run_log; then
        _filter_single_boot_log "$boot_file" "/var/log/boot.log" "$RCA_ANALYSIS_DIR/var_log_boot.out" "/var/log/boot.log"
    fi
    if $run_dmesg; then
        _filter_single_boot_log "$boot_file" "/bin/dmesg -T" "$RCA_ANALYSIS_DIR/dmesg.out" "dmesg -T"
    fi
}
