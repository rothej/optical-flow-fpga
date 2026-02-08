# Optical Flow Verification Results

## Single-Scale Lucas-Kanade

| Pattern | Ground Truth | MAE (u) | MAE (v) | RMSE | EPE | AAE | Status |
|---------|--------------|---------|---------|------|-----|-----|--------|
| translate_medium     | ( 2.0,  0.0) | 0.886 | 0.471 | 1.399 | 1.093 | 22.22° | Warning |
| rotate_small         | ( 0.0,  0.0) | 1.084 | 1.076 | 1.830 | 1.680 | 55.47° | Warning |
| translate_extreme    | (30.0, 20.0) | 29.375 | 18.685 | 36.135 | 35.405 | 79.77° | Fail |

## Pyramidal Lucas-Kanade

| Pattern | Ground Truth | MAE (u) | MAE (v) | RMSE | EPE | AAE | Status |
|---------|--------------|---------|---------|------|-----|-----|--------|
| translate_medium     | ( 2.0,  0.0) | 0.550 | 0.403 | 3.434 | 0.742 |  6.91° | Warning |
| rotate_small         | ( 0.0,  0.0) | 0.754 | 0.826 | 1.370 | 1.227 | 47.09° | Pass |
| translate_extreme    | (30.0, 20.0) | 36.122 | 22.051 | 100.350 | 46.567 | 69.07° | Fail |

## Metrics Legend

- **MAE**: Mean Absolute Error (pixels)
- **RMSE**: Root Mean Square Error (pixels)
- **EPE**: Average Endpoint Error (pixels)
- **AAE**: Average Angular Error (degrees)
- **Pass**: MAE within expected threshold
- **Warning**: MAE slightly elevated but acceptable
- **Fail**: MAE exceeds threshold (expected for extreme motion)
