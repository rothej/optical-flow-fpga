#!/bin/bash
# scripts/run_sim.sh

TB_NAME=${1:-tb_optical_flow_top}
WAVES=${2:-0}

echo "=========================================="
echo "Running simulation: $TB_NAME"
echo "=========================================="

# Generate test frames
echo "Generating test frames..."
python python/generate_test_frames.py --displacement-x 2

if [ $? -ne 0 ]; then
    echo "ERROR: Test frame generation failed"
    exit 1
fi

# Run simulation
if [ "$WAVES" == "1" ]; then
    echo "Waveform dumping enabled"
    vivado -mode batch -source scripts/run_sim.tcl -tclargs $TB_NAME +dump_waves
else
    vivado -mode batch -source scripts/run_sim.tcl -tclargs $TB_NAME
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "Simulation complete. Check logs in sim_${TB_NAME}/"
else
    echo "Simulation FAILED"
    exit 1
fi
