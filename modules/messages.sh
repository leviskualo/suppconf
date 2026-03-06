#!/bin/bash

run_messages() {
    local run_module=false
    local start_time=""
    local end_time=""

    if [[ " $* " =~ " -all " ]] || [[ $# -eq 0 ]]; then
        run_module=true
    fi

    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[$i]}" == "-messages" ]]; then run_module=true; fi
        if [[ "${args[$i]}" == "-from" ]]; then start_time="${args[$i+1]}"; run_module=true; fi
        if [[ "${args[$i]}" == "-to" ]]; then end_time="${args[$i+1]}"; run_module=true; fi
    done

    if ! $run_module; then return 0; fi

    local messages_file="$TARGET_DIR/messages.txt"
    local output_file="$RCA_ANALYSIS_DIR/log-messages.out"

    if [[ ! -f "$messages_file" ]]; then
        show_progress "Filtering /var/log/messages..."
        log_fail "messages.txt not found"
        return 1
    fi

    show_progress "Filtering /var/log/messages..."
    
    if [[ -n "$start_time" && -n "$end_time" ]]; then
        local start_time_escaped="${start_time//\//\\/}"
        local end_time_escaped="${end_time//\//\\/}"
        sed -n "/${start_time_escaped}/,/${end_time_escaped}/{/^#==/q;p}" "$messages_file" > "$output_file"
    elif [[ -n "$start_time" && -z "$end_time" ]]; then
        local start_time_escaped="${start_time//\//\\/}"
        sed -n "/${start_time_escaped}/,/#==/{/^#==/q;p}" "$messages_file" > "$output_file"
    else
        sed -n '/\/var\/log\/messages/,/#==/{/^#==/q;p}' "$messages_file" > "$output_file"
    fi

    if [[ -s "$output_file" ]]; then
        log_success
    else
        log_fail "No matching logs found"
        rm -f "$output_file"
    fi
}
