# Python Reference Implementation

## Overview

Python implementations of Lucas-Kanade optical flow for RTL verification and prototyping.

## Quick Start

```bash
# Install dependencies
pip install -e .

# Generate test patterns
python python/generate_test_suite.py

# Run verification
python python/optical_flow_verifier.py
```

## Folder Structure

```
python/
├── lucas_kanade_core.py       # Single-scale L-K implementation
├── lucas_kanade_pyramidal.py  # Multi-scale pyramid implementation
├── generate_test_suite.py     # Synthetic test pattern generator
├── optical_flow_verifier.py   # Automated verification suite
├── flow_metrics.py            # Standard evaluation metrics
├── verification_config.yaml   # Test suite configuration
├── verification_baseline.json # Regression test baseline
├── verification_results.md    # Latest quantitative results
└── verification_plots/        # Visual comparison outputs
```

# Core Implementations

### Single-Scale Lucas-Kanade

Single-Scale Lucas-Kanade (`lucas_kanade_core.py`), suitable for low motion (>5 px).

Standard L-K implementation:
```python
from lucas_kanade_core import LucasKanade

# Initialize
from lucas_kanade_core import lucas_kanade_single_scale

# Compute flow
u, v = lucas_kanade_single_scale(frame1, frame2, window_size=5)
```

`window_size`: Integration window (3, 5, 7, 9, 11)

#### Algorithm Summary:

1. Compute spatial gradients $I_x$, $I_y$ via Sobel operators
2. Compute temporal gradient $I_t = I_{prev} - I_{curr}$
3. Accumulate structure tensor over 5×5 window:
$$
A = \begin{bmatrix}
\sum I_x^2 & \sum I_x I_y \\
\sum I_x I_y & \sum I_y^2
\end{bmatrix},
\quad
\mathbf{b} = -\begin{bmatrix}
\sum I_x I_t \\
\sum I_y I_t
\end{bmatrix}
$$
4. Solve for flow: $\mathbf{u} = A^{-1} \mathbf{b}$

### Pyramidal Lucas-Kanade

Pyramidal Lucas-Kanade (`lucas_kanade_pyramidal.py`), suitable for larger motion.

Standard implementation:
```python
from lucas_kanade_pyramidal import lucas_kanade_pyramidal

# Compute flow with 3-level pyramid
u, v = lucas_kanade_pyramidal(
    frame1,
    frame2,
    num_levels=3,
    window_size=5,
    num_iterations=3
)
```

#### Coarse-to-Fine Refinement:

1. Build Gaussian pyramid (3 levels: 1/4×, 1/2×, 1× resolution)
2. Solve at coarsest level with zero initial flow
3. Upsample flow and warp current frame
4. Compute residual flow at next finer level
5. Accumulate: $\mathbf{u}{fine} = \mathbf{u}{coarse} + \Delta\mathbf{u}$

Parameters:

- `num_levels`: Number of pyramid scales (2-4 typical)
- `num_iterations`: Refinement iterations per level (2-5)
- `window_size`: Same as single-scale

---

## Test Suite

### Generating Patterns

```python
# Generate all 13 patterns
python python/generate_test_suite.py

# Custom displacement
python python/generate_test_suite.py --displacement-x 20 --displacement-y 10

# Specific patterns
python python/generate_test_suite.py --patterns translate_large rotate_small
```

### Available Patterns

- **Translation**: `translate_small` (0.5px), `translate_medium` (2px), `translate_large` (15px), `translate_extreme` (30px)
- **Rotation**: `rotate_small` (2°), `rotate_medium` (5°), `rotate_large` (10°)
- **Zoom**: `zoom_in` (5% expansion), `zoom_out` (5% contraction)
- **Combined**: `translate_rotate` (5px + 3°)
- **Edge cases**: `no_motion`, `translate_vertical` (5px vertical)

**Output**: `python/test_patterns/[pattern_name]/ (frame1.png, frame2.png, ground_truth.txt)`.

### Verification

```bash
# Full suite (all patterns, both implementations)
# Also regenerates output images
python python/optical_flow_verifier.py

# Specific patterns
python python/optical_flow_verifier.py --pattern translate_medium rotate_small

# Without visualizations (faster for CI/CD etc.)
python python/optical_flow_verifier.py --no-visualizations

# Custom pyramid config
python python/optical_flow_verifier.py --pyramid-config shallow
```

**Output**:
- `python/verification_results.md`: Quantitative metrics table
- `python/verification_plots/[pattern]/`: Flow field and error visualizations
- Console: Summary statistics and pass/fail status

