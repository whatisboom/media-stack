#!/bin/bash
set -e

echo "Starting media compressor (run-once mode)..."
echo "CRF: ${COMPRESSION_CRF:-23}"
echo "Preset: ${COMPRESSION_PRESET:-slow}"
echo "Dry run: ${DRY_RUN:-false}"

# Run compression once and exit
cd /app && python compressor.py
