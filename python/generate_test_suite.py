#!/usr/bin/env python3
# python/generate_test_suite.py
"""
Comprehensive optical flow test pattern generator.

Generates diverse test cases (translation, rotation, zoom) with known ground truth
for verifying optical flow implementations. Uses OpenCV for professional-grade
geometric transformations.

Usage:
    # Generate all default test patterns
    python generate_test_suite.py

    # Generate specific pattern
    python generate_test_suite.py --pattern translate_large

    # Custom pattern
    python generate_test_suite.py --pattern custom --dx 10 --dy 5 --rotation 3
"""

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import cv2
import numpy as np
import numpy.typing as npt
from PIL import Image

# Cache directory for base textures
CACHE_DIR = Path(__file__).parent / "test_data"
CACHED_IMAGE = CACHE_DIR / "mountain_texture.jpg"

# Output directory structure
TEST_SUITE_DIR = Path(__file__).parent / "test_suite"


@dataclass
class MotionParameters:
    """Ground truth motion parameters for a test pattern."""

    name: str
    dx: float = 0.0  # Horizontal translation (pixels)
    dy: float = 0.0  # Vertical translation (pixels)
    rotation: float = 0.0  # Rotation angle (degrees, counter-clockwise)
    scale: float = 1.0  # Zoom factor (1.0 = no zoom)
    description: str = ""

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON export."""
        return asdict(self)


# Predefined test suite covering multiple scenarios
TEST_PATTERNS = {
    # Translation Patterns
    "translate_small": MotionParameters(
        name="translate_small",
        dx=0.5,
        dy=0.5,
        description="Sub-pixel motion (tests fixed-point precision)",
    ),
    "translate_medium": MotionParameters(
        name="translate_medium",
        dx=2.0,
        dy=0.0,
        description="Medium horizontal motion (standard test case)",
    ),
    "translate_large": MotionParameters(
        name="translate_large",
        dx=15.0,
        dy=0.0,
        description="Large motion (challenges single-scale L-K)",
    ),
    "translate_vertical": MotionParameters(
        name="translate_vertical",
        dx=0.0,
        dy=10.0,
        description="Vertical motion test",
    ),
    "translate_diagonal": MotionParameters(
        name="translate_diagonal",
        dx=10.0,
        dy=10.0,
        description="Diagonal motion (tests both components)",
    ),
    # Rotation Patterns (Challenges L-K brightness constancy)
    "rotate_small": MotionParameters(
        name="rotate_small",
        rotation=2.0,
        description="Small rotation (2°) - violates brightness constancy",
    ),
    "rotate_medium": MotionParameters(
        name="rotate_medium",
        rotation=5.0,
        description="Medium rotation (5°) - tests algorithm limits",
    ),
    "rotate_large": MotionParameters(
        name="rotate_large",
        rotation=15.0,
        description="Large rotation (15°) - expected failure for L-K",
    ),
    # Zoom Patterns
    "zoom_in": MotionParameters(
        name="zoom_in",
        scale=1.1,
        description="Zoom in (10% expansion)",
    ),
    "zoom_out": MotionParameters(
        name="zoom_out",
        scale=0.9,
        description="Zoom out (10% contraction)",
    ),
    # Combined Motion
    "translate_rotate": MotionParameters(
        name="translate_rotate",
        dx=5.0,
        dy=5.0,
        rotation=3.0,
        description="Combined translation + rotation",
    ),
    # Edge Cases
    "no_motion": MotionParameters(
        name="no_motion",
        dx=0.0,
        dy=0.0,
        description="Stationary pattern (sanity check - expect zero flow)",
    ),
    "translate_extreme": MotionParameters(
        name="translate_extreme",
        dx=30.0,
        dy=20.0,
        description="Extreme motion (far beyond window size)",
    ),
}


def load_base_texture(width: int = 320, height: int = 240) -> npt.NDArray[np.uint8]:
    """
    Load and resize the base natural texture image.

    Args:
        width: Target width
        height: Target height

    Returns:
        Grayscale uint8 image array

    Raises:
        FileNotFoundError: If base texture doesn't exist
    """
    if not CACHED_IMAGE.exists():
        raise FileNotFoundError(
            f"Base texture not found at {CACHED_IMAGE}. "
            "Please ensure mountain_texture.jpg exists in python/test_data/"
        )

    img = Image.open(CACHED_IMAGE).convert("L")
    img_resized = img.resize((width, height), Image.Resampling.BILINEAR)
    return np.array(img_resized, dtype=np.uint8)


def apply_motion_opencv(
    frame: npt.NDArray[np.uint8], params: MotionParameters
) -> npt.NDArray[np.uint8]:
    """
    Apply geometric transformation using OpenCV's warpAffine.

    Combines translation, rotation, and scaling into a single affine transform.
    Uses bilinear interpolation for sub-pixel accuracy.

    Args:
        frame: Input grayscale image (uint8)
        params: Motion parameters to apply

    Returns:
        Transformed image (same size as input)
    """
    height, width = frame.shape
    center = (width / 2.0, height / 2.0)

    # Build transformation matrix
    # Order: scale -> rotate -> translate
    M = cv2.getRotationMatrix2D(center, params.rotation, params.scale)

    # Add translation (modify the translation column)
    M[0, 2] += params.dx
    M[1, 2] += params.dy

    # Apply transformation
    # - INTER_LINEAR: Bilinear interpolation (sub-pixel accurate)
    # - BORDER_CONSTANT: Fill with gray (128) to match natural edges
    warped = cv2.warpAffine(
        frame,
        M,
        (width, height),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=128,
    )

    return warped.astype(np.uint8)


def generate_test_pattern(
    params: MotionParameters,
    width: int = 320,
    height: int = 240,
    output_dir: Optional[Path] = None,
    save_mem: bool = True,
    save_bin: bool = True,
    save_png: bool = True,
) -> Tuple[npt.NDArray[np.uint8], npt.NDArray[np.uint8]]:
    """
    Generate a single test pattern (frame pair + metadata).

    Args:
        params: Motion parameters defining the test case
        width: Frame width
        height: Frame height
        output_dir: Where to save outputs (None = don't save)
        save_mem: Export .mem files for Verilog $readmemh
        save_bin: Export raw binary files
        save_png: Export PNG visualization

    Returns:
        Tuple of (frame_0, frame_1) as uint8 arrays
    """
    # Load base texture
    frame_0 = load_base_texture(width, height)

    # Apply motion to create frame_1
    frame_1 = apply_motion_opencv(frame_0, params)

    # Save outputs if directory specified
    if output_dir is not None:
        pattern_dir = output_dir / params.name
        pattern_dir.mkdir(parents=True, exist_ok=True)

        # Save metadata (ground truth)
        metadata = {
            "pattern_name": params.name,
            "description": params.description,
            "resolution": {"width": width, "height": height},
            "motion_parameters": params.to_dict(),
            "expected_flow": {
                "u_mean": params.dx if params.rotation == 0 and params.scale == 1.0 else "variable",
                "v_mean": params.dy if params.rotation == 0 and params.scale == 1.0 else "variable",
                "note": "For rotation/zoom, flow varies spatially. Use test regions.",
            },
        }

        with open(pattern_dir / "metadata.json", "w") as f:
            json.dump(metadata, f, indent=2)

        # Binary format (for Python processing)
        if save_bin:
            frame_0.tofile(pattern_dir / "frame_00.bin")
            frame_1.tofile(pattern_dir / "frame_01.bin")

        # Hex memory format (for RTL testbenches)
        if save_mem:
            with open(pattern_dir / "frame_00.mem", "w") as f:
                for val in frame_0.flatten():
                    f.write(f"{val:02x}\n")

            with open(pattern_dir / "frame_01.mem", "w") as f:
                for val in frame_1.flatten():
                    f.write(f"{val:02x}\n")

        # PNG visualization (for documentation/debugging)
        if save_png:
            Image.fromarray(frame_0).save(pattern_dir / "frame_00.png")
            Image.fromarray(frame_1).save(pattern_dir / "frame_01.png")

            # Side-by-side comparison
            comparison = np.hstack([frame_0, frame_1])
            Image.fromarray(comparison).save(pattern_dir / "comparison.png")

        print(f"  Generated: {params.name}")
        print(
            f"    Motion: dx={params.dx:.1f}, dy={params.dy:.1f}, "
            f"rot={params.rotation:.1f}°, scale={params.scale:.2f}"
        )

    return frame_0, frame_1


def generate_full_suite(
    width: int = 320, height: int = 240, output_dir: Optional[Path] = None
) -> None:
    """
    Generate all predefined test patterns.

    Args:
        width: Frame width
        height: Frame height
        output_dir: Output directory (None = TEST_SUITE_DIR)
    """
    if output_dir is None:
        output_dir = TEST_SUITE_DIR

    output_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("Generating Optical Flow Test Suite")
    print("=" * 60)
    print(f"Resolution: {width}x{height}")
    print(f"Output directory: {output_dir}")
    print(f"Number of patterns: {len(TEST_PATTERNS)}")
    print("")

    for pattern_name, params in TEST_PATTERNS.items():
        generate_test_pattern(params, width, height, output_dir)

    # Generate suite index (for test runners)
    suite_index = {
        "suite_name": "Optical Flow Verification Suite",
        "resolution": {"width": width, "height": height},
        "num_patterns": len(TEST_PATTERNS),
        "patterns": {name: params.to_dict() for name, params in TEST_PATTERNS.items()},
    }

    with open(output_dir / "suite_index.json", "w") as f:
        json.dump(suite_index, f, indent=2)

    print("")
    print("=" * 60)
    print("Test Suite Generation Complete")
    print("=" * 60)
    print(f"Generated {len(TEST_PATTERNS)} test patterns")
    print(f"Suite index: {output_dir / 'suite_index.json'}")
    print("")


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Generate optical flow test patterns with known ground truth",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate full test suite
  python generate_test_suite.py

  # Generate specific pattern
  python generate_test_suite.py --pattern translate_large

  # Custom motion
  python generate_test_suite.py --pattern custom --dx 12 --dy 3 --rotation 2

  # List available patterns
  python generate_test_suite.py --list
        """,
    )

    parser.add_argument(
        "--pattern",
        type=str,
        default="all",
        help='Test pattern to generate ("all" or specific name)',
    )
    parser.add_argument("--list", action="store_true", help="List available test patterns")
    parser.add_argument("--width", type=int, default=320, help="Frame width")
    parser.add_argument("--height", type=int, default=240, help="Frame height")
    parser.add_argument("--output-dir", type=str, default=None, help="Output directory")

    # Custom motion parameters
    parser.add_argument("--dx", type=float, default=0.0, help="Custom horizontal translation")
    parser.add_argument("--dy", type=float, default=0.0, help="Custom vertical translation")
    parser.add_argument("--rotation", type=float, default=0.0, help="Custom rotation (degrees)")
    parser.add_argument("--scale", type=float, default=1.0, help="Custom zoom factor")

    args = parser.parse_args()

    # List patterns if requested
    if args.list:
        print("\nAvailable Test Patterns:")
        print("-" * 60)
        for name, params in TEST_PATTERNS.items():
            print(f"{name:25s} - {params.description}")
        print("")
        return

    output_dir = Path(args.output_dir) if args.output_dir else TEST_SUITE_DIR

    # Generate patterns
    if args.pattern == "all":
        generate_full_suite(args.width, args.height, output_dir)

    elif args.pattern == "custom":
        # Generate custom pattern
        params = MotionParameters(
            name="custom",
            dx=args.dx,
            dy=args.dy,
            rotation=args.rotation,
            scale=args.scale,
            description=f"Custom: dx={args.dx}, dy={args.dy}, rot={args.rotation}°",
        )
        print(f"Generating custom pattern: {params.description}")
        generate_test_pattern(params, args.width, args.height, output_dir)
        print(f"Saved to: {output_dir / 'custom'}")

    elif args.pattern in TEST_PATTERNS:
        # Generate specific pattern
        params = TEST_PATTERNS[args.pattern]
        print(f"Generating pattern: {params.name}")
        print(f"  {params.description}")
        generate_test_pattern(params, args.width, args.height, output_dir)
        print(f"Saved to: {output_dir / params.name}")

    else:
        print(f"ERROR: Unknown pattern '{args.pattern}'")
        print("Use --list to see available patterns")
        exit(1)


if __name__ == "__main__":
    main()
