#!/bin/bash
# scripts/build.sh

# Wrapper for synthesis and implementation runs

CONFIG=${1:-unopt}
IMPL=${2:-false} # Optional second argument: "impl" to run place & route

if [[ "$CONFIG" != "unopt" && "$CONFIG" != "opt" ]]; then
    echo "Usage: $0 <unopt|opt> [impl]"
    echo "  unopt      - Build unoptimized configuration"
    echo "  opt        - Build optimized configuration"
    echo "  impl       - (optional) Run implementation after synthesis"
    echo ""
    echo "Examples:"
    echo "  $0 unopt           # Synthesis only"
    echo "  $0 unopt impl      # Synthesis + place & route"
    exit 1
fi

# Normalize second argument
if [[ "$IMPL" == "impl" ]]; then
    RUN_IMPL=true
else
    RUN_IMPL=false
fi

echo "=========================================="
echo "Building configuration: $CONFIG"
if [[ "$RUN_IMPL" == "true" ]]; then
    echo "Running: Synthesis + Implementation"
else
    echo "Running: Synthesis only"
fi
echo "=========================================="

vivado -mode batch -source scripts/synth_config.tcl -tclargs $CONFIG $RUN_IMPL

if [ $? -eq 0 ]; then
    echo ""
    echo "Build complete. Reports in prj/$CONFIG/"
    echo "  - Timing (post-synth): prj/$CONFIG/timing_summary_$CONFIG.rpt"
    echo "  - Utilization (post-synth): prj/$CONFIG/utilization_$CONFIG.rpt"

    if [[ "$RUN_IMPL" == "true" ]]; then
        echo "  - Timing (post-route): prj/$CONFIG/timing_postroute_$CONFIG.rpt"
        echo "  - Utilization (post-route): prj/$CONFIG/utilization_postroute_$CONFIG.rpt"
    fi
else
    echo "Build FAILED - see Vivado logs"
    exit 1
fi
