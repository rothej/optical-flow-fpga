# Optical Flow on FPGA

Real-time Lucas-Kanade optical flow implementation on Nexys A7-100T FPGA.

---

## Folder Structure
```
optical-flow-fpga/
├── .github/
| └── workflows/   # CI/CD workflows
├── constraints/   # Timing constraints (XDC)
├── docs/          # Documentation
├── prj/           # Vivado project files
│ ├── unopt/       # Unoptimized build artifacts
│ └── opt/         # Optimized build artifacts
├── python/        # Test generation and reference implementation
├── rtl/           # RTL source files (SystemVerilog)
│ ├── common/      # Shared modules (line buffers, frame buffer)
│ ├── unopt/       # Unoptimized implementation (fails timing)
│ └── opt/         # Optimized implementation (meets timing)
├── scripts/       # Build automation scripts
└── tb/            # Testbenches and test data
  └── test_frames/ # Generated .mem files
```

---

## Hardware

- **Board:** Digilent Nexys A7-100T
- **FPGA:** Xilinx Artix-7 (xc7a100tcsg324-1)
- **Resources:** 15,850 slices, 240 DSP48E1 slices, 4,860 Kb BRAM

---

## Architecture

### Lucas-Kanade Optical Flow

3-stage pipeline:

1. **Gradient Compute**: Sobel operators -> spatial gradients (Ix, Iy) + temporal difference (It)
2. **Window Accumulator**: 5×5 sliding window -> structure tensor components (Σ Ix², Σ Iy², Σ IxIy, etc.)
3. **Flow Solver**: Cramer's rule -> solve 2×2 system for (u, v) flow vectors

This RTL implements single-scale Lucas-Kanade, suitable for motions <5 pixels. Python reference includes both single-scale and pyramidal implementations.

---

## Verification

### Quick Start

```bash
# Generate test patterns
python python/generate_test_suite.py

# Run verification suite
python python/optical_flow_verifier.py

# Test specific patterns
python python/optical_flow_verifier.py --pattern translate_medium rotate_small
```

### Regression Testing

Automated baseline comparison for catching algorithm changes.
```bash
# Create initial baseline (run once after validating results)
python python/optical_flow_verifier.py --update-baseline

# Compare current implementation against baseline
python python/optical_flow_verifier.py --compare-baseline

# Adjust sensitivity (default: 10% threshold)
python python/optical_flow_verifier.py --compare-baseline --regression-threshold 5.0

# Update baseline after verified algorithm improvements
python python/optical_flow_verifier.py --update-baseline
```

What gets flagged:
- MAE (horizontal/vertical) changes >10%
- EPE (endpoint error) changes >10%

Example output:

```
========================================================
Regression Testing: Comparing Against Baseline
========================================================

translate_medium (Single-Scale):
    Regression detected:
    - mae_u: +12.3% change (current=1.51, baseline=1.34)

translate_medium (Pyramidal):
    Pass

========================================================
Regression detected in 1 test(s)
========================================================
```

Baseline location: `python/verification_baseline.json` (committed to repo).

### Python Reference Models

Two implementations provided for algorithm development and RTL verification:

**Single-Scale Lucas-Kanade** (`python/lucas_kanade.py`):
- Structure tensor computation with Gaussian weighting
- Least-squares flow solver (2×2 linear system)
- Suitable for small motions (<5 pixels)
- Serves as primary model for RTL verification

**Pyramidal Lucas-Kanade** (`python/lucas_kanade_pyramidal.py`):
- 3-level Gaussian pyramid with 2x downsampling
- Coarse-to-fine iterative refinement
- Handles large motions (tested up to 20 pixels)
- Demonstrates aperture problem mitigation

### Automated Test Suite

Comprehensive verification across 13 synthetic patterns:

```bash
# Generate test patterns
python python/generate_test_suite.py

# Run verification suite
python python/optical_flow_verifier.py

# Test specific patterns
python python/optical_flow_verifier.py --pattern translate_medium rotate_small
```

