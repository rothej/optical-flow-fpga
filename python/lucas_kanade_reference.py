#!/usr/bin/env python3
# python/lucas_kanade_reference.py
"""
Lucas-Kanade optical flow reference implementation.
Used to verify FPGA implementation and generate test vectors.
"""

import argparse
from pathlib import Path
from typing import Tuple

import numpy as np
import numpy.typing as npt


def compute_gradients(
    frame_prev: npt.NDArray[np.float32], frame_curr: npt.NDArray[np.float32]
) -> Tuple[npt.NDArray[np.float32], npt.NDArray[np.float32], npt.NDArray[np.float32]]:
    """
    Compute spatial and temporal gradients using Sobel operators.

    Args:
        frame_prev: Previous frame (grayscale, float32)
        frame_curr: Current frame (grayscale, float32)

    Returns:
        Tuple of (Ix, Iy, It) gradient arrays
    """
    # Sobel kernels for spatial gradients (applied to average of frames)
    sobel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=np.float32) / 8.0

    sobel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=np.float32) / 8.0

    # Average frame for spatial gradients (reduces noise)
    frame_avg = (frame_prev + frame_curr) / 2.0

    # Compute spatial gradients via convolution
    from scipy import signal

    Ix = signal.convolve2d(frame_avg, sobel_x, mode="same", boundary="symm")
    Iy = signal.convolve2d(frame_avg, sobel_y, mode="same", boundary="symm")

    # Temporal gradient (simple difference)
    It = frame_prev - frame_curr

    return Ix, Iy, It


def lucas_kanade_window(
    Ix: npt.NDArray[np.float32],
    Iy: npt.NDArray[np.float32],
    It: npt.NDArray[np.float32],
    window_size: int = 5,
) -> Tuple[npt.NDArray[np.float32], npt.NDArray[np.float32]]:
    """
    Compute optical flow using Lucas-Kanade method with sliding window.

    Args:
        Ix: Spatial gradient in X direction
        Iy: Spatial gradient in Y direction
        It: Temporal gradient
        window_size: Size of analysis window (must be odd)

    Returns:
        Tuple of (u, v) flow fields
    """
    height, width = Ix.shape
    u = np.zeros((height, width), dtype=np.float32)
    v = np.zeros((height, width), dtype=np.float32)

    half_win = window_size // 2

    # Process each pixel (excluding borders)
    for y in range(half_win, height - half_win):
        for x in range(half_win, width - half_win):
            # Extract window
            win_Ix = Ix[y - half_win : y + half_win + 1, x - half_win : x + half_win + 1]
            win_Iy = Iy[y - half_win : y + half_win + 1, x - half_win : x + half_win + 1]
            win_It = It[y - half_win : y + half_win + 1, x - half_win : x + half_win + 1]

            # Compute sums for least squares (structure tensor)
            sum_Ix2 = np.sum(win_Ix * win_Ix)
            sum_Iy2 = np.sum(win_Iy * win_Iy)
            sum_IxIy = np.sum(win_Ix * win_Iy)
            sum_IxIt = np.sum(win_Ix * win_It)
            sum_IyIt = np.sum(win_Iy * win_It)

            # Structure tensor (A^T * A)
            A = np.array([[sum_Ix2, sum_IxIy], [sum_IxIy, sum_Iy2]], dtype=np.float32)

            # Right-hand side (-A^T * b)
            b = np.array([-sum_IxIt, -sum_IyIt], dtype=np.float32)

            # Solve system (with regularization - stable)
            det = A[0, 0] * A[1, 1] - A[0, 1] * A[1, 0]

            # Compute flow where there's sufficient texture
            if abs(det) > 1e-4:
                u[y, x] = (A[1, 1] * b[0] - A[0, 1] * b[1]) / det
                v[y, x] = (A[0, 0] * b[1] - A[0, 1] * b[0]) / det

    return u, v


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
    ax.set_title("Optical Flow Vectors")
    ax.set_xlabel("X (pixels)")
    ax.set_ylabel("Y (pixels)")

    plt.colorbar(ax.collections[0], ax=ax, label="Flow Magnitude (pixels)")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    print(f"Flow visualization saved: {output_path}")


def main() -> None:
    """Run Lucas-Kanade on test frames and save results."""
    parser = argparse.ArgumentParser(description="Lucas-Kanade reference implementation")
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

    # Compute gradients
    print("\nComputing gradients...")
    Ix, Iy, It = compute_gradients(frame_prev, frame_curr)

    # Debug: Check gradient magnitudes
    print("\nGradient statistics:")
    print(f"  Ix range: [{np.min(Ix):.2f}, {np.max(Ix):.2f}]")
    print(f"  Iy range: [{np.min(Iy):.2f}, {np.max(Iy):.2f}]")
    print(f"  It range: [{np.min(It):.2f}, {np.max(It):.2f}]")

    # Check gradients in square region
    square_region = np.s_[105:135, 55:85]
    print("\nGradients in square region:")
    print(f"  Ix mean: {np.mean(np.abs(Ix[square_region])):.3f}")
    print(f"  Iy mean: {np.mean(np.abs(Iy[square_region])):.3f}")
    print(f"  It mean: {np.mean(np.abs(It[square_region])):.3f}")

    # Compute optical flow
    print("Computing optical flow...")
    u, v = lucas_kanade_window(Ix, Iy, It, window_size=args.window_size)

    # Window analysis
    print("\nWindow analysis:")
    half_win = args.window_size // 2
    valid_region = np.s_[half_win:-half_win, half_win:-half_win]
    total_valid_windows = (args.height - 2 * half_win) * (args.width - 2 * half_win)
    computed_windows = np.sum(u[valid_region] != 0)

    print(f"  Total possible windows: {total_valid_windows}")
    print(f"  Windows with non-zero flow: {computed_windows}")
    print("  Windows at square region: analyzing...")

    # Analyze square boundary windows
    square_y_range = range(100, 140)
    square_x_range = range(50, 90)

    # Count windows that overlap square edges
    edge_windows = 0
    interior_windows = 0
    for y in range(half_win, args.height - half_win):
        for x in range(half_win, args.width - half_win):
            # Window spans y-half_win to y+half_win, x-half_win to x+half_win
            win_y_min, win_y_max = y - half_win, y + half_win + 1
            win_x_min, win_x_max = x - half_win, x + half_win + 1

            # Check if window center is in square region
            if y in square_y_range and x in square_x_range:
                # Check if window extends beyond square boundaries
                if win_y_min < 100 or win_y_max > 140 or win_x_min < 50 or win_x_max > 90:
                    edge_windows += 1
                else:
                    interior_windows += 1

    print(f"  Square edge windows (partial overlap): {edge_windows}")
    print(f"  Square interior windows (full overlap): {interior_windows}")

    # Analyze results in the square region (should show rightward motion)
    # Square is at y=100:140, x=50:90 in frame 0, displaced +2 in x
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

    # Visualize
    try:
        visualize_flow(u, v, output_dir / "flow_visualization.png")
    except ImportError:
        print("Matplotlib not available, skipping visualization")


if __name__ == "__main__":
    main()
