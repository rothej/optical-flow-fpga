# Unoptimized Baseline Design Notes

## Key Finding: Division Bottleneck

**WNS = -130.409 ns** (target: 10 ns for 100 MHz)

### Root Cause
The `flow_solver.sv` module uses combinational 32-bit division:
```systemverilog
flow_u_comb = (numerator_u <<< FRAC_BITS) / det;
flow_v_comb = (numerator_v <<< FRAC_BITS) / det;
```

This synthesizes to ~100 logic levels of LUT cascade, creating a 130ns path.

### What Worked: DSP Inference

- Successfully inferred 222 DSP48E1 primitives
- Multiplications in window_accumulator.sv use dedicated DSP blocks
- Each 5x5 window: 125 multiplies (IxIx, IyIy, IxIy, IxIt, Iy*It)
- 3 pyramid levels share DSP resources → 222 total

## Optimization Strategy

1. Replace division with Newton-Raphson reciprocal
  - Compute recip = 1/det using iterative refinement (4 stages)
  - Then flow_u = numerator_u * recip (DSP multiply)
  - Expected: 4-5 ns per N-R stage = 20-25 ns total

2. If still needed: Pipeline accumulator
  - Break 25-element adder chain into 2-3 stages
  - Currently combinational after DSP multiplies

3. Expected Result
  - WNS: +2 to +5 ns at 100 MHz
  - Latency: 8-10 cycles (vs. 4, but 13× faster clock)
  - Net throughput gain: 13×

## Critical Files

- `rtl/unopt/flow_solver.sv` (lines ~66-90): Division bottleneck
- `rtl/unopt/window_accumulator.sv` (lines ~79-140): DSP success
- See `critical_path_verbose.txt` for detailed timing path

## Reproducibility

```bash
git checkout $(git rev-parse --short HEAD)
./scripts/build.sh unopt impl
# Should produce WNS = -130.409 ns
```
