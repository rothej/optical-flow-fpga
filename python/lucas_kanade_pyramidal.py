#!/usr/bin/env python3
# python/lucas_kanade_pyramidal.py
"""
Pyramidal Lucas-Kanade optical flow implementation.
Coarse-to-fine refinement for handling larger displacements.
"""

import argparse
import os
from pathlib import Path
from typing import Tuple

import numpy as np
import numpy.typing as npt
from lucas_kanade_core import lucas_kanade_single_scale
from scipy.ndimage import map_coordinates


def build_gaussian_pyramid(
    image: npt.NDArray[np.float32], num_levels: int, scale_factor: float = 0.5
) -> list[npt.NDArray[np.float32]]:
    """
    Build Gaussian pyramid by iterative smoothing and downsampling.

    Args:
        image: Input image (grayscale, float32)
        num_levels: Number of pyramid levels (1 = original only)
        scale_factor: Downsampling factor between levels (default 0.5 = half resolution)

    Returns:
        List of images from coarse (smallest) to fine (original)
    """
    from scipy.ndimage import gaussian_filter

    pyramid: list[npt.NDArray[np.float32]] = []
    current = image.copy()

    # Build from fine to coarse
    for level in range(num_levels):
        if level > 0:
            # Smooth before downsampling (anti-aliasing)
            sigma = 1.0 / scale_factor
            smoothed = gaussian_filter(current, sigma=sigma)

            # Downsample
            height, width = smoothed.shape
            new_height = int(height * scale_factor)
            new_width = int(width * scale_factor)

            # Use bilinear interpolation for downsampling
            y_coords = np.linspace(0, height - 1, new_height)
            x_coords = np.linspace(0, width - 1, new_width)
            yy, xx = np.meshgrid(y_coords, x_coords, indexing="ij")

            current = map_coordinates(smoothed, [yy, xx], order=1, mode="constant")

        pyramid.insert(0, current)  # Insert at beginning (coarse to fine)

    return pyramid


def warp_image(
    image: npt.NDArray[np.float32],
    flow_u: npt.NDArray[np.float32],
    flow_v: npt.NDArray[np.float32],
) -> npt.NDArray[np.float32]:
    """
    Warp image according to flow field using bilinear interpolation.

    This "moves" the image forward by the flow vectors, effectively
    compensating for the motion so the residual flow is smaller.

    Args:
        image: Image to warp (grayscale, float32)
        flow_u: Horizontal flow component
        flow_v: Vertical flow component

    Returns:
        Warped image
    """
    height, width = image.shape

    # Create coordinate grids
    yy, xx = np.meshgrid(np.arange(height), np.arange(width), indexing="ij")

    # Compute warped coordinates (add flow to move pixels forward)
    x_warped = xx + flow_u
    y_warped = yy + flow_v

    # Bilinear interpolation
    warped_any = map_coordinates(image, [y_warped, x_warped], order=1, mode="constant", cval=0.0)
    warped: npt.NDArray[np.float32] = warped_any.astype(np.float32)
    return warped


def upsample_flow(
    flow_u: npt.NDArray[np.float32],
    flow_v: npt.NDArray[np.float32],
    target_shape: Tuple[int, int],
) -> Tuple[npt.NDArray[np.float32], npt.NDArray[np.float32]]:
    """
    Upsample flow field to target resolution.

    Flow magnitudes are scaled proportionally to the resolution increase.

    Args:
        flow_u: Coarse horizontal flow
        flow_v: Coarse vertical flow
        target_shape: (height, width) of desired output

    Returns:
        Tuple of upsampled (u, v) flow fields
    """
    coarse_height, coarse_width = flow_u.shape
    target_height, target_width = target_shape

    # Scale factors
    scale_y = target_height / coarse_height
    scale_x = target_width / coarse_width

    # Create coordinate grids for target resolution
    y_target = np.linspace(0, coarse_height - 1, target_height)
    x_target = np.linspace(0, coarse_width - 1, target_width)
    yy, xx = np.meshgrid(y_target, x_target, indexing="ij")

    # Bilinear interpolation
    flow_u_upsampled = map_coordinates(flow_u, [yy, xx], order=1, mode="constant")
    flow_v_upsampled = map_coordinates(flow_v, [yy, xx], order=1, mode="constant")

    # Scale flow magnitudes (motion is proportional to resolution)
    flow_u_upsampled = flow_u_upsampled * scale_x
    flow_v_upsampled = flow_v_upsampled * scale_y

    return flow_u_upsampled.astype(np.float32), flow_v_upsampled.astype(np.float32)


