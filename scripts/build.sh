#!/bin/bash
# scripts/build.sh

# Wrapper for synthesis runs

CONFIG=${1:-unopt}

if [[ "$CONFIG" != "unopt" && "$CONFIG" != "opt" ]]; then
    echo "Usage: $0 <unopt|opt>"
    exit 1
fi

echo "=========================================="
echo "Building configuration: $CONFIG"
echo "=========================================="

vivado -mode batch -source scripts/synth_config.tcl -tclargs $CONFIG

if [ $? -eq 0 ]; then
    echo ""
    echo "Build complete. Reports in prj/$CONFIG/"
    echo "  - Timing: prj/$CONFIG/timing_summary_$CONFIG.rpt"
    echo "  - Utilization: prj/$CONFIG/utilization_$CONFIG.rpt"
else
    echo "Build FAILED - see Vivado logs"
    exit 1
fi
