#!/bin/bash
# scripts/pre_merge_check.sh

# Runs CI/CD steps locally prior to merge

set -e # Exit on error

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "Pre-Merge Verification"
echo "========================================="
echo ""

# Install dependencies
echo "1. Installing dependencies..."
pip install -e .[dev] -q
echo -e "${GREEN}Dependencies installed${NC}"
echo ""

# Generate test suite
echo "2. Generating test suite..."
python python/generate_test_suite.py > /dev/null
if [ -f python/test_suite/suite_index.json ]; then
    NUM_PATTERNS=$(python -c "import json; print(len(json.load(open('python/test_suite/suite_index.json'))['patterns']))")
    echo -e "${GREEN}Test suite generated ($NUM_PATTERNS patterns)${NC}"
else
    echo -e "${RED}Test suite generation failed${NC}"
    exit 1
fi
echo ""

# Run verification
echo "3. Running verification suite..."
python python/optical_flow_verifier.py --no-visualizations > /tmp/verify_output.txt 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Verification passed${NC}"
else
    echo -e "${RED}Verification failed${NC}"
    cat /tmp/verify_output.txt
    exit 1
fi
echo ""

# Check outputs
echo "4. Checking output files..."
test -f python/verification_summary.md && echo -e "${GREEN}verification_summary.md${NC}"
test -f python/verification_results.json && echo -e "${GREEN}verification_results.json${NC}"
echo ""

# Regression test
echo "5. Running regression check..."
python python/optical_flow_verifier.py \
  --compare-baseline \
  --no-visualizations \
  --regression-threshold 10.0 > /tmp/regression_output.txt 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Regression check passed${NC}"
else
    echo -e "${RED}Regression detected${NC}"
    cat /tmp/regression_output.txt
    exit 1
fi
echo ""

# Lint check
echo "6. Running linters..."
flake8 python/ --count --select=E9,F63,F7,F82 --show-source --statistics > /tmp/lint_output.txt 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}No critical lint errors${NC}"
else
    echo -e "${YELLOW}Lint warnings detected (check /tmp/lint_output.txt)${NC}"
fi
echo ""

# Step Git status
echo "9. Checking git status..."
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}  Uncommitted changes:${NC}"
    git status --short
    echo ""
else
    echo -e "${GREEN}Working directory clean${NC}"
fi
echo ""

echo "========================================="
echo -e "${GREEN}ALL PRE-MERGE CHECKS PASSED${NC}"
echo "========================================="
echo ""