def lucas_kanade_pyramidal(
    frame_prev: npt.NDArray[np.float32],
    frame_curr: npt.NDArray[np.float32],
    num_levels: int = 3,
    window_size: int = 5,
    num_iterations: int = 3,
) -> Tuple[npt.NDArray[np.float32], npt.NDArray[np.float32]]:
    """
    Pyramidal Lucas-Kanade optical flow with coarse-to-fine refinement.

    Algorithm:
    1. Build Gaussian pyramids for both frames
    2. Start at coarsest level with zero flow
    3. For each level (coarse to fine):
       a. Upsample flow from previous level
       b. Warp current frame using upsampled flow
       c. Compute residual flow between previous and warped current
       d. Add residual to accumulated flow
    4. Return final refined flow at original resolution

    Args:
        frame_prev: Previous frame (grayscale, float32)
        frame_curr: Current frame (grayscale, float32)
        num_levels: Number of pyramid levels
        window_size: Window size for Lucas-Kanade
        num_iterations: Iterations per pyramid level (for further refinement)

    Returns:
        Tuple of (u, v) flow fields at original resolution
    """
    # Build pyramids (coarse to fine)
    print(f"Building {num_levels}-level Gaussian pyramids...")
    pyr_prev = build_gaussian_pyramid(frame_prev, num_levels)
    pyr_curr = build_gaussian_pyramid(frame_curr, num_levels)

    # Verify pyramid shapes
    print("Pyramid levels:")
    for i, (p, c) in enumerate(zip(pyr_prev, pyr_curr)):
        print(f"  Level {i}: {p.shape[1]}x{p.shape[0]} pixels")

    # Initialize flow at coarsest level (all zeros)
    height, width = pyr_prev[0].shape
    flow_u = np.zeros((height, width), dtype=np.float32)
    flow_v = np.zeros((height, width), dtype=np.float32)

    # Coarse-to-fine refinement
    for level in range(num_levels):
        print(f"\nProcessing pyramid level {level}/{num_levels-1}...")

        # Get images at current level
        img_prev = pyr_prev[level]
        img_curr = pyr_curr[level]

        # Upsample flow from previous level (if not at coarsest)
        if level > 0:
            target_shape = img_prev.shape
            flow_u, flow_v = upsample_flow(flow_u, flow_v, target_shape)
            print(f"  Upsampled flow to {target_shape[1]}x{target_shape[0]}")

        # Iterative refinement at this level
        for iteration in range(num_iterations):
            # Warp current frame using current flow estimate
            img_warped = warp_image(img_curr, flow_u, flow_v)

            # Compute residual flow (between prev and warped current)
            du, dv = lucas_kanade_single_scale(img_prev, img_warped, window_size)

            # Accumulate flow
            flow_u += du
            flow_v += dv

            # Statistics
            mean_du = np.mean(np.abs(du))
            mean_dv = np.mean(np.abs(dv))
            print(
                f"  Iteration {iteration+1}/{num_iterations}: "
                f"mean residual = ({mean_du:.4f}, {mean_dv:.4f})"
            )

            # Early termination if residual is small
            if mean_du < 0.01 and mean_dv < 0.01:
                print(f"  Converged after {iteration+1} iterations")
                break

        # Save visualization
        visualize_pyramid_level(flow_u, flow_v, level, num_levels)

    return flow_u, flow_v


