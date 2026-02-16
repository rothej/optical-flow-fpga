#!/bin/bash
# scripts/run_sim.sh

TB_NAME=${1:-tb_optical_flow_top}
WAVES=${2:-0}
RUN_TIME=${3:-100ms}

echo "=========================================="
echo "Running simulation: $TB_NAME"
echo "=========================================="

# Generate test frames
echo "Generating test frames..."
python python/generate_test_frames_natural.py --displacement-x 2

if [ $? -ne 0 ]; then
    echo "ERROR: Test frame generation failed"
    exit 1
fi

# Run simulation
if [ "$WAVES" == "1" ]; then
    echo "Waveform dumping enabled"
    vivado -mode batch -source scripts/run_sim.tcl -tclargs $TB_NAME $RUN_TIME +dump_waves
else
    vivado -mode batch -source scripts/run_sim.tcl -tclargs $TB_NAME $RUN_TIME
fi

if [ $? -eq 0 ]; then
    # Copy flow_field.txt from simulation directory to project root
    SIM_FLOW_FILE="prj/sim_${TB_NAME}/sim_project.sim/sim_1/behav/xsim/flow_field.txt"

    if [ -f "$SIM_FLOW_FILE" ]; then
        cp "$SIM_FLOW_FILE" flow_field_rtl.txt
        echo ""
        echo "Flow field copied to: flow_field_rtl.txt"
        echo ""
        echo "=========================================="
        echo "Test Region Statistics (x[55:85], y[105:135])"
        echo "=========================================="
        awk '$1>=55 && $1<=85 && $2>=105 && $2<=135 {
            sum_u+=$3; sum_v+=$4; n++
            if ($3 > 0) pos_u++
            if ($3 != 0 || $4 != 0) non_zero++
        } END {
            if (n > 0) {
                mean_u = sum_u/n
                mean_v = sum_v/n
                print "  Total vectors:     " n " (expect ~961)"
                print "  Non-zero vectors:  " non_zero
                print "  Mean flow:         u=" sprintf("%.3f", mean_u) ", v=" sprintf("%.3f", mean_v)
                print "  Positive u count:  " pos_u "/" n " (" sprintf("%.1f", 100*pos_u/n) "%)"
                print ""
                print "Expected (after fixes):"
                print "  Mean u: +0.8 to +1.5 pixels (rightward)"
                print "  Mean v: -0.2 to +0.2 pixels (near zero)"
                print "  Positive u: >70% (most vectors rightward)"
            } else {
                print "  ERROR: No vectors found in test region"
            }
        }' flow_field_rtl.txt
        echo "=========================================="
    else
        echo ""
        echo "Warning: Flow field not found at $SIM_FLOW_FILE"
    fi

    echo ""
    echo "Simulation complete. Check logs in prj/sim_${TB_NAME}/"
else
    echo "Simulation FAILED"
    exit 1
fi