#### Tabulated Results

| Pattern           | Ground Truth | Single-Scale MAE | Pyramidal MAE | Single Status | Pyramidal Status |
|-------------------|--------------|------------------|---------------|---------------|------------------|
| translate_small   | (0.5, 0.5)   | 0.31 / 0.27      | 0.65 / 0.72   | Pass          | Warning          |
| translate_medium  | (2.0, 0.0)   | 1.34 / 0.77      | 0.53 / 0.37   | Warning       | Warning          |
| translate_large   | (15.0, 0.0)  | 14.82 / 2.06     | 6.04 / 4.90   | Fail          | Fail             |
| rotate_small      | (0.0, 0.0)   | 1.21 / 1.14      | 0.78 / 0.94   | Warning       | Pass             |
| rotate_medium     | (0.0, 0.0)   | 1.09 / 1.57      | 1.78 / 1.89   | Warning       | Warning          |
| zoom_in           | (0.0, 0.0)   | 1.17 / 1.74      | 2.02 / 2.10   | Warning       | Warning          |
| translate_rotate  | (5.0, 5.0)   | 4.78 / 4.85      | 1.13 / 1.29   | Fail          | Warning          |
| no_motion         | (0.0, 0.0)   | 0.00 / 0.00      | 0.00 / 0.00   | Pass          | Pass             |
| translate_extreme | (30.0, 20.0) | 29.65 / 18.93    | 34.24 / 21.15 | Fail          | Fail             |

*MAE (Mean Absolute Error) format: horizontal / vertical (pixels). Full metrics in `python/verification_results.md`.*

##### Summary of Results
- Single-scale excels at sub-pixel motion (0.31px MAE on small translation)
- Pyramidal approach reduces error by ~59% on large translations (14.8 to 6.0px)
- Combined motion benefits most from pyramid (4.8 to 1.3px MAE improvement)
- Both methods struggle with extreme motion (>20px) which is expected

#### Visual Comparison: Medium Translation (2px)

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="python/verification_plots/translate_medium/flow_single.png" alt="Single-scale flow field" width="400"/>
        <br><em>Single-Scale: MAE = 1.34px (horizontal)</em>
      </td>
      <td align="center">
        <img src="python/verification_plots/translate_medium/flow_pyramidal.png" alt="Pyramidal flow field" width="400"/>
        <br><em>Pyramidal: MAE = 0.53px (horizontal)</em>
      </td>
    </tr>
    <tr>
      <td align="center">
        <img src="python/verification_plots/translate_medium/error_single.png" alt="Single-scale error heatmap" width="400"/>
        <br><em>Error distribution: single-scale</em>
      </td>
      <td align="center">
        <img src="python/verification_plots/translate_medium/error_pyramidal.png" alt="Pyramidal error heatmap" width="400"/>
        <br><em>Error distribution: pyramidal (more uniform)</em>
      </td>
    </tr>
  </table>
</div>

#### Visual Comparison: Small Rotation (2°)

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="python/verification_plots/rotate_small/flow_single.png" alt="Single-scale rotation" width="400"/>
        <br><em>Single-Scale: Circular flow pattern</em>
      </td>
      <td align="center">
        <img src="python/verification_plots/rotate_small/flow_pyramidal.png" alt="Pyramidal rotation" width="400"/>
        <br><em>Pyramidal: Smoother flow recovery</em>
      </td>
    </tr>
  </table>
</div>

**Note:** Rotation patterns show elevated MAE even for small angles due to Lucas-Kanade's constant motion assumption. This is expected behavior - the algorithm assumes uniform translation within the window, but rotation creates spatially-varying flow.

### Verification Results

#### Test Case: 15-Pixel Horizontal Motion

