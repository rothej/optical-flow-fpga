#!/usr/bin/env python3
# scripts/convert_frames.py
"""
Convert .mem files to PNG images for visualization overlay.

Reads frame_00.mem and frame_01.mem hex files and saves as PNG.
"""

from pathlib import Path

import numpy as np
from PIL import Image


def mem_to_image(mem_file: str, width: int, height: int) -> Image.Image:
    """Read .mem file (hex values, one per line) and convert to image."""
    pixels = []

    with open(mem_file, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("//"):
                # Parse hex value
                val = int(line, 16)
                pixels.append(val)

    if len(pixels) != width * height:
        raise ValueError(f"Expected {width*height} pixels, got {len(pixels)}")

    # Reshape to 2D array
    img_array = np.array(pixels, dtype=np.uint8).reshape((height, width))

    return Image.fromarray(img_array, mode="L")


def main() -> None:
    # Configuration
    width = 320
    height = 240
    frames_dir = Path("tb/test_frames")

    # Convert frame_00.mem
    print("Converting frame_00.mem...")
    img0 = mem_to_image(str(frames_dir / "frame_00.mem"), width, height)
    output0 = frames_dir / "frame_00.png"
    img0.save(output0)
    print(f"  Saved: {output0}")

    # Convert frame_01.mem
    print("Converting frame_01.mem...")
    img1 = mem_to_image(str(frames_dir / "frame_01.mem"), width, height)
    output1 = frames_dir / "frame_01.png"
    img1.save(output1)
    print(f"  Saved: {output1}")

    print("\nFrame conversion complete!")


if __name__ == "__main__":
    main()
