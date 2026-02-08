#!/usr/bin/env python3
# scripts/visualize_flow.py
"""
Visualize optical flow results from RTL simulation.

Creates comprehensive 4-panel diagnostic plot:
  - Flow field quiver overlay
  - Magnitude heatmap
  - Component distribution histogram
  - Error magnitude vs ground truth
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


def create_diagnostic_plot(
    frame_path: str,
    flow_file: str,
    output_path: str,
    ground_truth_u: float = 2.0,
    ground_truth_v: float = 0.0,
    stride: int = 10,
    scale: float = 20.0,
) -> None:
    """
    Create comprehensive 4-panel diagnostic visualization.

    Args:
        frame_path: Path to grayscale frame PNG
        flow_file: Path to flow field text file
        output_path: Where to save output
        ground_truth_u: Expected horizontal flow
        ground_truth_v: Expected vertical flow
        stride: Arrow subsampling stride
        scale: Arrow scale factor
    """
    # Load frame
    frame = Image.open(frame_path)
    frame_array = np.array(frame)
    height, width = frame_array.shape

    # Load flow field
    x, y, u, v, metadata = parse_flow_field(flow_file)

    # Compute flow magnitude
    magnitude = np.sqrt(u**2 + v**2)

    # Create flow field grids for heatmaps
    u_field = np.zeros((height, width))
    v_field = np.zeros((height, width))
    mag_field = np.zeros((height, width))

    for i in range(len(x)):
        xi = int(x[i])
        yi = int(y[i])
        if 0 <= xi < width and 0 <= yi < height:
            u_field[yi, xi] = u[i]
            v_field[yi, xi] = v[i]
            mag_field[yi, xi] = magnitude[i]

    # Compute error vs ground truth
    error_u = u_field - ground_truth_u
    error_v = v_field - ground_truth_v
    error_mag = np.sqrt(error_u**2 + error_v**2)

    # Extract test region statistics
    if all(k in metadata for k in ["test_x_min", "test_y_min", "test_x_max", "test_y_max"]):
        x_min = metadata["test_x_min"]
        x_max = metadata["test_x_max"]
        y_min = metadata["test_y_min"]
        y_max = metadata["test_y_max"]

        u_test = u_field[y_min : y_max + 1, x_min : x_max + 1]
        v_test = v_field[y_min : y_max + 1, x_min : x_max + 1]
        mag_test = mag_field[y_min : y_max + 1, x_min : x_max + 1]

        # Filter out zero values (no flow computed)
        mask = mag_test > 0
        u_test_valid = u_test[mask]
        v_test_valid = v_test[mask]
        mag_test_valid = mag_test[mask]

        mean_u = np.mean(u_test_valid) if len(u_test_valid) > 0 else 0
        mean_v = np.mean(v_test_valid) if len(v_test_valid) > 0 else 0
        std_u = np.std(u_test_valid) if len(u_test_valid) > 0 else 0
        std_v = np.std(v_test_valid) if len(v_test_valid) > 0 else 0
        mean_mag = np.mean(mag_test_valid) if len(mag_test_valid) > 0 else 0
        std_mag = np.std(mag_test_valid) if len(mag_test_valid) > 0 else 0
        num_vectors = len(u_test_valid)
    else:
        # No test region defined
        mean_u = np.mean(u)
        mean_v = np.mean(v)
        std_u = np.std(u)
        std_v = np.std(v)
        mean_mag = np.mean(magnitude)
        std_mag = np.std(magnitude)
        num_vectors = len(u)

    # Create 2x2 subplot figure
    fig = plt.figure(figsize=(16, 12), dpi=150)
    gs = fig.add_gridspec(2, 2, hspace=0.3, wspace=0.3)

    # --- Top-Left: Flow Field Quiver ---
    ax1 = fig.add_subplot(gs[0, 0])
    extent = (0, width, height, 0)
    ax1.imshow(frame_array, cmap="gray", extent=extent)

    # Subsample for quiver
    indices = np.arange(0, len(x), stride)
    ax1.quiver(
        x[indices],
        y[indices],
        u[indices],
        v[indices],
        magnitude[indices],
        angles="xy",
        scale_units="xy",
        scale=1.0 / scale,
        cmap="jet",
        width=0.003,
        headwidth=3,
        alpha=0.8,
    )

    # Highlight test region
    if "test_x_min" in metadata:
        rect = Rectangle(
            (metadata["test_x_min"], metadata["test_y_min"]),
            metadata["test_x_max"] - metadata["test_x_min"],
            metadata["test_y_max"] - metadata["test_y_min"],
            linewidth=2,
            edgecolor="cyan",
            facecolor="none",
            linestyle="--",
        )
        ax1.add_patch(rect)
        ax1.text(
            metadata["test_x_min"] + 2,
            metadata["test_y_min"] + 2,
            "Test Region",
            color="cyan",
            fontsize=10,
            bbox=dict(boxstyle="round,pad=0.3", facecolor="black", alpha=0.7),
        )

    ax1.set_title("Optical Flow Field (Quiver Plot)", fontsize=12, pad=10)
    ax1.set_xlabel("X (pixels)")
    ax1.set_ylabel("Y (pixels)")
    ax1.set_aspect("equal")

    # --- Top-Right: Magnitude Heatmap ---
    ax2 = fig.add_subplot(gs[0, 1])
    im2 = ax2.imshow(mag_field, cmap="hot", extent=extent, vmin=0, vmax=np.max(magnitude))

    if "test_x_min" in metadata:
        rect2 = Rectangle(
            (metadata["test_x_min"], metadata["test_y_min"]),
            metadata["test_x_max"] - metadata["test_x_min"],
            metadata["test_y_max"] - metadata["test_y_min"],
            linewidth=2,
            edgecolor="cyan",
            facecolor="none",
            linestyle="--",
        )
        ax2.add_patch(rect2)

    ax2.set_title("Flow Magnitude Heatmap", fontsize=12, pad=10)
    ax2.set_xlabel("X (pixels)")
    ax2.set_ylabel("Y (pixels)")
    ax2.set_aspect("equal")

    cbar2 = plt.colorbar(im2, ax=ax2, fraction=0.046, pad=0.04)
    cbar2.set_label("Magnitude (pixels)", rotation=270, labelpad=15)

    # --- Bottom-Left: Component Distribution ---
    ax3 = fig.add_subplot(gs[1, 0])

    # Histogram of u and v components (test region only if available)
    if "test_x_min" in metadata and len(u_test_valid) > 0:
        u_hist = u_test_valid
        v_hist = v_test_valid
    else:
        u_hist = u
        v_hist = v

    ax3.hist(u_hist, bins=50, alpha=0.6, color="blue", label="u (horizontal)", edgecolor="black")
    ax3.hist(v_hist, bins=50, alpha=0.6, color="red", label="v (vertical)", edgecolor="black")

    # Ground truth lines
    ax3.axvline(
        ground_truth_u,
        color="blue",
        linestyle="--",
        linewidth=2,
        label=f"GT u={ground_truth_u:.1f}",
    )
    ax3.axvline(
        ground_truth_v, color="red", linestyle="--", linewidth=2, label=f"GT v={ground_truth_v:.1f}"
    )

    ax3.set_xlabel("Flow Component (pixels)")
    ax3.set_ylabel("Frequency")
    ax3.set_title("Flow Component Distribution", fontsize=12, pad=10)
    ax3.legend(loc="upper right")
    ax3.grid(True, alpha=0.3)

    # Add statistics text
    stats_text = (
        f"Flow Statistics:\n"
        f"Mean: u={mean_u:.3f}, v={mean_v:.3f}\n"
        f"Std:  u={std_u:.3f}, v={std_v:.3f}\n"
        f"Magnitude: {mean_mag:.3f} ± {std_mag:.3f}\n"
        f"Total vectors: {len(u)}\n"
        f"\n"
        f"Test Region ({num_vectors} vectors):\n"
        f"Mean: u={mean_u:.3f}, v={mean_v:.3f}\n"
        f"Magnitude: {mean_mag:.3f} ± {std_mag:.3f}\n"
        f"Error vs GT: u={mean_u - ground_truth_u:.3f}, v={mean_v - ground_truth_v:.3f}"
    )

    ax3.text(
        0.02,
        0.98,
        stats_text,
        transform=ax3.transAxes,
        fontsize=9,
        verticalalignment="top",
        bbox=dict(boxstyle="round,pad=0.5", facecolor="wheat", alpha=0.8),
        family="monospace",
    )

    # --- Bottom-Right: Error Magnitude ---
    ax4 = fig.add_subplot(gs[1, 1])
    im4 = ax4.imshow(error_mag, cmap="viridis", extent=extent, vmin=0, vmax=np.max(error_mag))

    if "test_x_min" in metadata:
        rect4 = Rectangle(
            (metadata["test_x_min"], metadata["test_y_min"]),
            metadata["test_x_max"] - metadata["test_x_min"],
            metadata["test_y_max"] - metadata["test_y_min"],
            linewidth=2,
            edgecolor="cyan",
            facecolor="none",
            linestyle="--",
        )
        ax4.add_patch(rect4)

    ax4.set_title("Error Magnitude vs Ground Truth", fontsize=12, pad=10)
    ax4.set_xlabel("X (pixels)")
    ax4.set_ylabel("Y (pixels)")
    ax4.set_aspect("equal")

    cbar4 = plt.colorbar(im4, ax=ax4, fraction=0.046, pad=0.04)
    cbar4.set_label("Error (pixels)", rotation=270, labelpad=15)

    # Save figure
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close()


def main() -> None:
    """Main visualization script."""
    parser = argparse.ArgumentParser(description="Visualize optical flow results")
    parser.add_argument(
        "flow_file",
        help="Flow field file to visualize",
    )
    parser.add_argument(
        "--frame",
        default="tb/test_frames/frame_00.png",
        help="Frame to overlay flow on (PNG)",
    )
    parser.add_argument(
        "--output",
        default="results/flow_visualization.png",
        help="Output visualization file",
    )
    parser.add_argument(
        "--ground-truth-u",
        type=float,
        default=2.0,
        help="Ground truth horizontal flow (pixels)",
    )
    parser.add_argument(
        "--ground-truth-v",
        type=float,
        default=0.0,
        help="Ground truth vertical flow (pixels)",
    )
    parser.add_argument(
        "--stride",
        type=int,
        default=16,
        help="Arrow subsampling stride",
    )
    parser.add_argument(
        "--scale",
        type=float,
        default=7.0,
        help="Arrow scale factor",
    )

    args = parser.parse_args()

    # Verify input files exist
    if not Path(args.flow_file).exists():
        print(f"ERROR: Flow file not found: {args.flow_file}")
        return

    if not Path(args.frame).exists():
        print(f"ERROR: Frame file not found: {args.frame}")
        print("Run: python scripts/convert_frames.py")
        return

    print("Generating 4-panel diagnostic visualization...")

    # Ensure output directory exists
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)

    # Create diagnostic plot
    create_diagnostic_plot(
        args.frame,
        args.flow_file,
        args.output,
        ground_truth_u=args.ground_truth_u,
        ground_truth_v=args.ground_truth_v,
        stride=args.stride,
        scale=args.scale,
    )

    print(f"Generated: {args.output}")
    print("\nVisualization complete!")


if __name__ == "__main__":
    main()