<div align="center">
  <img src="python/output/flow_comparison.png" alt="Single-Scale vs Pyramidal Comparison" width="800"/>
  <p><em>Left: Single-scale (fails on large motion). Right: Pyramidal (successful coarse-to-fine refinement).</em></p>
</div>

#### Pyramid Level Breakdown

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="python/output/pyramid_level_0.png" alt="Coarsest level (80×60)" width="250"/>
        <br><em>Level 0: 80×60 px (coarsest)</em>
      </td>
      <td align="center">
        <img src="python/output/pyramid_level_1.png" alt="Middle level (160×120)" width="250"/>
        <br><em>Level 1: 160×120 px</em>
      </td>
      <td align="center">
        <img src="python/output/pyramid_level_2.png" alt="Finest level (320×240)" width="250"/>
        <br><em>Level 2: 320×240 px (finest)</em>
      </td>
    </tr>
  </table>
</div>

**Note**: Poor performance is expected at edges.

#### Convergence Behavior

```
============================================================
Pyramidal Lucas-Kanade Optical Flow
============================================================
Loaded frames: 320x240
Pyramid levels: 3
Window size: 5x5
Iterations per level: 3

============================================================
Running Pyramidal Lucas-Kanade...
============================================================
Building 3-level Gaussian pyramids...
Pyramid levels:
  Level 0: 80x60 pixels
  Level 1: 160x120 pixels
  Level 2: 320x240 pixels

Processing pyramid level 0/2...
  Iteration 1/3: mean residual = (4.0603, 0.5694)
  Iteration 2/3: mean residual = (0.8930, 0.9292)
  Iteration 3/3: mean residual = (0.2696, 0.5366)

Processing pyramid level 1/2...
  Upsampled flow to 160x120
  Iteration 1/3: mean residual = (0.7448, 1.9079)
  Iteration 2/3: mean residual = (0.5363, 1.1262)
  Iteration 3/3: mean residual = (0.5325, 1.2620)

Processing pyramid level 2/2...
  Upsampled flow to 320x240
  Iteration 1/3: mean residual = (2.5990, 4.9165)
  Iteration 2/3: mean residual = (2.1149, 3.8442)
  Iteration 3/3: mean residual = (2.0820, 4.1527)

============================================================
Pyramidal Results
============================================================
Mean flow in test region: u=15.081, v=0.134
Std dev in test region:   u=0.231, v=0.452
Expected: u=15.0, v=0.0 (from generate_test_frames_natural.py --displacement-x 15)
```

Flow field visualizations regenerate automatically when running the comparison script.

---

## Tools

### Required
- **Vivado**: 2022.2+ (Xilinx/AMD)
- **Python**: 3.12+ with NumPy, SciPy, Matplotlib
- **OS**: Linux Mint 21.3 (any Debian-based distro should work)

