# Optical Flow Verification Results

## Single-Scale Lucas-Kanade

| Pattern | Ground Truth | MAE (u) | MAE (v) | RMSE | EPE | AAE | Status |
|---------|--------------|---------|---------|------|-----|-----|--------|
| translate_small      | ( 0.5,  0.5) | 0.265 | 0.245 | 0.466 | 0.391 | 13.60° | Pass |
| translate_medium     | ( 2.0,  0.0) | 0.886 | 0.471 | 1.399 | 1.093 | 22.22° | Warning |
| translate_large      | (15.0,  0.0) | 14.735 | 2.280 | 15.438 | 15.120 | 82.87° | Fail |
| translate_vertical   | ( 0.0, 10.0) | 2.221 | 8.452 | 9.774 | 9.166 | 67.39° | Fail |
| translate_diagonal   | (10.0, 10.0) | 9.531 | 8.685 | 13.873 | 13.309 | 72.29° | Fail |
| rotate_small         | ( 0.0,  0.0) | 1.084 | 1.076 | 1.830 | 1.680 | 55.47° | Warning |
| rotate_medium        | ( 0.0,  0.0) | 1.285 | 1.391 | 2.332 | 2.092 | 59.65° | Warning |
| rotate_large         | ( 0.0,  0.0) | 1.243 | 1.603 | 2.742 | 2.257 | 58.82° | Warning |
| zoom_in              | ( 0.0,  0.0) | 1.346 | 1.530 | 2.616 | 2.271 | 61.12° | Warning |
| zoom_out             | ( 0.0,  0.0) | 1.362 | 1.538 | 2.801 | 2.299 | 60.40° | Warning |
| translate_rotate     | ( 5.0,  5.0) | 4.589 | 4.834 | 7.285 | 6.881 | 71.27° | Warning |
| no_motion            | ( 0.0,  0.0) | 0.000 | 0.000 | 0.000 | 0.000 |  0.00° | Pass |
| translate_extreme    | (30.0, 20.0) | 29.375 | 18.685 | 36.135 | 35.405 | 79.77° | Fail |

## Pyramidal Lucas-Kanade

| Pattern | Ground Truth | MAE (u) | MAE (v) | RMSE | EPE | AAE | Status |
|---------|--------------|---------|---------|------|-----|-----|--------|
| translate_small      | ( 0.5,  0.5) | 0.638 | 0.628 | 1.821 | 0.997 | 31.18° | Warning |
| translate_medium     | ( 2.0,  0.0) | 0.550 | 0.403 | 3.434 | 0.742 |  6.91° | Warning |
| translate_large      | (15.0,  0.0) | 6.039 | 5.092 | 16.349 | 8.934 | 28.64° | Fail |
| translate_vertical   | ( 0.0, 10.0) | 5.663 | 2.562 | 27.117 | 6.793 | 14.20° | Fail |
| translate_diagonal   | (10.0, 10.0) | 7.774 | 4.803 | 24.808 | 10.223 | 24.54° | Fail |
| rotate_small         | ( 0.0,  0.0) | 0.754 | 0.826 | 1.370 | 1.227 | 47.09° | Pass |
| rotate_medium        | ( 0.0,  0.0) | 1.771 | 1.796 | 2.944 | 2.738 | 66.52° | Warning |
| rotate_large         | ( 0.0,  0.0) | 5.208 | 5.304 | 8.726 | 8.068 | 80.91° | Fail |
| zoom_in              | ( 0.0,  0.0) | 2.013 | 2.038 | 3.330 | 3.114 | 69.03° | Warning |
| zoom_out             | ( 0.0,  0.0) | 2.067 | 2.166 | 3.534 | 3.268 | 69.62° | Warning |
| translate_rotate     | ( 5.0,  5.0) | 1.107 | 1.176 | 1.938 | 1.764 |  9.09° | Pass |
| no_motion            | ( 0.0,  0.0) | 0.000 | 0.000 | 0.000 | 0.000 |  0.00° | Pass |
| translate_extreme    | (30.0, 20.0) | 36.122 | 22.051 | 100.350 | 46.567 | 69.07° | Fail |

## Metrics Legend

- **MAE**: Mean Absolute Error (pixels)
- **RMSE**: Root Mean Square Error (pixels)
- **EPE**: Average Endpoint Error (pixels)
- **AAE**: Average Angular Error (degrees)
- **Pass**: MAE within expected threshold
- **Warning**: MAE slightly elevated but acceptable
- **Fail**: MAE exceeds threshold (expected for extreme motion)
