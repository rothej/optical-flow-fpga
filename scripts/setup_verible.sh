#!/bin/bash
set -e

VERIBLE_VERSION="v0.0-4051-g9fdb4057"
VERIBLE_DIR=".tools/verible"
VERIBLE_URL="https://github.com/chipsalliance/verible/releases/download/${VERIBLE_VERSION}/verible-${VERIBLE_VERSION}-linux-static-x86_64.tar.gz"

mkdir -p "${VERIBLE_DIR}"

if [ -f "${VERIBLE_DIR}/bin/verible-verilog-lint" ]; then
    echo "Verible already installed at ${VERIBLE_DIR}"
    echo "Version: $(${VERIBLE_DIR}/bin/verible-verilog-lint --version 2>&1 | head -1)"
    echo "To reinstall, remove ${VERIBLE_DIR} and run this script again"
    exit 0
fi

echo "Downloading Verible ${VERIBLE_VERSION}..."
cd "${VERIBLE_DIR}"

if ! wget -q "${VERIBLE_URL}"; then
    echo "Error: Failed to download Verible ${VERIBLE_VERSION}"
    echo "URL attempted: ${VERIBLE_URL}"
    exit 1
fi

echo "Extracting..."
tar -xzf "verible-${VERIBLE_VERSION}-linux-static-x86_64.tar.gz" --strip-components=1
rm "verible-${VERIBLE_VERSION}-linux-static-x86_64.tar.gz"

echo ""
echo "Verible ${VERIBLE_VERSION} installed successfully!"
echo "Binary location: ${VERIBLE_DIR}/bin/verible-verilog-lint"
echo ""
echo "Version info:"
"${VERIBLE_DIR}/bin/verible-verilog-lint" --version 2>&1 | head -1
