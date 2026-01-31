# Optical Flow on FPGA

Real-time Lucas-Kanade optical flow implementation on Nexys A7-100T FPGA.

## Folder Structure
```
optical-flow-fpga/
├── .github/
| └── workflows/   # CI/CD workflows
├── constraints/   # Timing constraints (XDC)
├── docs/          # Documentation
├── prj/           # Vivado project files
├── python/        # Test generation and reference implementation
├── rtl/           # RTL source files (SystemVerilog)
├── scripts/       # TCL automation scripts
└── tb/            # Testbenches and test data
  └── test_Frames/ # Generated .mem files
```

## Table of Contents

- [Hardware](#hardware)
- [Architecture](#architecture)
- [Tools](#tools)
- [Testing](#testing)
- [Setup](#setup)
- [License](#license)
- [Author](#author)

## Hardware

- **Board:** Digilent Nexys A7-100T
- **FPGA:** Xilinx Artix-7 (xc7a100tcsg324-1)
- **Clock:** 100 MHz system clock
- **Memory:** 128 MB DDR2

## Architecture

## Tools

- Vivado: 2022.2
- Python: 3.12 with NumPy, OpenCV
- OS: Linux Mint 21.3

Other debian-based OSes should be fine. Project may also work with other Vivado and Python versions, but this is not guaranteed. You can use `pyenv` to handle multiple python versions on your system.

## Testing

### Python

To run all tests, use:
```bash
pytest
```

To run a specific test, use:
```bash
pytest python/tests/test_generate_frames.py -v
```
Change the file name as necessary.

### Vivado

Open the Vivado project:
```bash
cd ../
vivado optical_flow_fpga.xpr
```
From within the project, run the simulation using **Flow Navigator -> Run Simulation -> Run Behavioral Simulation**

## Setup

### Prerequisites

- Python 3.12+
- [direnv](https://direnv.net/) (recommended) or manual venv management

### Installation

#### Development Only

In addition to the below steps; if developing, run the following to set up Verible for use in pre-commit.
```bash
./scripts/setup_verible.sh
```

#### With direnv

Repository uses `direnv` to manage the virtual environment and dependencies. From within the repository folder, run:
```bash
direnv allow .
```

If you do not have `direnv`, it can be installed and added to `.bashrc` using:
```bash
sudo apt install direnv
eval "$(direnv hook bash)"
```

#### Without direnv

From within the repository folder, run:
```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
pre-commit install
```


## License

MIT License (MIT) - See LICENSE file for details.

## Author

[Joshua Rothe](http://joshrothe.us)