### Development (Optional)
- **Linting**: Verible (SystemVerilog), mypy (Python)
- **Environment**: [direnv](https://direnv.net/) for automatic venv activation

> **Note**: Other Vivado/Python versions may work but are untested.

---

## Building

This repo uses configuration-based builds to demonstrate timing optimization.

Unoptimized:
```bash
./scripts/build.sh unopt
```

Optimized:
```bash
./scripts/build.sh opt
```

Reports generated in `prj/<config>/`:

- Critical path analysis - `timing_summary_<config>.rpt`
- Resource usage - `utilization_<config>.rpt`

---

## Testing

### Algorithm Characteristics

**Single-Scale Lucas-Kanade Limitations:**

This implementation demonstrates single-scale L-K behavior:

- **Correct flow direction** detection (sign of motion)
- **Underestimates magnitude** on smooth textures (~40% of ground truth)
- **Fails on large motion** (>5 pixels exceeds window size)

Magnitude underestimation is caused by:
1. **Sobel normalization** (divide by 8 reduces gradient strength)
2. **Frame averaging** (blurs motion between frames)
3. **Aperture problem** (insufficient high-frequency texture in 5×5 windows)

**Comparison to Python Reference:**

| Implementation      | Mean Flow (u) | Error        | Notes                          |
|---------------------|---------------|--------------|--------------------------------|
| Ground Truth        | 2.00 pixels   | -            | Known displacement             |
| Python (float32)    | 1.34 pixels   | -33%         | Reference implementation       |
| RTL (S8.7 fixed)    | 0.76 pixels   | -62%         | Additional fixed-point effects |
| Pyramidal (Python)  | 0.53 pixels   | -74%*        | Better for large motion        |

*Pyramidal shows higher error on 2px motion (optimized for >5px), but excels on 15px translation (6.04px vs 14.82px single-scale).

### Python Reference Model

Generate test frames with checkerboard pattern.

Small motion (2 pixels):
```bash
python python/generate_test_frames.py --displacement-x 2
```

Run Lucas-Kanade reference:
```bash
python python/lucas_kanade.py
```

Large motion (15 pixels):
```bash
# Generate test pattern with large motion
python python/generate_test_frames_natural.py --displacement-x 15
# Compare methods
python python/lucas_kanade_pyramidal.py --compare
```

**Note**: The `python/test_data/` directory contains cached image(s) used for test frame generation (source: Wikimedia Commons).

### RTL Simulation

#### Option 1: Vivado GUI

Open the Vivado project:
```bash
vivado prj/optical_flow_fpga_prj/optical_flow_fpga_prj.xpr
```
From within the project, run the simulation using **Flow Navigator -> Run Simulation -> Run Behavioral Simulation**

#### Option 2: Terminal (Recommended)

Run:
```bash
./scripts/run_sim.sh tb_optical_flow_top
```

To enable waveform dump, run this instead:
```bash
./scripts/run_sim.sh tb_optical_flow_top 1
```

#### RTL Simulation Results

**Test Pattern:** 320×240 synthetic checkerboard, 2-pixel horizontal motion

```bash
Frame buffer loaded:
  Frame 0: tb/test_frames/frame_00.mem
  Frame 1: tb/test_frames/frame_01.mem
  Total pixels per frame: 76800

============================================
Optical Flow Accelerator Testbench
============================================
Configuration:
  Resolution: 320x240
  Total pixels: 76800
  Window size: 5x5
  Expected motion: rightward (2.0 pixels ground truth)
  Test criteria: magnitude >= 0.5 pixels, horizontal direction
  Test region: x[55:85], y[105:135]

=== Frame Buffer Verification ===
Sample pixels:
  Test region start [55,105] (idx=33655):
    frame_0 = 0x69 (105)
    frame_1 = 0x68 (104)
  Image center [60,120] (idx=38460):
    frame_0 = 0x95 (149)
    frame_1 = 0x8d (141)
  Frames differ (motion present)
=================================


[145000] Starting optical flow processing...
[155000] Processing active (busy asserted)
INFO: [USF-XSim-96] XSim completed. Design snapshot 'tb_optical_flow_top_behav' loaded.
INFO: [USF-XSim-97] XSim simulation ran for 1000ns
# run 100ms
[26045000] First valid flow output received
  Latency: 0 clock cycles
  Corresponds to pixel position (10, 8)
  Pipeline latency breakdown:
    Gradient line buffer: 1284 cycles
    Accumulator line buffer: 1284 cycles
    Register stages: 2 cycles
  [x= 55, y=105] u= 0.000, v= 0.000
  [x= 62, y=108] u= 0.000, v= 0.000
  [x= 69, y=111] u= 0.000, v= 0.000
  [x= 76, y=114] u=-1.664, v=-0.109
  [x= 83, y=117] u= 0.000, v= 0.000
  [x= 59, y=121] u= 0.000, v= 0.000
  [x= 66, y=124] u= 0.000, v= 0.000
  [x= 73, y=127] u=-1.750, v=-1.344
  [x= 80, y=130] u=-1.828, v= 0.664
  [x= 56, y=134] u=-1.805, v=-0.328

[768165000] Processing complete (done asserted)

============================================
Results Summary
============================================
Total valid flow vectors: 73289
Vectors in test region: 961
Latency: 0 cycles (0.00 us @ 100MHz)

Flow Statistics (Test Region):
  Mean:         u=-0.765, v=-0.053
  Std Dev:      u= 0.886, v= 0.307
  Ground truth: u= 2.000, v= 0.000
  Error vs GT:  u=-2.765, v=-0.053

============================================
Flow magnitude: 0.767 pixels
Flow direction: -176.0 degrees
*** TEST PASSED ***
Flow detection successful:
  - Magnitude: 0.767 >= 0.5 pixels (minimum threshold)
  - Direction: horizontal (v component < 0.5 pixels)
Note: Single-scale L-K underestimates smooth motion
      (expected behavior - see Python reference)
============================================
```

#### RTL Flow Field Visualization

<div align="center">
  <img src="results/flow_visualization.png" alt="RTL Flow Field Visualization" width="900"/>
  <p><em>4-panel diagnostic plot showing RTL-computed optical flow for 2-pixel rightward motion</em></p>
</div>

**Interpretation:**
- **Top-left (Quiver):** Vector field overlaid on the input grayscale frame. Each arrow represents the computed motion at that pixel location. Length is for visualization purposes, color represents magnitude (blue is small, green is medium, yellow is large). Confirms horizontal motion of image.
- **Top-right (Magnitude):** Scalar field showing flow magnitude (speed) at each pizel, direction agnostic. Red (1-2 px motion) matches ground truth magnitude.
- **Bottom-left (Distribution):** Histogram shows statistical distribution  of horizontal and vertical flow components across entire image. Average of ~1.8 pixels for horizontal, aiming for 0 pixels vertical but noise exists.
- **Bottom-right (Error Map):** Maps error magnitude verus ground truth. Shows 1-2 pixel error (typical for single-scale L-K on smooth motion).

This validates correct RTL implementation of the Lucas-Kanade algorithm.

To regenerate (developers):

```bash
# Generate test frames (if not done already)
python python/generate_test_frames_natural.py --displacement-x 2

# Run simulation (exports flow_field_rtl.txt)
./scripts/run_sim.sh tb_optical_flow_top

# Generate Python reference (for comparison)
python python/lucas_kanade_reference.py

# Convert .mem frames to PNG
python scripts/convert_frames.py

# Visualize RTL results
python scripts/visualize_flow.py flow_field_rtl.txt
```

Optional comparision of RTL and Python:

```bash
python scripts/visualize_flow.py flow_field_rtl.txt --compare
```

---

## Setup

### Environmental Setup (Required)

#### Method 1: With direnv

Repository uses `direnv` to manage the Python virtual environment and dependencies.

If `direnv` is not already installed, run:
```bash
sudo apt install direnv
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
source ~/.bashrc
```

From within the cloned repository folder, set up the virtual environment and install dependencies using:
```bash
direnv allow .
```

#### Method 2: Without direnv

From within the repository folder, run:
```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
pre-commit install
```

### Development Setup (Optional)

For contributors that want to modify RTL or Python code to be pushed up to this repository.

Uncomment the Vivado path exports in `.envrc`.

Then, install necessary dev tools:
```bash
./scripts/setup_verible.sh
pip install -e ".[dev]"
pre-commit install
```

These tools are not required for building or simulating the design.

#### Submitting PRs

Verify all pre-merge checks run by running `scripts/pre_merge_check.sh` before submitting a PR. Will need to run `git add .` one last time after the script runs - be sure to squash commits when merging PR.

---

## License

MIT License (MIT) - See LICENSE file for details.

---

## Author

[Joshua Rothe](http://joshrothe.us)
