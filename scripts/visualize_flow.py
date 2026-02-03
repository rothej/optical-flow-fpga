#!/usr/bin/env python3
# scripts/visualize_flow.py
"""
Visualize optical flow results from RTL simulation and Python reference.

Creates overlay plots with flow vectors, error maps, and comparison figures.
"""

import argparse
from pathlib import Path
from typing import Dict, Tuple

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Rectangle
from PIL import Image


def parse_flow_field(
    file_path: str,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, Dict[str, int]]:
    """Parse flow field text file (x y u v format)."""
    data = np.loadtxt(file_path, comments="#")

    # Extract metadata from header
    metadata: Dict[str, int] = {}
    with open(file_path, "r") as f:
        for line in f:
            if "Image size:" in line:
                parts = line.split(":")
                if len(parts) > 1:
                    dims = parts[1].strip().replace("x", " ").split()
                    if len(dims) >= 2:
                        metadata["width"] = int(dims[0])
                        metadata["height"] = int(dims[1])
            elif "Test region:" in line:
                # Parse: x[55:85], y[105:135]
                parts = line.split("x[")
                if len(parts) > 1:
                    x_part = parts[1].split("]")[0]
                    x_vals = x_part.split(":")
                    metadata["test_x_min"] = int(x_vals[0])
                    metadata["test_x_max"] = int(x_vals[1])

                if "y[" in line:
                    y_part = line.split("y[")[1].split("]")[0]
                    y_vals = y_part.split(":")
                    metadata["test_y_min"] = int(y_vals[0])
                    metadata["test_y_max"] = int(y_vals[1])

    x = data[:, 0]
    y = data[:, 1]
    u = data[:, 2]
    v = data[:, 3]

    return x, y, u, v, metadata


def load_flow_field(
    file_path: str,
    width: int = 320,
    height: int = 240,
) -> Tuple[np.ndarray, np.ndarray]:
    """Load flow field and reshape to image dimensions."""
    x, y, u_vals, v_vals, _ = parse_flow_field(file_path)

    # Initialize full flow field
    u_field: np.ndarray = np.zeros((height, width))
    v_field: np.ndarray = np.zeros((height, width))

    # Fill in values (handle potential sparse data)
    for i in range(len(x)):
        xi = int(x[i])
        yi = int(y[i])
        if 0 <= xi < width and 0 <= yi < height:
            u_field[yi, xi] = u_vals[i]
            v_field[yi, xi] = v_vals[i]

    return u_field, v_field


def plot_flow_overlay(
    frame_path: str,
    flow_file: str,
    output_path: str,
    title: str,
    stride: int = 10,
    scale: float = 20.0,
) -> None:
    """Create flow overlay visualization on grayscale frame."""
    # Load frame
    frame = Image.open(frame_path)
    frame_array = np.array(frame)

    # Load flow field
    x, y, u, v, metadata = parse_flow_field(flow_file)

    # Create figure
    fig, ax = plt.subplots(figsize=(12, 9), dpi=150)

    # Show grayscale frame
    extent_tuple: Tuple[float, float, float, float] = (
        0.0,
        float(frame_array.shape[1]),
        float(frame_array.shape[0]),
        0.0,
    )
    ax.imshow(frame_array, cmap="gray", extent=extent_tuple)

    # Overlay flow vectors (subsample for clarity)
    indices = np.arange(0, len(x), stride)
    ax.quiver(
        x[indices],
        y[indices],
        u[indices],
        v[indices],
        color="cyan",
        scale=scale,
        scale_units="xy",
        width=0.003,
        headwidth=3,
        headlength=4,
        alpha=0.8,
    )

    # Highlight test region if metadata available
    if metadata:
        rect = Rectangle(
            (metadata["test_x_min"], metadata["test_y_min"]),
            metadata["test_x_max"] - metadata["test_x_min"],
            metadata["test_y_max"] - metadata["test_y_min"],
            linewidth=2,
            edgecolor="yellow",
            facecolor="none",
            linestyle="--",
        )
        ax.add_patch(rect)

    ax.set_title(title, fontsize=14, pad=10)
    ax.set_xlabel("X (pixels)")
    ax.set_ylabel("Y (pixels)")
    ax.grid(False)
    ax.set_aspect("equal")

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close()


