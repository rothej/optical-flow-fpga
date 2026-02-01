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
│ ├── unopt/ # Unoptimized build artifacts
│ └── opt/ # Optimized build artifacts
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

## Table of Contents

- [Hardware](#hardware)
- [Architecture](#architecture)
- [Tools](#tools)
- [Building](#building)
- [Testing](#testing)
- [Setup](#setup)
- [License](#license)
- [Author](#author)

---

## Hardware

- **Board:** Digilent Nexys A7-100T
- **FPGA:** Xilinx Artix-7 (xc7a100tcsg324-1)
- **Resources:** 15,850 slices, 240 DSP48E1 slices, 4,860 Kb BRAM

---

## Architecture

### Lucas-Kanade Optical Flow

3-stage pipeline:

1. Gradient Compute: Sobel operators -> spatial gradients (Ix, Iy) + temporal difference (It)
2. Window Accumulator: 5×5 sliding window -> structure tensor components (Σ Ix², Σ Iy², Σ IxIy, etc.)
3. Flow Solver: Cramer's rule -> solve 2×2 system for (u, v) flow vectors

---

## Tools

### Required:
- Vivado: 2022.2+ (Xilinx/AMD)
- Python: 3.12+ with NumPy, SciPy, Matplotlib
- Linting: Verible (SystemVerilog), mypy (Python)
- Environment: [direnv](https://direnv.net/) for automatic venv activation
- OS: Linux Mint 21.3 (any Debian-based should work)

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

### Python Reference Model

Generate test frames (moving checkerboard pattern):

```bash
python python/generate_test_frames.py --displacement-x 2
```

Run Lucas-Kanade reference:

```bash
python python/lucas_kanade_reference.py
```

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

Expected output:
```bash
============================================
Optical Flow Accelerator Testbench
============================================
...
Flow Statistics (Test Region):
  Mean:     u= 2.013, v= 0.042
  Expected: u= 2.000, v= 0.000
  Error:    u= 0.013, v= 0.042

*** TEST PASSED ***
Flow vectors within tolerance (±0.5 pixels)
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

Linters can be ran manually using:

#### RTL
```bash
verible-verilog-lint
```

#### Python
```bash
mypy
```

These tools are not required for building or simulating the design.

---

## License

MIT License (MIT) - See LICENSE file for details.

---

## Author

[Joshua Rothe](http://joshrothe.us)
