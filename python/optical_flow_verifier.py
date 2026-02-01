#!/usr/bin/env python3
# python/optical_flow_verifier.py
"""
Optical Flow Verification Suite.
Runs Lucas-Kanade on test patterns and generates accuracy reports.
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Tuple

import numpy as np
import numpy.typing as npt
import yaml
from flow_metrics import compute_all_metrics
from lucas_kanade_core import lucas_kanade_single_scale
from lucas_kanade_pyramidal import lucas_kanade_pyramidal

# ============================================================================
# Configuration Loading
# ============================================================================


def load_config(config_path: Path) -> dict[str, Any]:
    """Load verification configuration from YAML file."""
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    assert isinstance(config, dict)
    return config


def load_test_suite_index(suite_dir: Path) -> dict[str, Any]:
    """Load test suite index JSON."""
    index_path = suite_dir / "suite_index.json"
    with open(index_path, "r") as f:
        index: dict[str, Any] = json.load(f)
    return index


def load_test_pattern(pattern_dir: Path) -> dict[str, Any]:
    """
    Load a single test pattern (frames + metadata).

    Returns:
        Dictionary with keys:
            - frame_prev: np.ndarray (float32, grayscale)
            - frame_curr: np.ndarray (float32, grayscale)
            - metadata: dict from metadata.json
    """
    # Load metadata
    with open(pattern_dir / "metadata.json", "r") as f:
        metadata = json.load(f)

    # Load frames as uint8, convert to float32
    width = metadata["resolution"]["width"]
    height = metadata["resolution"]["height"]

    frame_prev_u8 = np.fromfile(pattern_dir / "frame_00.bin", dtype=np.uint8)
    frame_curr_u8 = np.fromfile(pattern_dir / "frame_01.bin", dtype=np.uint8)

    frame_prev = frame_prev_u8.reshape((height, width)).astype(np.float32)
    frame_curr = frame_curr_u8.reshape((height, width)).astype(np.float32)

    return {
        "frame_prev": frame_prev,
        "frame_curr": frame_curr,
        "metadata": metadata,
    }


def get_thresholds_for_pattern(pattern_name: str, config: dict) -> tuple[float, float]:
    """Return (pass_threshold, warning_threshold) for pattern."""
    # Find category
    categories = config["pattern_categories"]
    for category, patterns in categories.items():
        if pattern_name in patterns:
            thresholds = config["thresholds"][category]
            return thresholds["mae_pass"], thresholds["mae_warning"]

    # Default to translation if unknown
    print(f"Warning: Unknown pattern '{pattern_name}', using translation thresholds")
    return (
        config["thresholds"]["translation"]["mae_pass"],
        config["thresholds"]["translation"]["mae_warning"],
    )


# ============================================================================
# Test Region Handling
# ============================================================================


def get_test_region_mask(
    shape: Tuple[int, int],
    pattern_type: str,
    center_crop_size: int,
) -> npt.NDArray[np.bool_]:
    """
    Create mask for test region based on pattern type.

    For translation: test entire frame (excluding borders)
    For rotation/zoom: test only center region (where flow is more predictable)

    Args:
        shape: (height, width) of frame
        pattern_type: Pattern name (e.g., 'translate_medium', 'rotate_small')
        center_crop_size: Size of center crop for rotation/zoom patterns

    Returns:
        Boolean mask (True = test this pixel)
    """
    height, width = shape
    mask = np.zeros((height, width), dtype=bool)

    # Determine pattern category
    is_rotation = "rotate" in pattern_type
    is_zoom = "zoom" in pattern_type
    is_combined = "translate_rotate" in pattern_type

    if is_rotation or is_zoom or is_combined:
        # Test only center region (variable flow elsewhere)
        cy, cx = height // 2, width // 2
        half_size = center_crop_size // 2
        y_start = cy - half_size
        y_end = cy + half_size
        x_start = cx - half_size
        x_end = cx + half_size

        mask[y_start:y_end, x_start:x_end] = True
    else:
        # Translation patterns: test entire frame (excluding 10px border)
        border = 10
        mask[border:-border, border:-border] = True

    return mask


# ============================================================================
# Flow Computation
# ============================================================================


def run_single_scale_lk(
    frame_prev: npt.NDArray[np.float32],
    frame_curr: npt.NDArray[np.float32],
    window_size: int,
) -> Tuple[npt.NDArray[np.float32], npt.NDArray[np.float32]]:
    """Run single-scale Lucas-Kanade."""
    return lucas_kanade_single_scale(frame_prev, frame_curr, window_size)


def run_pyramidal_lk(
    frame_prev: npt.NDArray[np.float32],
    frame_curr: npt.NDArray[np.float32],
    pyramid_config: dict[str, Any],
) -> Tuple[npt.NDArray[np.float32], npt.NDArray[np.float32]]:
    """Run pyramidal Lucas-Kanade with specified configuration."""
    return lucas_kanade_pyramidal(
        frame_prev,
        frame_curr,
        num_levels=pyramid_config["levels"],
        window_size=pyramid_config["window_size"],
        num_iterations=pyramid_config["iterations"],
    )


# ============================================================================
# Result Classification
# ============================================================================


def classify_result(
    mae_u: float,
    mae_v: float,
    pattern_type: str,
    config: dict[str, Any],
) -> str:
    """
    Classify result as pass/warning/fail based on MAE.

    Args:
        mae_u: Mean absolute error in horizontal flow
        mae_v: Mean absolute error in vertical flow
        pattern_type: Pattern name to determine threshold category
        config: Threshold configuration dict

    Returns:
        One of: "Pass", "Warning", "Fail"
    """
    mae_pass, mae_warning = get_thresholds_for_pattern(pattern_type, config)

    # Use worst-case MAE (max of u and v)
    mae_max = max(mae_u, mae_v)

    if mae_max <= mae_pass:
        return "Pass"
    elif mae_max <= mae_warning:
        return "Warning"
    else:
        return "Fail"


# ============================================================================
# Verification Runner
# ============================================================================


def verify_pattern(
    pattern_name: str,
    pattern_data: dict[str, Any],
    config: dict[str, Any],
    pyramid_config_name: str = "default",
    verbose: bool = True,
) -> dict[str, Any]:
    """
    Run verification on a single test pattern.

    Returns:
        Results dictionary with metrics and classification
    """
    if verbose:
        print(f"\n{'='*60}")
        print(f"Testing: {pattern_name}")
        print(f"{'='*60}")

    frame_prev = pattern_data["frame_prev"]
    frame_curr = pattern_data["frame_curr"]
    metadata = pattern_data["metadata"]

    # Extract ground truth
    motion_params = metadata["motion_parameters"]
    u_true = motion_params["dx"]
    v_true = motion_params["dy"]

    if verbose:
        print(f"Ground truth: u={u_true:.1f}, v={v_true:.1f} pixels")
        print(f"Description: {motion_params['description']}")

    # Get test region mask
    mask = get_test_region_mask(
        frame_prev.shape,
        pattern_name,
        config["test_region"]["center_crop"],
    )
    num_test_pixels = np.sum(mask)
    if verbose:
        print(f"Test region: {num_test_pixels} pixels")

    # Run single-scale L-K
    if verbose:
        print("\nRunning single-scale Lucas-Kanade...")
    window_size = config["pyramids"]["default"]["window_size"]
    u_single, v_single = run_single_scale_lk(frame_prev, frame_curr, window_size)

    metrics_single = compute_all_metrics(u_single, v_single, u_true, v_true, mask)

    if verbose:
        print(f"  MAE: u={metrics_single['mae_u']:.3f}, v={metrics_single['mae_v']:.3f}")
        print(f"  RMSE: {metrics_single['rmse']:.3f}")
        print(f"  EPE: {metrics_single['epe']:.3f}")
        print(f"  AAE: {metrics_single['aae']:.2f}°")

    # Run pyramidal L-K
    if verbose:
        print(f"\nRunning pyramidal Lucas-Kanade ({pyramid_config_name})...")
    pyramid_config = config["pyramids"][pyramid_config_name]
    u_pyr, v_pyr = run_pyramidal_lk(frame_prev, frame_curr, pyramid_config)

    metrics_pyr = compute_all_metrics(u_pyr, v_pyr, u_true, v_true, mask)

    if verbose:
        print(f"  MAE: u={metrics_pyr['mae_u']:.3f}, v={metrics_pyr['mae_v']:.3f}")
        print(f"  RMSE: {metrics_pyr['rmse']:.3f}")
        print(f"  EPE: {metrics_pyr['epe']:.3f}")
        print(f"  AAE: {metrics_pyr['aae']:.2f}°")

    # Classify results
    status_single = classify_result(
        metrics_single["mae_u"],
        metrics_single["mae_v"],
        pattern_name,
        config,
    )
    status_pyr = classify_result(
        metrics_pyr["mae_u"],
        metrics_pyr["mae_v"],
        pattern_name,
        config,
    )

    if verbose:
        print(f"\nSingle-scale status: {status_single}")
        print(f"Pyramidal status: {status_pyr}")

    # Compile results
    return {
        "pattern_name": pattern_name,
        "ground_truth": {"u": u_true, "v": v_true},
        "num_test_pixels": int(num_test_pixels),
        "single_scale": {
            "metrics": metrics_single,
            "status": status_single,
        },
        "pyramidal": {
            "metrics": metrics_pyr,
            "status": status_pyr,
            "config": pyramid_config_name,
        },
    }


# ============================================================================
# Output Generation
# ============================================================================


def generate_markdown_table(results: list[dict[str, Any]]) -> str:
    """
    Generate markdown table of results.

    Returns:
        Markdown-formatted table as string
    """
    lines = []
    lines.append("# Optical Flow Verification Results\n")
    lines.append("## Single-Scale Lucas-Kanade\n")
    lines.append("| Pattern | Ground Truth | MAE (u) | MAE (v) | RMSE | EPE | AAE | Status |")
    lines.append("|---------|--------------|---------|---------|------|-----|-----|--------|")

    for result in results:
        pattern = result["pattern_name"]
        gt = result["ground_truth"]
        metrics = result["single_scale"]["metrics"]
        status = result["single_scale"]["status"]

        lines.append(
            f"| {pattern:20s} | ({gt['u']:4.1f}, {gt['v']:4.1f}) | "
            f"{metrics['mae_u']:5.3f} | {metrics['mae_v']:5.3f} | "
            f"{metrics['rmse']:5.3f} | {metrics['epe']:5.3f} | "
            f"{metrics['aae']:5.2f}° | {status} |"
        )

    lines.append("\n## Pyramidal Lucas-Kanade\n")
    lines.append("| Pattern | Ground Truth | MAE (u) | MAE (v) | RMSE | EPE | AAE | Status |")
    lines.append("|---------|--------------|---------|---------|------|-----|-----|--------|")

    for result in results:
        pattern = result["pattern_name"]
        gt = result["ground_truth"]
        metrics = result["pyramidal"]["metrics"]
        status = result["pyramidal"]["status"]

        lines.append(
            f"| {pattern:20s} | ({gt['u']:4.1f}, {gt['v']:4.1f}) | "
            f"{metrics['mae_u']:5.3f} | {metrics['mae_v']:5.3f} | "
            f"{metrics['rmse']:5.3f} | {metrics['epe']:5.3f} | "
            f"{metrics['aae']:5.2f}° | {status} |"
        )

    lines.append("\n## Metrics Legend\n")
    lines.append("- **MAE**: Mean Absolute Error (pixels)")
    lines.append("- **RMSE**: Root Mean Square Error (pixels)")
    lines.append("- **EPE**: Average Endpoint Error (pixels)")
    lines.append("- **AAE**: Average Angular Error (degrees)")
    lines.append("- **Pass**: MAE within expected threshold")
    lines.append("- **Warning**: MAE slightly elevated but acceptable")
    lines.append("- **Fail**: MAE exceeds threshold (expected for extreme motion)")

    return "\n".join(lines)


def save_results_json(results: list[dict[str, Any]], output_path: Path) -> None:
    """Save results as JSON for regression testing."""
    output_data = {
        "version": "1.0",
        "timestamp": datetime.now(timezone.utc).isoformat(),  # UTC timestamp
        "patterns": {result["pattern_name"]: result for result in results},
    }

    with open(output_path, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nResults saved: {output_path}")


# ============================================================================
# Visualization (for showcase patterns)
# ============================================================================


def visualize_flow_field(
    u: npt.NDArray[np.float32],
    v: npt.NDArray[np.float32],
    title: str,
    output_path: Path,
    subsample_step: int = 10,
    scale: float = 1.0,
) -> None:
    """
    Create quiver plot of flow field.

    Args:
        u: Horizontal flow component
        v: Vertical flow component
        title: Plot title
        output_path: Where to save
        subsample_step: Arrow spacing (pixels)
        scale: Arrow scale factor
    """
    import matplotlib.pyplot as plt

    height, width = u.shape

    # Subsample for visualization
    y_coords, x_coords = np.mgrid[
        subsample_step:height:subsample_step,
        subsample_step:width:subsample_step,
    ]

    u_sub = u[subsample_step:height:subsample_step, subsample_step:width:subsample_step]
    v_sub = v[subsample_step:height:subsample_step, subsample_step:width:subsample_step]
    magnitude = np.sqrt(u_sub**2 + v_sub**2)

    fig, ax = plt.subplots(figsize=(12, 9))

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
    ax.set_ylim(height, 0)
    ax.set_title(title)
    ax.set_xlabel("X (pixels)")
    ax.set_ylabel("Y (pixels)")

    plt.colorbar(ax.collections[0], ax=ax, label="Flow Magnitude (pixels)")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close()


def visualize_error_heatmap(
    u_pred: npt.NDArray[np.float32],
    v_pred: npt.NDArray[np.float32],
    u_true: float,
    v_true: float,
    title: str,
    output_path: Path,
    vmax: float = 5.0,
) -> None:
    """
    Create heatmap of flow error magnitude.

    Args:
        u_pred: Predicted horizontal flow
        v_pred: Predicted vertical flow
        u_true: Ground truth horizontal flow
        v_true: Ground truth vertical flow
        title: Plot title
        output_path: Where to save
        vmax: Maximum value for colormap
    """
    import matplotlib.pyplot as plt

    error_u = u_pred - u_true
    error_v = v_pred - v_true
    error_magnitude = np.sqrt(error_u**2 + error_v**2)

    fig, ax = plt.subplots(figsize=(12, 9))

    im = ax.imshow(error_magnitude, cmap="hot", vmin=0, vmax=vmax, interpolation="nearest")
    ax.set_title(title)
    ax.set_xlabel("X (pixels)")
    ax.set_ylabel("Y (pixels)")
    ax.set_aspect("equal")

    plt.colorbar(im, ax=ax, label="Error Magnitude (pixels)")
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close()


def generate_visualizations(
    pattern_name: str,
    pattern_data: dict[str, Any],
    u_single: npt.NDArray[np.float32],
    v_single: npt.NDArray[np.float32],
    u_pyr: npt.NDArray[np.float32],
    v_pyr: npt.NDArray[np.float32],
    output_dir: Path,
    config: dict[str, Any],
) -> None:
    """
    Generate all visualizations for a showcase pattern.

    Creates:
        - Flow field quiver plots (single-scale and pyramidal)
        - Error heatmaps (single-scale and pyramidal)
    """
    print(f"  Generating visualizations for {pattern_name}...")

    pattern_dir = output_dir / pattern_name
    pattern_dir.mkdir(parents=True, exist_ok=True)

    metadata = pattern_data["metadata"]
    u_true = metadata["motion_parameters"]["dx"]
    v_true = metadata["motion_parameters"]["dy"]

    viz_config = config["visualization"]

    # Flow field plots
    visualize_flow_field(
        u_single,
        v_single,
        f"{pattern_name} - Single-Scale L-K Flow Field",
        pattern_dir / "flow_single.png",
        subsample_step=viz_config["quiver"]["subsample_step"],
        scale=viz_config["quiver"]["scale"],
    )

    visualize_flow_field(
        u_pyr,
        v_pyr,
        f"{pattern_name} - Pyramidal L-K Flow Field",
        pattern_dir / "flow_pyramidal.png",
        subsample_step=viz_config["quiver"]["subsample_step"],
        scale=viz_config["quiver"]["scale"],
    )

    # Error heatmaps
    visualize_error_heatmap(
        u_single,
        v_single,
        u_true,
        v_true,
        f"{pattern_name} - Single-Scale Error",
        pattern_dir / "error_single.png",
        vmax=viz_config["colormap"]["error_range"][1],
    )

    visualize_error_heatmap(
        u_pyr,
        v_pyr,
        u_true,
        v_true,
        f"{pattern_name} - Pyramidal Error",
        pattern_dir / "error_pyramidal.png",
        vmax=viz_config["colormap"]["error_range"][1],
    )

    print(f"  Saved visualizations to {pattern_dir}")


# ============================================================================
# Baseline Comparison for Regression Testing
# ============================================================================


def load_baseline(baseline_path: Path) -> dict[str, Any]:
    """Load baseline results for comparison."""
    if not baseline_path.exists():
        print(f"Warning: Baseline file not found: {baseline_path}")
        return {}

    with open(baseline_path, "r") as f:
        data = json.load(f)
        if not isinstance(data, dict):
            print(f"Warning: Baseline file has invalid format: {baseline_path}")
            return {}
        return data


def compare_metrics(
    current: dict[str, float],
    baseline: dict[str, float],
    threshold_percent: float = 10.0,
) -> dict[str, Any]:
    """
    Compare current metrics against baseline.

    Args:
        current: Current metric values
        baseline: Baseline metric values
        threshold_percent: Percentage change threshold for flagging

    Returns:
        Dictionary with comparison results:
            - passed: bool
            - differences: dict of metric differences
            - flags: list of flagged metrics
    """
    differences = {}
    flags = []

    for metric in ["mae_u", "mae_v", "epe"]:  # Key metrics for regression
        curr_val = current.get(metric, 0.0)
        base_val = baseline.get(metric, 0.0)

        if base_val < 1e-6:  # Avoid division by zero
            if curr_val > 1e-6:
                flags.append(f"{metric}: {curr_val:.4f} (baseline was 0)")
            continue

        percent_change = 100.0 * (curr_val - base_val) / base_val
        differences[metric] = {
            "current": curr_val,
            "baseline": base_val,
            "change_percent": percent_change,
        }

        if abs(percent_change) > threshold_percent:
            flags.append(
                f"{metric}: {percent_change:+.1f}% change "
                f"(current={curr_val:.4f}, baseline={base_val:.4f})"
            )

    return {
        "passed": len(flags) == 0,
        "differences": differences,
        "flags": flags,
    }


def compare_against_baseline(
    results: list[dict[str, Any]],
    baseline_path: Path,
    threshold_percent: float = 10.0,
) -> bool:
    """
    Compare verification results against baseline.

    Returns:
        True if all tests pass regression check, False otherwise
    """
    print("\n" + "=" * 60)
    print("Regression Testing: Comparing Against Baseline")
    print("=" * 60)

    baseline = load_baseline(baseline_path)

    if not baseline:
        print("No baseline found. Run with --update-baseline to create one.")
        return True  # Don't fail on missing baseline

    baseline_patterns = baseline.get("patterns", {})
    all_passed = True
    flagged_patterns = []

    for result in results:
        pattern_name = result["pattern_name"]

        if pattern_name not in baseline_patterns:
            print(f"\n  {pattern_name}: Not in baseline (skipping)")
            continue

        baseline_result = baseline_patterns[pattern_name]

        # Compare single-scale
        print(f"\n{pattern_name} (Single-Scale):")
        single_comparison = compare_metrics(
            result["single_scale"]["metrics"],
            baseline_result["single_scale"]["metrics"],
            threshold_percent,
        )

        if single_comparison["passed"]:
            print("  Pass")
        else:
            print("  Regression detected:")
            for flag in single_comparison["flags"]:
                print(f"    - {flag}")
            all_passed = False
            flagged_patterns.append((pattern_name, "single-scale", single_comparison["flags"]))

        # Compare pyramidal
        print(f"{pattern_name} (Pyramidal):")
        pyr_comparison = compare_metrics(
            result["pyramidal"]["metrics"],
            baseline_result["pyramidal"]["metrics"],
            threshold_percent,
        )

        if pyr_comparison["passed"]:
            print("  Pass")
        else:
            print("  Regression detected:")
            for flag in pyr_comparison["flags"]:
                print(f"    - {flag}")
            all_passed = False
            flagged_patterns.append((pattern_name, "pyramidal", pyr_comparison["flags"]))

    # Summary
    print("\n" + "=" * 60)
    if all_passed:
        print("All patterns pass regression check")
    else:
        print(f"Regression detected in {len(flagged_patterns)} test(s)")
        print("\nFlagged patterns:")
        for pattern, method, flags in flagged_patterns:
            print(f"  - {pattern} ({method}):")
            for flag in flags:
                print(f"      {flag}")

    print("=" * 60)

    return all_passed


def update_baseline(results: list[dict[str, Any]], baseline_path: Path) -> None:
    """Update baseline with current results."""
    baseline_data = {
        "version": "1.0",
        "timestamp": datetime.now().isoformat(),
        "patterns": {result["pattern_name"]: result for result in results},
    }

    baseline_path.parent.mkdir(parents=True, exist_ok=True)

    with open(baseline_path, "w") as f:
        json.dump(baseline_data, f, indent=2)

    print(f"\nBaseline updated: {baseline_path}")


# ============================================================================
# Main Entry Point
# ============================================================================


def main() -> None:
    """Main verification script."""
    parser = argparse.ArgumentParser(
        description="Verify optical flow implementations against test suite"
    )
    parser.add_argument(
        "--config",
        type=str,
        default="python/verification_config.yaml",
        help="Path to verification config YAML",
    )
    parser.add_argument(
        "--pattern",
        type=str,
        nargs="+",
        help="Specific pattern(s) to test (default: all)",
    )
    parser.add_argument(
        "--pyramid-config",
        type=str,
        default="default",
        help="Pyramid configuration to use (default, shallow, deep, etc.)",
    )
    parser.add_argument(
        "--no-visualizations",
        action="store_true",
        help="Skip generating visualization plots",
    )
    parser.add_argument(
        "--compare-baseline",
        action="store_true",
        help="Compare results against baseline for regression testing",
    )
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="Update baseline with current results",
    )
    parser.add_argument(
        "--regression-threshold",
        type=float,
        default=10.0,
        help="Percentage threshold for flagging regressions (default: 10%%)",
    )

    args = parser.parse_args()

    # Load configuration
    config_path = Path(args.config)
    if not config_path.exists():
        print(f"Error: Config file not found: {config_path}")
        return

    config = load_config(config_path)
    print("=" * 60)
    print("Optical Flow Verification Suite")
    print("=" * 60)
    print(f"Config: {config_path}")
    print(f"Pyramid config: {args.pyramid_config}")

    # Load test suite
    suite_dir = Path(config["test_suite_dir"])
    if not suite_dir.exists():
        print(f"\nError: Test suite not found: {suite_dir}")
        print("Run generate_test_suite.py first to create test patterns.")
        return

    suite_index = load_test_suite_index(suite_dir)
    print(f"Test suite: {suite_dir}")
    print(f"Patterns available: {len(suite_index['patterns'])}")

    # Determine which patterns to test
    if args.pattern:
        patterns_to_test = args.pattern
        # Validate pattern names
        available = set(suite_index["patterns"].keys())
        for p in patterns_to_test:
            if p not in available:
                print(f"Warning: Pattern '{p}' not found in suite")
                print(f"Available patterns: {', '.join(sorted(available))}")
                return
    else:
        patterns_to_test = list(suite_index["patterns"].keys())

    print(f"Testing {len(patterns_to_test)} patterns\n")

    # Run verification on each pattern
    all_results = []

    for pattern_name in patterns_to_test:
        pattern_dir = suite_dir / pattern_name

        # Load pattern data
        pattern_data = load_test_pattern(pattern_dir)

        # Run verification
        result = verify_pattern(
            pattern_name,
            pattern_data,
            config,
            pyramid_config_name=args.pyramid_config,
            verbose=True,
        )

        all_results.append(result)

        # Generate visualizations for showcase patterns
        if not args.no_visualizations:
            showcase_patterns = config["visualization"]["showcase_patterns"]
            if pattern_name in showcase_patterns:
                # Re-run L-K to get flow fields (could optimize by saving earlier)
                window_size = config["pyramids"]["default"]["window_size"]
                u_single, v_single = run_single_scale_lk(
                    pattern_data["frame_prev"],
                    pattern_data["frame_curr"],
                    window_size,
                )

                pyramid_config_obj = config["pyramids"][args.pyramid_config]
                u_pyr, v_pyr = run_pyramidal_lk(
                    pattern_data["frame_prev"],
                    pattern_data["frame_curr"],
                    pyramid_config_obj,
                )

                viz_dir = Path(config["output"]["visualizations_dir"])
                generate_visualizations(
                    pattern_name,
                    pattern_data,
                    u_single,
                    v_single,
                    u_pyr,
                    v_pyr,
                    viz_dir,
                    config,
                )

    # Generate outputs
    print("\n" + "=" * 60)
    print("Generating Output Reports")
    print("=" * 60)

    # Markdown table (print to stdout)
    markdown_table = generate_markdown_table(all_results)
    print("\n" + markdown_table)

    # Save markdown to file
    md_output_path = Path(config["output"]["results_markdown"])
    md_output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(md_output_path, "w") as f:
        f.write(markdown_table)
    print(f"\nMarkdown table saved: {md_output_path}")

    # Save JSON for regression testing
    json_output_path = Path(config["output"]["results_json"])
    save_results_json(all_results, json_output_path)

    # Regression testing
    baseline_path = Path("python/verification_baseline.json")

    if args.update_baseline:
        update_baseline(all_results, baseline_path)

    if args.compare_baseline:
        regression_passed = compare_against_baseline(
            all_results,
            baseline_path,
            threshold_percent=args.regression_threshold,
        )

        if not regression_passed:
            print("\n   Regression detected! Review changes before committing.")
            sys.exit(1)  # Fail for CI/CD

    print("\n" + "=" * 60)
    print("Verification Complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
