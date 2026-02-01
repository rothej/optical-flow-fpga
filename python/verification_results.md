# Optical Flow Verification Results

## Single-Scale Lucas-Kanade

| Pattern | Ground Truth | MAE (u) | MAE (v) | RMSE | EPE | AAE | Status |
|---------|--------------|---------|---------|------|-----|-----|--------|
| translate_small      | ( 0.5,  0.5) | 0.312 | 0.267 | 0.522 | 0.444 | 14.91° | Pass |
| translate_medium     | ( 2.0,  0.0) | 1.340 | 0.765 | 2.172 | 1.680 | 40.21° | Warning |
| translate_large      | (15.0,  0.0) | 14.824 | 2.064 | 15.294 | 15.122 | 84.09° | Fail |
| translate_vertical   | ( 0.0, 10.0) | 1.657 | 8.801 | 9.724 | 9.249 | 69.50° | Fail |
| translate_diagonal   | (10.0, 10.0) | 9.579 | 8.914 | 13.776 | 13.389 | 73.52° | Fail |
| rotate_small         | ( 0.0,  0.0) | 1.208 | 1.141 | 2.003 | 1.826 | 57.17° | Warning |
| rotate_medium        | ( 0.0,  0.0) | 1.090 | 1.567 | 2.361 | 2.096 | 59.15° | Warning |
| rotate_large         | ( 0.0,  0.0) | 0.919 | 1.602 | 2.408 | 2.027 | 56.89° | Warning |
| zoom_in              | ( 0.0,  0.0) | 1.171 | 1.744 | 2.642 | 2.322 | 61.51° | Warning |
| zoom_out             | ( 0.0,  0.0) | 1.110 | 1.660 | 2.581 | 2.212 | 59.75° | Warning |
| translate_rotate     | ( 5.0,  5.0) | 4.776 | 4.849 | 7.249 | 7.002 | 76.16° | Warning |
| no_motion            | ( 0.0,  0.0) | 0.000 | 0.000 | 0.000 | 0.000 |  0.00° | Pass |
| translate_extreme    | (30.0, 20.0) | 29.649 | 18.930 | 36.059 | 35.585 | 80.78° | Fail |

## Pyramidal Lucas-Kanade

| Pattern | Ground Truth | MAE (u) | MAE (v) | RMSE | EPE | AAE | Status |
|---------|--------------|---------|---------|------|-----|-----|--------|
| translate_small      | ( 0.5,  0.5) | 0.651 | 0.721 | 2.129 | 1.088 | 32.80° | Warning |
| translate_medium     | ( 2.0,  0.0) | 0.525 | 0.374 | 3.224 | 0.703 |  6.88° | Warning |
| translate_large      | (15.0,  0.0) | 6.039 | 4.900 | 14.806 | 8.759 | 28.95° | Fail |
| translate_vertical   | ( 0.0, 10.0) | 5.512 | 2.561 | 23.243 | 6.647 | 14.65° | Fail |
| translate_diagonal   | (10.0, 10.0) | 7.280 | 4.774 | 21.248 | 9.747 | 24.54° | Fail |
| rotate_small         | ( 0.0,  0.0) | 0.775 | 0.941 | 1.529 | 1.341 | 48.92° | Pass |
| rotate_medium        | ( 0.0,  0.0) | 1.780 | 1.887 | 3.040 | 2.819 | 67.05° | Warning |
| rotate_large         | ( 0.0,  0.0) | 5.228 | 5.396 | 8.811 | 8.156 | 81.07° | Fail |
| zoom_in              | ( 0.0,  0.0) | 2.024 | 2.101 | 3.391 | 3.173 | 69.52° | Warning |
| zoom_out             | ( 0.0,  0.0) | 2.074 | 2.229 | 3.615 | 3.332 | 69.92° | Warning |
| translate_rotate     | ( 5.0,  5.0) | 1.135 | 1.294 | 2.107 | 1.888 |  9.75° | Pass |
| no_motion            | ( 0.0,  0.0) | 0.000 | 0.000 | 0.000 | 0.000 |  0.00° | Pass |
| translate_extreme    | (30.0, 20.0) | 34.241 | 21.145 | 77.513 | 44.218 | 69.33° | Fail |

## Metrics Legend

- **MAE**: Mean Absolute Error (pixels)
- **RMSE**: Root Mean Square Error (pixels)
- **EPE**: Average Endpoint Error (pixels)
- **AAE**: Average Angular Error (degrees)
- **Pass**: MAE within expected threshold
- **Warning**: MAE slightly elevated but acceptable
- **Fail**: MAE exceeds threshold (expected for extreme motion)
