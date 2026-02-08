#!/bin/bash
# copy_files.sh

# Script to copy content of .py, .sv, .yaml, and .md files with filenames as headers
# Usage: ./copy_files.sh [directory] [output_file]

# Set default values
SOURCE_DIR="${1:-.}" # Use current directory if no argument provided
OUTPUT_FILE="${2:-combined_files.txt}" # Default output filename

# Clear the output file
> "$OUTPUT_FILE"

echo "Collecting files from: $SOURCE_DIR"
echo "Output file: $OUTPUT_FILE"
echo "----------------------------------------"

# Find all matching files, excluding .direnv, .venv, and prj folders
find "$SOURCE_DIR" -type f \
    \( -name "*.py" -o -name "*.sh" -o -name "*.sv" -o -name "*.xdc" -o -name "*.tcl" -o -name "*.yaml" -o -name "*.yml" -o -name "*.md" \) \
    -not -path "*/.direnv/*" \
    -not -path "*/.venv/*" \
    -not -path "*/prj/*" \
    | sort | while read -r file; do

    # Get relative path
    rel_path=$(realpath --relative-to="$SOURCE_DIR" "$file")

    echo "Processing: $rel_path"

    # Add separator and filename header to output
    {
        echo ""
        echo "=================================="
        echo "FILE: $rel_path"
        echo "=================================="
        echo ""
        cat "$file"
        echo ""
    } >> "$OUTPUT_FILE"
done

# Get final count (recount since while loop runs in subshell)
final_count=$(find "$SOURCE_DIR" -type f \
    \( -name "*.py" -o -name "*.sh" -o -name "*.sv" -o -name "*.xdc" -o -name "*.tcl" -o -name "*.yaml" -o -name "*.yml" -o -name "*.md" \) \
    -not -path "*/.direnv/*" \
    -not -path "*/.venv/*" \
    -not -path "*/prj/*" \
    | wc -l)

echo "----------------------------------------"
echo "Completed! Processed $final_count files."
echo "All content saved to: $OUTPUT_FILE"