### Regression Testing

Automated baseline comparison for catching unintended changes.

#### Initial Setup

```bash
# After validating results look correct:
python python/optical_flow_verifier.py --update-baseline
```

**Output:** `python/verification_baseline.json` with current metrics.

#### Actions

Used to catch unintended changes or regressions (obviously). Can also update to new baseline when adding new test patterns, changing algorithms, or improving accuracy (and thus the baseline).

```bash
# Before making changes to algorithm, load current code and run against baseline.
# Can add --regression-threshhold 5.0 for stricter, 20.0 for more lenient etc. (default 10%).
python python/optical_flow_verifier.py --compare-baseline

# Run verification on current code, evaluate against thresholds in verification_config.yaml.
# Does not compare against baseline, just checks against the thresholds. Run after changes made.
python python/optical_flow_verifier.py

# If changes are satisfactory, update current baseline with new values.
python python/optical_flow_verifier.py --update-baseline
```

## Evaluation Metrics

Implemented in `flow_metrics.py`.

| Metric                        | Description                                       |
|-------------------------------|---------------------------------------------------|
| MAE (Mean Absolute Error)     | Average per-component error                       |
| RMSE (Root Mean Square Error)	| RMS of flow magnitude error                       |
| EPE (Endpoint Error)          | Euclidean distance between predicted/true vectors |
| AAE (Angular Error)           | Angle between flow vectors in 3D (u,v,1) space    |

### Example Usage

```python
from flow_metrics import compute_all_metrics

metrics = compute_all_metrics(
    u_pred, v_pred,
    u_true=2.0, v_true=0.0,
    mask=valid_region
)

print(f"EPE: {metrics['epe']:.3f} pixels")
print(f"AAE: {metrics['aae']:.2f} degrees")
```

## Configuration

Defined in `verification_config.yaml`. Edit file to adjust variables.

### Example/Snippet

```yaml
window_sizes: [5, 7, 9]
pyramid_levels: 3
iterations_per_level: 3
sigma: 1.0

thresholds:
  translation:
    mae_pass: 0.5    # < 0.5px = Pass
    mae_warning: 2.0 # 0.5-2.0px = Warning (>2.0px = Fail)

  rotation:
    mae_pass: 1.0
    mae_warning: 3.0
  # ... etc.
```

File can be modified to test different params e.g. window size, or adjust pass/fail criteria. Also holds pyramid configurations.

## Common Issues

- Platform change: re-run baseline on target platform, differences in numerical precision between architectures can cause problems.
- High MAE on rotation tests: normal, rotation creates spacially-varying flow but L-K assumes constant motion. MAE rapidly increases with even small rotations.
- 30 px (extreme) is meant to fail in almost all cases, exceeds the problem tolerance of these implementations.

## Expected Behavior Notes

### Single-Scale Magnitude Underestimation

Single-scale Lucas-Kanade inherently underestimates flow magnitude on smooth synthetic patterns:

**Root Causes:**
1. Sobel operator normalization (÷8) reduces gradient magnitudes
2. Frame averaging blurs spatial edges
3. Aperture problem - uniform regions lack texture for reliable estimates

**Evidence from Verification:**

```bash
Pattern: translate_medium (2.0 pixels rightward)
  Python single-scale:  1.34 pixels MAE (67% of truth)
  RTL fixed-point:      0.76 pixels MAE (38% of truth)
  Python pyramidal:     0.53 pixels MAE (but excels on large motion)
  ```

RTL correctly implements L-K; the magnitude error matches what the Python reference produces (accounting for fixed-point precision).

If flow direction is wrong (sign flip), magnitude is zero in textured regions, or results diverge significantly from Python reference, then test flow will need to be evaluated.


## Example Workflows

### Algorithm Development (Python)

```bash
# Make changes to lucas_kanade_core.py
vim python/lucas_kanade_core.py

# Test on specific pattern
python python/optical_flow_verifier.py --pattern translate_medium

# Visual inspection
open python/verification_plots/translate_medium/flow_single.png

# Full regression check
python python/optical_flow_verifier.py --compare-baseline

# If improvement, update baseline
python python/optical_flow_verifier.py --update-baseline
```

### RTL Verification

```bash
# Generate test vectors
python python/generate_rtl_testvectors.py --pattern translate_medium

# Run RTL simulation (example)
cd sim
vsim -do "do run_test.tcl"

# Compare RTL outputs to python ones
python python/compare_rtl_results.py \
  --rtl-output sim/results.txt \
  --pattern translate_medium
```

<!-- TODO: Add RTL comparison scripts -->
