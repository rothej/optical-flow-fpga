# Unoptimized Baseline Design

**Target:** Nexys A7-100T (xc7a100tcsg324-1)
**Clock Constraint:** 10ns (100 MHz)

## Summary

This is an intentionally unoptimized baseline design. The design demonstrates common FPGA timing pitfalls that will be addressed in the optimized build.

Design features massive combination paths and no pipelining.

## Timing Results

| Metric                 | Value        |
|------------------------|--------------|
| **WNS**                | -110.051 ns  |
| **TNS**                | -3520.810 ns |
| **Failing Endpoints**  | 32 / 345     |
| **Target Frequency**   | 100 MHz      |
| **Achieved Frequency** | ~8.3 MHz     |

This unoptimized design misses timing by 110 ns (WNS). This is more than 11x the clock period, and indicates that critical paths require ~120ns to stabilize; a theoretical maximum frequency of ~8.3 MHz.

## Resource Utilization

| Resource | Used  | Available | Utilization |
|----------|-------|-----------|-------------|
| **LUTs** | 3,765 | 63,400    | 5.94%       |
| **FFs**  | 129   | 126,800   | 0.10%       |
| **DSPs** | 23    | 240       | 9.58%       |
| **BRAM** | 0     | 135       | 0.00%       |

Plenty of resources available for optimization. Low FF utilization coincides with no pipelining, which would likely take up LUT resources for pipeline registers (which are also readily available).

## Critical Path Analysis

See [critical_paths.md](./critical_paths.md) for detailed breakdown.

## Files

- [Full Timing Report](./reports/timing_summary_unopt.rpt)
- [Full Utilization Report](./reports/utilization_unopt.rpt)
- [Critical Path Details](./critical_paths.md)
