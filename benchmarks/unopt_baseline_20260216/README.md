# Unoptimized Baseline (Part 1)

**Purpose:** Capture intentionally naive implementation for blog series comparison

## Quick Summary
- Timing: WNS = -130.409 ns (fails at 100 MHz target)
- DSP Usage: 222/240 (92.5%)
- Bottleneck: Combinational division in flow_solver.sv

## Files
- `metrics.txt` - Quantitative results
- `DESIGN_NOTES.md` - Why it failed + Part 2 strategy
- `critical_path_verbose.txt` - Detailed timing paths
- `timing_summary_excerpt.txt` - Vivado timing report excerpt
- `rtl_manifest.txt` - File versions for reproducibility
- `*.rpt` - Full Vivado reports
- `*.dcp` - Design checkpoints

## Next: Part 2 Optimization
Replace division with Newton-Raphson → Target WNS > 0
