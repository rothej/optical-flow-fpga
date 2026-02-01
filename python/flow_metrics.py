#!/usr/bin/env python3
# python/flow_metrics.py
"""
Optical flow accuracy metrics.
Standard metrics used in optical flow literature.
"""

from typing import Optional, Tuple

import numpy as np
import numpy.typing as npt


def mean_absolute_error(
    u_pred: npt.NDArray[np.float32],
    v_pred: npt.NDArray[np.float32],
    u_true: float,
    v_true: float,
    mask: Optional[npt.NDArray[np.bool_]] = None,
) -> Tuple[float, float]:
    """
    Compute Mean Absolute Error (MAE) for flow components.

    Args:
        u_pred: Predicted horizontal flow field
        v_pred: Predicted vertical flow field
        u_true: Ground truth horizontal flow (constant)
        v_true: Ground truth vertical flow (constant)
        mask: Optional mask for valid pixels (True = compute, False = ignore)

    Returns:
        Tuple of (mae_u, mae_v)
    """
    if mask is None:
        mask = np.ones_like(u_pred, dtype=bool)

    mae_u = float(np.mean(np.abs(u_pred[mask] - u_true)))
    mae_v = float(np.mean(np.abs(v_pred[mask] - v_true)))

    return mae_u, mae_v


def root_mean_square_error(
    u_pred: npt.NDArray[np.float32],
    v_pred: npt.NDArray[np.float32],
    u_true: float,
    v_true: float,
    mask: Optional[npt.NDArray[np.bool_]] = None,
) -> float:
    """
    Compute Root Mean Square Error (RMSE) of flow magnitude.

    Args:
        u_pred: Predicted horizontal flow field
        v_pred: Predicted vertical flow field
        u_true: Ground truth horizontal flow (constant)
        v_true: Ground truth vertical flow (constant)
        mask: Optional mask for valid pixels

    Returns:
        RMSE in pixels
    """
    if mask is None:
        mask = np.ones_like(u_pred, dtype=bool)

    error_u = u_pred[mask] - u_true
    error_v = v_pred[mask] - v_true
    squared_error = error_u**2 + error_v**2

    return float(np.sqrt(np.mean(squared_error)))


def endpoint_error(
    u_pred: npt.NDArray[np.float32],
    v_pred: npt.NDArray[np.float32],
    u_true: float,
    v_true: float,
    mask: Optional[npt.NDArray[np.bool_]] = None,
) -> float:
    """
    Compute Average Endpoint Error (EPE).

    EPE is the Euclidean distance between predicted and true flow vectors,
    averaged over all pixels. Standard metric in optical flow literature.

    Args:
        u_pred: Predicted horizontal flow field
        v_pred: Predicted vertical flow field
        u_true: Ground truth horizontal flow (constant)
        v_true: Ground truth vertical flow (constant)
        mask: Optional mask for valid pixels

    Returns:
        Average EPE in pixels
    """
    if mask is None:
        mask = np.ones_like(u_pred, dtype=bool)

    error_u = u_pred[mask] - u_true
    error_v = v_pred[mask] - v_true
    epe = np.sqrt(error_u**2 + error_v**2)

    return float(np.mean(epe))


def angular_error(
    u_pred: npt.NDArray[np.float32],
    v_pred: npt.NDArray[np.float32],
    u_true: float,
    v_true: float,
    mask: Optional[npt.NDArray[np.bool_]] = None,
) -> float:
    """
    Compute Average Angular Error (AAE).

    Angular error measures the angle between predicted and true flow vectors
    in 3D space (u, v, 1), used in optical flow benchmarks like Middlebury.

    Args:
        u_pred: Predicted horizontal flow field
        v_pred: Predicted vertical flow field
        u_true: Ground truth horizontal flow (constant)
        v_true: Ground truth vertical flow (constant)
        mask: Optional mask for valid pixels

    Returns:
        Average angular error in degrees
    """
    if mask is None:
        mask = np.ones_like(u_pred, dtype=bool)

    # Convert to 3D vectors (u, v, 1)
    u_pred_3d = u_pred[mask]
    v_pred_3d = v_pred[mask]
    w_pred = np.ones_like(u_pred_3d)

    u_true_arr = np.full_like(u_pred_3d, u_true)
    v_true_arr = np.full_like(v_pred_3d, v_true)
    w_true = np.ones_like(u_true_arr)

    # Check if both ground truth and predictions are near zero
    mag_true = np.sqrt(u_true**2 + v_true**2)
    mag_pred = np.sqrt(u_pred_3d**2 + v_pred_3d**2)
    if mag_true < 1e-6 and np.all(mag_pred < 1e-6):
        return 0.0  # Avoid div/0

    # Normalize vectors
    norm_pred = np.sqrt(u_pred_3d**2 + v_pred_3d**2 + w_pred**2)
    norm_true = np.sqrt(u_true_arr**2 + v_true_arr**2 + w_true**2)

    # Dot product
    dot_product = (u_pred_3d * u_true_arr + v_pred_3d * v_true_arr + w_pred * w_true) / (
        norm_pred * norm_true
    )

    # Clamp to [-1, 1] for numerical stability
    dot_product = np.clip(dot_product, -1.0, 1.0)

    # Angular error in radians -> degrees
    angular_error_rad = np.arccos(dot_product)
    angular_error_deg = np.rad2deg(angular_error_rad)

    return float(np.mean(angular_error_deg))


def compute_all_metrics(
    u_pred: npt.NDArray[np.float32],
    v_pred: npt.NDArray[np.float32],
    u_true: float,
    v_true: float,
    mask: Optional[npt.NDArray[np.bool_]] = None,
) -> dict[str, float]:
    """
    Compute all standard optical flow metrics.

    Args:
        u_pred: Predicted horizontal flow field
        v_pred: Predicted vertical flow field
        u_true: Ground truth horizontal flow
        v_true: Ground truth vertical flow
        mask: Optional mask for valid pixels

    Returns:
        Dictionary with all metrics:
            - mae_u, mae_v: Mean absolute error per component
            - rmse: Root mean square error
            - epe: Average endpoint error
            - aae: Average angular error (degrees)
    """
    mae_u, mae_v = mean_absolute_error(u_pred, v_pred, u_true, v_true, mask)
    rmse = root_mean_square_error(u_pred, v_pred, u_true, v_true, mask)
    epe = endpoint_error(u_pred, v_pred, u_true, v_true, mask)
    aae = angular_error(u_pred, v_pred, u_true, v_true, mask)

    return {
        "mae_u": mae_u,
        "mae_v": mae_v,
        "rmse": rmse,
        "epe": epe,
        "aae": aae,  # angular error in degrees
    }