def visualize_flow_comparison(
    flow_u_single: npt.NDArray[np.float32],
    flow_v_single: npt.NDArray[np.float32],
    flow_u_pyr: npt.NDArray[np.float32],
    flow_v_pyr: npt.NDArray[np.float32],
    output_path: Path,
    scale: float = 1.0,
) -> None:
    """
    Create side-by-side comparison of single-scale vs pyramidal flow.

    Args:
        flow_u_single: Single-scale horizontal flow
        flow_v_single: Single-scale vertical flow
        flow_u_pyr: Pyramidal horizontal flow
        flow_v_pyr: Pyramidal vertical flow
        output_path: Where to save visualization
        scale: Arrow scale factor
    """
    import matplotlib.pyplot as plt

    height, width = flow_u_single.shape

    # Subsample for visualization
    step = 10
    y_coords, x_coords = np.mgrid[step:height:step, step:width:step]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(20, 9))

    # Single-scale
    u_sub = flow_u_single[step:height:step, step:width:step]
    v_sub = flow_v_single[step:height:step, step:width:step]
    mag = np.sqrt(u_sub**2 + v_sub**2)

    ax1.quiver(
        x_coords,
        y_coords,
        u_sub,
        v_sub,
        mag,
        angles="xy",
        scale_units="xy",
        scale=1.0 / scale,
        cmap="jet",
        width=0.003,
    )
    ax1.set_aspect("equal")
    ax1.set_xlim(0, width)
    ax1.set_ylim(height, 0)
    ax1.set_title("Single-Scale Lucas-Kanade")
    ax1.set_xlabel("X (pixels)")
    ax1.set_ylabel("Y (pixels)")

    # Pyramidal
    u_sub = flow_u_pyr[step:height:step, step:width:step]
    v_sub = flow_v_pyr[step:height:step, step:width:step]
    mag = np.sqrt(u_sub**2 + v_sub**2)

    ax2.quiver(
        x_coords,
        y_coords,
        u_sub,
        v_sub,
        mag,
        angles="xy",
        scale_units="xy",
        scale=1.0 / scale,
        cmap="jet",
        width=0.003,
    )
    ax2.set_aspect("equal")
    ax2.set_xlim(0, width)
    ax2.set_ylim(height, 0)
    ax2.set_title("Pyramidal Lucas-Kanade")
    ax2.set_xlabel("X (pixels)")
    ax2.set_ylabel("Y (pixels)")

    plt.tight_layout()
    plt.savefig(output_path, dpi=100)
    print(f"Comparison visualization saved: {output_path}")


def visualize_pyramid_level(
    flow_u: np.ndarray,
    flow_v: np.ndarray,
    level: int,
    num_levels: int = 3,
    output_dir: str = "python/output",
) -> None:
    """Visualize flow field at a specific pyramid level."""
    import matplotlib.pyplot as plt
    from matplotlib.colors import Normalize

    os.makedirs(output_dir, exist_ok=True)

    # Compute flow magnitude for color coding
    magnitude = np.sqrt(flow_u**2 + flow_v**2)

    fig, axes = plt.subplots(1, 3, figsize=(15, 4))

    # U component
    im0 = axes[0].imshow(flow_u, cmap="RdBu_r", norm=Normalize(vmin=-20, vmax=20))
    axes[0].set_title(f"Level {level}: U (horizontal)")
    axes[0].axis("off")
    plt.colorbar(im0, ax=axes[0], label="pixels")

    # V component
    im1 = axes[1].imshow(flow_v, cmap="RdBu_r", norm=Normalize(vmin=-20, vmax=20))
    axes[1].set_title(f"Level {level}: V (vertical)")
    axes[1].axis("off")
    plt.colorbar(im1, ax=axes[1], label="pixels")

    # Magnitude
    im2 = axes[2].imshow(magnitude, cmap="viridis", norm=Normalize(vmin=0, vmax=20))
    axes[2].set_title(f"Level {level}: Magnitude")
    axes[2].axis("off")
    plt.colorbar(im2, ax=axes[2], label="pixels")

    plt.tight_layout()
    plt.savefig(f"{output_dir}/pyramid_level_{level}.png", dpi=100, bbox_inches="tight")
    plt.close()


