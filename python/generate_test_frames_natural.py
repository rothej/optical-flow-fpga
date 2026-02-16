#!/usr/bin/env python3
# python/generate_test_frames_natural.py
"""Generate test frames using natural image patterns."""

import argparse
from pathlib import Path
from typing import Any

import numpy as np
from numpy.typing import NDArray
from PIL import Image

# Cache directory for image(s)
SCRIPT_DIR = Path(__file__).resolve().parent
CACHE_DIR = SCRIPT_DIR / "test_data"
CACHED_IMAGE = CACHE_DIR / "mountain_texture.jpg"


def load_test_image() -> np.ndarray:
    """Load the cached natural texture image."""
    if not CACHED_IMAGE.exists():
        raise FileNotFoundError(
            f"Natural texture image not found at {CACHED_IMAGE}. "
            "Please ensure mountain_texture.jpg exists in python/test_data/"
        )

    img = Image.open(CACHED_IMAGE).convert("L")
    return np.array(img, dtype=np.uint8)


def generate_natural_pattern(width: int = 320, height: int = 240) -> NDArray[np.uint8]:
    """
    Create a textured pattern from an image of the alps.

    Alternative: Use OpenCV's structured patterns.
    """
    # Load image
    try:
        img = load_test_image()
        # Crop/resize to desired dimensions
        img_resized = Image.fromarray(img).resize((width, height))
        return np.array(img_resized, dtype=np.uint8)
    except Exception as e:
        print(f"Error loading natural image: {e}")
        print("Falling back to synthetic pattern...")
        return generate_smooth_synthetic(width, height)


def generate_smooth_synthetic(width: int, height: int) -> NDArray[np.uint8]:
    """Create smooth synthetic texture using sum of sinusoids."""
    x = np.linspace(0, 4 * np.pi, width)
    y = np.linspace(0, 3 * np.pi, height)
    X, Y = np.meshgrid(x, y)

    # Multiple frequency components for rich texture
    pattern = (
        128
        + 50 * np.sin(X) * np.cos(Y)
        + 30 * np.cos(2 * X + 0.5) * np.sin(1.5 * Y)
        + 20 * np.sin(3 * X - 0.3) * np.cos(2.5 * Y + 0.7)
    )

    clipped: NDArray[Any] = np.clip(pattern, 0, 255)
    return clipped.astype(np.uint8)


def apply_motion(frame: np.ndarray, dx: float, dy: float) -> NDArray[np.uint8]:
    """Apply sub-pixel motion using bilinear interpolation."""
    from scipy.ndimage import shift

    # Negative because pattern moves, not viewport
    shifted: NDArray[Any] = shift(frame, (dy, dx), order=1, mode="constant", cval=128)
    return shifted.astype(np.uint8)


def main() -> None:
    """Generate test frames with smooth patterns."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--displacement-x", type=float, default=2.0)
    parser.add_argument("--displacement-y", type=float, default=0.0)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=240)
    parser.add_argument("--output-dir", type=str, default="tb/test_frames")
    parser.add_argument(
        "--use-synthetic",
        action="store_true",
        help="Use synthetic pattern (for debug)",
    )

    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Generating {args.width}x{args.height} test frames...")
    print(f"Motion vector: ({args.displacement_x}, {args.displacement_y}) pixels")
    print(f"Pattern type: {'Smooth synthetic' if args.use_synthetic else 'Natural'}")

    # Generate base pattern
    if args.use_synthetic:
        frame_0 = generate_smooth_synthetic(args.width, args.height)
    else:
        frame_0 = generate_natural_pattern(args.width, args.height)

    # Apply motion to create frame 1
    frame_1 = apply_motion(frame_0, args.displacement_x, args.displacement_y)

    # Save as binary
    frame_0.tofile(output_dir / "frame_00.bin")
    frame_1.tofile(output_dir / "frame_01.bin")

    # Save as .mem for Verilog
    with open(output_dir / "frame_00.mem", "w") as f:
        for val in frame_0.flatten():
            f.write(f"{val:02x}\n")

    with open(output_dir / "frame_01.mem", "w") as f:
        for val in frame_1.flatten():
            f.write(f"{val:02x}\n")

    print(f"\nSaved: {output_dir}/frame_00.bin")
    print(f"Saved: {output_dir}/frame_01.bin")
    print(f"Saved: {output_dir}/frame_00.mem")
    print(f"Saved: {output_dir}/frame_01.mem")

    # Statistics
    print("\nFrame statistics:")
    print(f"  Mean intensity: {np.mean(frame_0):.1f}")
    print(f"  Std dev: {np.std(frame_0):.1f}")
    print(f"  Min/Max: {np.min(frame_0)}/{np.max(frame_0)}")


if __name__ == "__main__":
    main()
