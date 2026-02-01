# scripts/regenerate_flow_plots.sh
#!/bin/bash
# Regenerate all flow visualization plots

set -e  # Exit on error

echo "Regenerating flow visualizations..."

# Generate test frames (15px motion for challenging case)
echo "1. Generating test frames (15px horizontal motion)..."
python python/generate_test_frames_natural.py --displacement-x 15

# Run single-scale L-K
echo "2. Running single-scale Lucas-Kanade..."
python python/lucas_kanade_reference.py

# Run pyramidal L-K with comparison
echo "3. Running pyramidal Lucas-Kanade..."
python python/lucas_kanade_pyramidal.py --compare

echo ""
echo "Done! Plots saved to python/output/"
echo "  - flow_visualization_single_scale.png"
echo "  - flow_comparison.png"
echo "  - pyramid_level_0.png"
echo "  - pyramid_level_1.png"
echo "  - pyramid_level_2.png"
