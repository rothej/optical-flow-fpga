#!/usr/bin/env python3
# python/generate_test_frames.py
"""
Generate test frames for optical flow verification.
Creates simple patterns with known motion for easy verification.
"""

import argparse
from pathlib import Path
from typing import Tuple

import numpy as np
import numpy.typing as npt


def generate_moving_square(
    width: int = 320,
    height: int = 240,
    square_size: int = 40,
    position_x: int = 50,
    position_y: int = 100,
    displacement_x: int = 2,
    displacement_y: int = 0,
) -> Tuple[npt.NDArray[np.uint8], npt.NDArray[np.uint8]]:
    """
    Generate two frames with a moving textured square on black background.
    Square contains a checkerboard pattern for optical flow texture.

    Args:
        width: Frame width in pixels
        height: Frame height in pixels
        square_size: Size of the square in pixels
        position_x: Initial X position of square (top-left corner)
        position_y: Initial Y position of square (top-left corner)
        displacement_x: Horizontal motion in pixels between frames
        displacement_y: Vertical motion in pixels between frames

    Returns:
        Tuple of (frame0, frame1) as uint8 numpy arrays
    """
    # Create textured square (checkerboard pattern, 4x4 pixel checks)
    check_size = 4
    texture = np.zeros((square_size, square_size), dtype=np.uint8)
    for i in range(0, square_size, check_size):
        for j in range(0, square_size, check_size):
            # Alternate between 180 and 255 for better gradient detection
            if ((i // check_size) + (j // check_size)) % 2 == 0:
                texture[i : i + check_size, j : j + check_size] = 255
            else:
                texture[i : i + check_size, j : j + check_size] = 180

    # Frame 0: Square at initial position
    frame0 = np.zeros((height, width), dtype=np.uint8)
    frame0[position_y : position_y + square_size, position_x : position_x + square_size] = texture

    # Frame 1: Square displaced
    frame1 = np.zeros((height, width), dtype=np.uint8)
    new_x = position_x + displacement_x
    new_y = position_y + displacement_y
    frame1[new_y : new_y + square_size, new_x : new_x + square_size] = texture

    return frame0, frame1


def save_as_mem_file(frame: npt.NDArray[np.uint8], filename: Path) -> None:
    """
    Save frame as .mem file for $readmemh in Verilog.
    Format: One hex byte per line (8-bit grayscale).

    Args:
        frame: 2D numpy array of uint8 pixels
        filename: Output file path
    """
    with open(filename, "w") as f:
        for row in frame:
            for pixel in row:
                f.write(f"{pixel:02x}\n")
    print(f"Saved: {filename} ({frame.shape[0]}x{frame.shape[1]} pixels)")


def save_as_binary(frame: npt.NDArray[np.uint8], filename: Path) -> None:
    """
    Save frame as raw binary file.

    Args:
        frame: 2D numpy array of uint8 pixels
        filename: Output file path
    """
    frame.tofile(filename)
    print(f"Saved: {filename} (binary)")


def main() -> None:
    """Main entry point for test frame generation."""
    parser = argparse.ArgumentParser(description="Generate optical flow test frames")
    parser.add_argument(
        "--output-dir",
        type=str,
        default="tb/test_frames",
        help="Output directory for test frames",
    )
    parser.add_argument("--width", type=int, default=320, help="Frame width in pixels")
    parser.add_argument("--height", type=int, default=240, help="Frame height in pixels")
    parser.add_argument(
        "--displacement-x", type=int, default=2, help="Horizontal displacement in pixels"
    )
    parser.add_argument(
        "--displacement-y", type=int, default=0, help="Vertical displacement in pixels"
    )

    args = parser.parse_args()

    # Create output directory
    output_dir = Path(args.output_dir)
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        print(f"  Failed to create directory: {e}")
        return

    # Generate frames
    print(f"Generating {args.width}x{args.height} test frames...")
    print(f"Motion vector: ({args.displacement_x}, {args.displacement_y}) pixels")

    try:
        frame0, frame1 = generate_moving_square(
            width=args.width,
            height=args.height,
            displacement_x=args.displacement_x,
            displacement_y=args.displacement_y,
        )
        print("  Frames generated successfully")
    except Exception as e:
        print(f"  Failed to generate frames: {e}")
        return

    # Save in .mem format for Verilog
    try:
        save_as_mem_file(frame0, output_dir / "frame_00.mem")
        save_as_mem_file(frame1, output_dir / "frame_01.mem")
    except Exception as e:
        print(f"  Failed to save .mem files: {e}")
        return

    # Also save as binary
    try:
        save_as_binary(frame0, output_dir / "frame_00.bin")
        save_as_binary(frame1, output_dir / "frame_01.bin")
    except Exception as e:
        print(f"✗ Failed to save binary files: {e}")
        return

    # Print statistics
    print("\nFrame statistics:")
    print(f"  Bright pixels (frame 0): {np.sum(frame0 == 255)}")
    print(f"  Bright pixels (frame 1): {np.sum(frame1 == 255)}")
    print(f"  Medium pixels (frame 0): {np.sum(frame0 == 180)}")
    print(f"  Medium pixels (frame 1): {np.sum(frame1 == 180)}")
    print(f"  Expected flow in square region: u={args.displacement_x}, v={args.displacement_y}")


if __name__ == "__main__":
    main()