def plot_error_map(
    flow_rtl_file: str,
    flow_ref_file: str,
    output_path: str,
    width: int = 320,
    height: int = 240,
) -> None:
    """Create error magnitude heatmap."""
    # Load both flow fields
    u_rtl, v_rtl = load_flow_field(flow_rtl_file, width, height)
    u_ref, v_ref = load_flow_field(flow_ref_file, width, height)

    # Calculate error magnitude
    error_u = u_rtl - u_ref
    error_v = v_rtl - v_ref
    error_mag = np.sqrt(error_u**2 + error_v**2)

    # Get test region bounds
    _, _, _, _, metadata = parse_flow_field(flow_rtl_file)

    # Create figure
    fig, ax = plt.subplots(figsize=(12, 9), dpi=150)

    # Plot error heatmap
    extent_tuple: Tuple[float, float, float, float] = (0.0, float(width), float(height), 0.0)
    im = ax.imshow(error_mag, cmap="hot", extent=extent_tuple, vmin=0, vmax=1.0)

    # Highlight test region
    if metadata:
        rect = Rectangle(
            (metadata["test_x_min"], metadata["test_y_min"]),
            metadata["test_x_max"] - metadata["test_x_min"],
            metadata["test_y_max"] - metadata["test_y_min"],
            linewidth=2,
            edgecolor="cyan",
            facecolor="none",
            linestyle="--",
        )
        ax.add_patch(rect)

    # Add colorbar
    cbar = plt.colorbar(im, ax=ax)
    cbar.set_label("Error Magnitude (pixels)", rotation=270, labelpad=20)

    ax.set_title("Flow Error: |RTL - Python Reference|", fontsize=14, pad=10)
    ax.set_xlabel("X (pixels)")
    ax.set_ylabel("Y (pixels)")
    ax.set_aspect("equal")

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close()


def plot_comparison_grid(
    frame0_path: str,
    frame1_path: str,
    flow_rtl_file: str,
    flow_ref_file: str,
    output_path: str,
    width: int = 320,
    height: int = 240,
) -> None:
    """Create 2x2 comparison grid."""
    # Load frames
    frame0 = np.array(Image.open(frame0_path))
    frame1 = np.array(Image.open(frame1_path))

    # Load flow fields
    x_rtl, y_rtl, u_rtl, v_rtl, metadata = parse_flow_field(flow_rtl_file)
    x_ref, y_ref, u_ref, v_ref, _ = parse_flow_field(flow_ref_file)

    # Create 2x2 grid
    fig, axes = plt.subplots(2, 2, figsize=(16, 12), dpi=150)

    extent_tuple: Tuple[float, float, float, float] = (0.0, float(width), float(height), 0.0)

    # Top-left: Frame 0
    axes[0, 0].imshow(frame0, cmap="gray", extent=extent_tuple)
    axes[0, 0].set_title("Frame 0 (t)", fontsize=12)
    axes[0, 0].set_xlabel("X (pixels)")
    axes[0, 0].set_ylabel("Y (pixels)")

    # Top-right: Frame 1
    axes[0, 1].imshow(frame1, cmap="gray", extent=extent_tuple)
    axes[0, 1].set_title("Frame 1 (t+1)", fontsize=12)
    axes[0, 1].set_xlabel("X (pixels)")
    axes[0, 1].set_ylabel("Y (pixels)")

    # Bottom-left: RTL flow
    axes[1, 0].imshow(frame0, cmap="gray", extent=extent_tuple)
    stride = 10
    indices_rtl = np.arange(0, len(x_rtl), stride)
    axes[1, 0].quiver(
        x_rtl[indices_rtl],
        y_rtl[indices_rtl],
        u_rtl[indices_rtl],
        v_rtl[indices_rtl],
        color="cyan",
        scale=20.0,
        scale_units="xy",
        width=0.003,
        headwidth=3,
        alpha=0.8,
    )
    axes[1, 0].set_title("RTL Flow Output", fontsize=12)
    axes[1, 0].set_xlabel("X (pixels)")
    axes[1, 0].set_ylabel("Y (pixels)")

    # Bottom-right: Python reference flow
    axes[1, 1].imshow(frame0, cmap="gray", extent=extent_tuple)
    indices_ref = np.arange(0, len(x_ref), stride)
    axes[1, 1].quiver(
        x_ref[indices_ref],
        y_ref[indices_ref],
        u_ref[indices_ref],
        v_ref[indices_ref],
        color="lime",
        scale=20.0,
        scale_units="xy",
        width=0.003,
        headwidth=3,
        alpha=0.8,
    )
    axes[1, 1].set_title("Python Reference Flow", fontsize=12)
    axes[1, 1].set_xlabel("X (pixels)")
    axes[1, 1].set_ylabel("Y (pixels)")

    # Highlight test region on all plots
    if metadata:
        for ax_row in axes:
            for ax in ax_row:
                rect = Rectangle(
                    (metadata["test_x_min"], metadata["test_y_min"]),
                    metadata["test_x_max"] - metadata["test_x_min"],
                    metadata["test_y_max"] - metadata["test_y_min"],
                    linewidth=1.5,
                    edgecolor="yellow",
                    facecolor="none",
                    linestyle="--",
                )
                ax.add_patch(rect)
                ax.set_aspect("equal")

    rect_tuple: Tuple[float, float, float, float] = (0.0, 0.0, 1.0, 1.0)
    plt.tight_layout(rect=rect_tuple)
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close()


