#!/usr/bin/env python3
# python/lucas_kanade_reference.py
"""
Lucas-Kanade optical flow reference implementation (single-scale).
Used to verify FPGA implementation and generate test vectors.
"""

import argparse
from pathlib import Path
from typing import Optional

import numpy as np
import numpy.typing as npt
from lucas_kanade_core import compute_gradients, lucas_kanade_single_scale


def visualize_flow(
    u: npt.NDArray[np.float32], v: npt.NDArray[np.float32], output_path: Path, scale: float = 10.0
) -> None:
    """
    Create a visualization of optical flow vectors.

    Args:
        u: Horizontal flow component
        v: Vertical flow component
        output_path: Where to save visualization
        scale: Arrow scale factor
    """
    import matplotlib.pyplot as plt

    height, width = u.shape

    # Subsample for visualization (every 10th pixel)
    step = 10
    y_coords, x_coords = np.mgrid[step:height:step, step:width:step]

    u_sub = u[step:height:step, step:width:step]
    v_sub = v[step:height:step, step:width:step]

    # Create figure
    fig, ax = plt.subplots(figsize=(12, 9))

    # Magnitude for color
    magnitude = np.sqrt(u_sub**2 + v_sub**2)

    # Quiver plot
    ax.quiver(
        x_coords,
        y_coords,
        u_sub,
        v_sub,
        magnitude,
        angles="xy",
        scale_units="xy",
        scale=1.0 / scale,
        cmap="jet",
        width=0.003,
    )

    ax.set_aspect("equal")
    ax.set_xlim(0, width)
    ax.set_ylim(height, 0)  # Invert Y axis to match image coordinates
    ax.set_title("Optical Flow Vectors (Single-Scale Lucas-Kanade)")
    ax.set_xlabel("X (pixels)")
    ax.set_ylabel("Y (pixels)")

    plt.colorbar(ax.collections[0], ax=ax, label="Flow Magnitude (pixels)")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    print(f"Flow visualization saved: {output_path}")


def export_flow_field_txt(
    u: np.ndarray,
    v: np.ndarray,
    output_path: Path,
    width: int,
    height: int,
    test_region: Optional[dict] = None,
) -> None:
    """Export flow field in text format for visualization script."""
    with open(output_path, "w") as f:
        f.write("# Optical flow field data (Python reference)\n")
        f.write("# Format: x y u v\n")
        f.write(f"# Image size: {width}x{height}\n")

        # Add test region
        if test_region:
            f.write(
                f"# Test region: x[{test_region['x_min']}:{test_region['x_max']}], "
                f"y[{test_region['y_min']}:{test_region['y_max']}]\n"
            )

        for y_idx in range(height):
            for x_idx in range(width):
                f.write(f"{x_idx} {y_idx} {u[y_idx, x_idx]:.6f} {v[y_idx, x_idx]:.6f}\n")

    print(f"Flow field text export: {output_path}")


def main() -> None:
    """Run single-scale Lucas-Kanade on test frames and save results."""
    parser = argparse.ArgumentParser(description="Lucas-Kanade single-scale reference")
    parser.add_argument(
        "--frame-dir",
        type=str,
        default="tb/test_frames",
        help="Directory containing frame_00.bin and frame_01.bin",
    )
    parser.add_argument("--width", type=int, default=320, help="Frame width")
    parser.add_argument("--height", type=int, default=240, help="Frame height")
    parser.add_argument("--window-size", type=int, default=5, help="Window size for Lucas-Kanade")
    parser.add_argument(
        "--output-dir", type=str, default="python/output", help="Output directory for results"
    )

    args = parser.parse_args()

    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Load frames
    frame_dir = Path(args.frame_dir)
    frame_prev_u8 = np.fromfile(frame_dir / "frame_00.bin", dtype=np.uint8)
    frame_curr_u8 = np.fromfile(frame_dir / "frame_01.bin", dtype=np.uint8)

    frame_prev: npt.NDArray[np.float32] = frame_prev_u8.reshape((args.height, args.width)).astype(
        np.float32
    )
    frame_curr: npt.NDArray[np.float32] = frame_curr_u8.reshape((args.height, args.width)).astype(
        np.float32
    )

    print(f"Loaded frames: {args.width}x{args.height}")
    print(f"Window size: {args.window_size}x{args.window_size}")

    # Compute gradients (for debugging)
    print("\nComputing gradients...")
    Ix, Iy, It = compute_gradients(frame_prev, frame_curr)

    # Check gradient magnitudes
    print("\nGradient statistics:")
    print(f"  Ix range: [{np.min(Ix):.2f}, {np.max(Ix):.2f}]")
    print(f"  Iy range: [{np.min(Iy):.2f}, {np.max(Iy):.2f}]")
    print(f"  It range: [{np.min(It):.2f}, {np.max(It):.2f}]")

    # Compute optical flow using core algorithm
    print("Computing optical flow...")
    u, v = lucas_kanade_single_scale(frame_prev, frame_curr, window_size=args.window_size)

    # Window analysis
    print("\nWindow analysis:")
    half_win = args.window_size // 2
    valid_region = np.s_[half_win:-half_win, half_win:-half_win]
    total_valid_windows = (args.height - 2 * half_win) * (args.width - 2 * half_win)
    computed_windows = np.sum(u[valid_region] != 0)

    print(f"  Total possible windows: {total_valid_windows}")
    print(f"  Windows with non-zero flow: {computed_windows}")

    # Analyze results in the textured region
    square_region = np.s_[105:135, 55:85]  # Interior of square (avoid edges)

    u_mean = np.mean(u[square_region])
    v_mean = np.mean(v[square_region])
    u_std = np.std(u[square_region])
    v_std = np.std(v[square_region])

    print("\n=== Results ===")
    print(f"Mean flow in square region: u={u_mean:.3f}, v={v_mean:.3f}")
    print(f"Std dev in square region:   u={u_std:.3f}, v={v_std:.3f}")
    print("Expected: u=2.0, v=0.0")

    # Save flow fields
    u.tofile(output_dir / "flow_u.bin")
    v.tofile(output_dir / "flow_v.bin")
    print(f"\nFlow fields saved to {output_dir}")

    # Export text format for visualization
    test_region = {"x_min": 55, "x_max": 85, "y_min": 105, "y_max": 135}

    export_flow_field_txt(
        u=u,
        v=v,
        output_path=output_dir / "flow_field_python.txt",
        width=args.width,
        height=args.height,
        test_region=test_region,
    )

    # Visualize
    try:
        visualize_flow(u, v, output_dir / "flow_visualization_single_scale.png")
    except ImportError:
        print("Matplotlib not available, skipping visualization")


if __name__ == "__main__":
    main()