def main() -> None:
    """Run pyramidal Lucas-Kanade and compare to single-scale."""
    parser = argparse.ArgumentParser(description="Pyramidal Lucas-Kanade optical flow")
    parser.add_argument(
        "--frame-dir",
        type=str,
        default="tb/test_frames",
        help="Directory containing frame_00.bin and frame_01.bin",
    )
    parser.add_argument("--width", type=int, default=320, help="Frame width")
    parser.add_argument("--height", type=int, default=240, help="Frame height")
    parser.add_argument("--num-levels", type=int, default=3, help="Number of pyramid levels")
    parser.add_argument("--window-size", type=int, default=5, help="Window size")
    parser.add_argument(
        "--num-iterations",
        type=int,
        default=3,
        help="Iterations per pyramid level",
    )
    parser.add_argument("--output-dir", type=str, default="python/output", help="Output directory")
    parser.add_argument(
        "--compare",
        action="store_true",
        help="Compare with single-scale implementation",
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

    print("=" * 60)
    print("Pyramidal Lucas-Kanade Optical Flow")
    print("=" * 60)
    print(f"Loaded frames: {args.width}x{args.height}")
    print(f"Pyramid levels: {args.num_levels}")
    print(f"Window size: {args.window_size}x{args.window_size}")
    print(f"Iterations per level: {args.num_iterations}")

    # Run pyramidal Lucas-Kanade
    print("\n" + "=" * 60)
    print("Running Pyramidal Lucas-Kanade...")
    print("=" * 60)
    u_pyr, v_pyr = lucas_kanade_pyramidal(
        frame_prev,
        frame_curr,
        num_levels=args.num_levels,
        window_size=args.window_size,
        num_iterations=args.num_iterations,
    )

    # Analyze results
    test_region = np.s_[105:135, 55:85]
    u_mean = np.mean(u_pyr[test_region])
    v_mean = np.mean(v_pyr[test_region])
    u_std = np.std(u_pyr[test_region])
    v_std = np.std(v_pyr[test_region])

    print("\n" + "=" * 60)
    print("Pyramidal Results")
    print("=" * 60)
    print(f"Mean flow in test region: u={u_mean:.3f}, v={v_mean:.3f}")
    print(f"Std dev in test region:   u={u_std:.3f}, v={v_std:.3f}")
    print("Expected: u=15.0, v=0.0 (from generate_test_frames_natural.py --displacement-x 15)")

    # Save pyramidal flow
    u_pyr.tofile(output_dir / "flow_u_pyramidal.bin")
    v_pyr.tofile(output_dir / "flow_v_pyramidal.bin")
    print(f"\nPyramidal flow fields saved to {output_dir}")

    # Optional: Compare with single-scale
    if args.compare:
        print("\n" + "=" * 60)
        print("Running Single-Scale for Comparison...")
        print("=" * 60)
        from lucas_kanade_core import lucas_kanade_single_scale

        u_single, v_single = lucas_kanade_single_scale(
            frame_prev, frame_curr, window_size=args.window_size
        )

        u_mean_single = np.mean(u_single[test_region])
        v_mean_single = np.mean(v_single[test_region])

        print("\n" + "=" * 60)
        print("Comparison")
        print("=" * 60)
        print(f"Single-scale: u={u_mean_single:.3f}, v={v_mean_single:.3f}")
        print(f"Pyramidal:    u={u_mean:.3f}, v={v_mean:.3f}")
        print(
            f"Difference:   u={abs(u_mean - u_mean_single):.3f}, "
            f"v={abs(v_mean - v_mean_single):.3f}"
        )

        # Visualize comparison
        try:
            visualize_flow_comparison(
                u_single,
                v_single,
                u_pyr,
                v_pyr,
                output_dir / "flow_comparison.png",
            )
        except ImportError:
            print("Matplotlib not available, skipping visualization")

    print("\n" + "=" * 60)
    print("Complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
