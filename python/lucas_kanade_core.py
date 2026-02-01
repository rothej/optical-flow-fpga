# python/lucas_kanade_core.py
"""
Core Lucas-Kanade single-scale implementation.
Shared by both single-scale and pyramidal versions.
"""

from typing import Tuple

import numpy as np
import numpy.typing as npt
from scipy import signal


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
    Ix = signal.convolve2d(frame_avg, sobel_x, mode="same", boundary="symm")
    Iy = signal.convolve2d(frame_avg, sobel_y, mode="same", boundary="symm")

    # Temporal gradient (simple difference)
    It = frame_prev - frame_curr

    return Ix, Iy, It


def lucas_kanade_single_scale(
    frame_prev: npt.NDArray[np.float32],
    frame_curr: npt.NDArray[np.float32],
    window_size: int = 5,
) -> Tuple[npt.NDArray[np.float32], npt.NDArray[np.float32]]:
    """
    Compute optical flow using Lucas-Kanade method (single scale).

    Args:
        frame_prev: Previous frame (grayscale, float32)
        frame_curr: Current frame (grayscale, float32)
        window_size: Size of analysis window (must be odd)

    Returns:
        Tuple of (u, v) flow fields
    """
    # Compute gradients
    Ix, Iy, It = compute_gradients(frame_prev, frame_curr)

    # Compute flow from gradients
    u, v = lucas_kanade_from_gradients(Ix, Iy, It, window_size)

    return u, v


def lucas_kanade_from_gradients(
    Ix: npt.NDArray[np.float32],
    Iy: npt.NDArray[np.float32],
    It: npt.NDArray[np.float32],
    window_size: int = 5,
) -> Tuple[npt.NDArray[np.float32], npt.NDArray[np.float32]]:
    """
    Compute optical flow from pre-computed gradients.

    This is useful when you want to separate gradient computation from flow solving,
    or when gradients are provided externally (e.g., warped frames in pyramidal LK).

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

            # Solve system (with regularization for stability)
            det = A[0, 0] * A[1, 1] - A[0, 1] * A[1, 0]

            # Compute flow where there's sufficient texture
            if abs(det) > 1e-4:
                u[y, x] = (A[1, 1] * b[0] - A[0, 1] * b[1]) / det
                v[y, x] = (A[0, 0] * b[1] - A[0, 1] * b[0]) / det

    return u, v
