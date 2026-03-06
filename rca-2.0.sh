#!/bin/bash
# The main executable engine (CLI parsing, logging) rca.sh script 

# Core Configuration
export BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
export TARGET_DIR="." # Default to current directory
export RCA_ANALYSIS_DIR="rca_analysis"

# Source utilities
source "$BASE_DIR/lib/utils.sh"

# Parse global arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-d <supportconfig_path>] [module_options...]"
            echo "Options:"
            echo "  -d, --dir   Path to extracted supportconfig directory (default: current dir)"
            echo "  -all        Run all available modules"
            echo ""
            echo "Module specific options (e.g., -messages, -boot, -sysinfo) are handled by modules."
            exit 0
            ;;
        *)
            # Pass unknown arguments to modules later
            break
            ;;
    esac
done

export RCA_ANALYSIS_DIR="$TARGET_DIR/rca_analysis"
mkdir -p "$RCA_ANALYSIS_DIR"

echo -e "${YELLOW}Starting SLES Root Cause Analysis Tool...${NC}"
echo -e "Target Directory: $TARGET_DIR\n"

# Dynamically load and execute modules
MODULES_RUN=0
for module in "$BASE_DIR"/modules/*.sh; do
    if [[ -f "$module" ]]; then
        source "$module"
        func_name="run_$(basename "$module" .sh)"
        
        # Call the module function, passing all remaining arguments so the module can check for its flags
        if declare -f "$func_name" > /dev/null; then
            $func_name "$@"
            MODULES_RUN=$((MODULES_RUN + 1))
        fi
    fi
done

echo -e "\n${GREEN}Analysis complete. Modules executed: $MODULES_RUN${NC}"
echo -e "Full details saved in ${YELLOW}$RCA_ANALYSIS_DIR${NC}"