def print_statistics(
    flow_rtl_file: str,
    flow_ref_file: str,
    width: int = 320,
    height: int = 240,
) -> None:
    """Print flow statistics and comparison."""
    # Load flow fields
    u_rtl, v_rtl = load_flow_field(flow_rtl_file, width, height)
    u_ref, v_ref = load_flow_field(flow_ref_file, width, height)

    # Get test region
    _, _, _, _, metadata = parse_flow_field(flow_rtl_file)

    if metadata:
        x_min = metadata["test_x_min"]
        x_max = metadata["test_x_max"]
        y_min = metadata["test_y_min"]
        y_max = metadata["test_y_max"]

        # Extract test region
        u_rtl_region = u_rtl[y_min : y_max + 1, x_min : x_max + 1]
        v_rtl_region = v_rtl[y_min : y_max + 1, x_min : x_max + 1]
        u_ref_region = u_ref[y_min : y_max + 1, x_min : x_max + 1]
        v_ref_region = v_ref[y_min : y_max + 1, x_min : x_max + 1]

        # Calculate statistics
        print("\n=== Flow Statistics (Test Region) ===")
        print(f"RTL Mean:      u={np.mean(u_rtl_region):.3f}, v={np.mean(v_rtl_region):.3f}")
        print(f"Python Mean:   u={np.mean(u_ref_region):.3f}, v={np.mean(v_ref_region):.3f}")

        # Error metrics
        error_u = u_rtl_region - u_ref_region
        error_v = v_rtl_region - v_ref_region
        error_mag = np.sqrt(error_u**2 + error_v**2)

        print(f"\nMean Absolute Error:     {np.mean(np.abs(error_mag)):.3f} pixels")
        print(f"RMS Error:               {np.sqrt(np.mean(error_mag**2)):.3f} pixels")
        print(f"Max Error:               {np.max(error_mag):.3f} pixels")
        print(f"Median Error:            {np.median(error_mag):.3f} pixels")


def main() -> None:
    """Main visualization script."""
    parser = argparse.ArgumentParser(description="Visualize optical flow results")
    parser.add_argument(
        "--rtl-flow",
        default="sim_tb_optical_flow_top/flow_field.txt",
        help="RTL flow field file",
    )
    parser.add_argument(
        "--python-flow",
        default="python/flow_field_python.txt",
        help="Python reference flow field file",
    )
    parser.add_argument(
        "--frame0",
        default="tb/test_frames/frame_00.png",
        help="First frame (PNG)",
    )
    parser.add_argument(
        "--frame1",
        default="tb/test_frames/frame_01.png",
        help="Second frame (PNG)",
    )
    parser.add_argument(
        "--output-dir",
        default=".",
        help="Output directory for plots",
    )

    args = parser.parse_args()

    # Verify input files exist
    for file_path in [args.rtl_flow, args.python_flow, args.frame0, args.frame1]:
        if not Path(file_path).exists():
            print(f"ERROR: File not found: {file_path}")
            return

    print("Generating visualizations...")

    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # 1. RTL flow overlay
    print("  Creating RTL flow overlay...")
    plot_flow_overlay(
        args.frame0,
        args.rtl_flow,
        str(output_dir / "flow_overlay_rtl.png"),
        "RTL Flow Output",
    )
    print("Generated: flow_overlay_rtl.png")

    # 2. Python reference overlay
    print("  Creating Python reference overlay...")
    plot_flow_overlay(
        args.frame0,
        args.python_flow,
        str(output_dir / "flow_overlay_python.png"),
        "Python Reference Flow",
    )
    print("Generated: flow_overlay_python.png")

    # 3. Error map
    print("  Creating error map...")
    plot_error_map(
        args.rtl_flow,
        args.python_flow,
        str(output_dir / "flow_error_map.png"),
    )
    print("Generated: flow_error_map.png")

    # 4. Comparison grid
    print("  Creating comparison grid...")
    plot_comparison_grid(
        args.frame0,
        args.frame1,
        args.rtl_flow,
        args.python_flow,
        str(output_dir / "comparison_vertical.png"),
    )
    print("Generated: comparison_vertical.png")

    # 5. Print statistics
    print_statistics(args.rtl_flow, args.python_flow)

    print("\nVisualization complete!")


if __name__ == "__main__":
    main()
