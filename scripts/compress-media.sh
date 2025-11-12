#!/bin/bash
set -e

# Media Compressor Manual Trigger Script
# Run compression on-demand instead of waiting for scheduled run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Parse command line arguments
DRY_RUN_FLAG=""
if [ "$1" = "--dry-run" ] || [ "$1" = "-d" ]; then
    DRY_RUN_FLAG="-e DRY_RUN=true"
    echo "Running in DRY RUN mode (no actual changes will be made)"
fi

echo "=========================================="
echo "Media Compressor - Manual Trigger"
echo "=========================================="
echo "Starting compression run..."
echo

# Stop the scheduled container if running
if docker compose ps compressor | grep -q "Up"; then
    echo "Stopping scheduled compressor container..."
    docker compose stop compressor
fi

# Build and run one-time container
echo "Building compressor image..."
docker compose build compressor

echo
echo "Running compression (this may take a while)..."
echo

# Run compressor in one-shot mode (bypass entrypoint to run directly)
docker compose run --rm --entrypoint python $DRY_RUN_FLAG compressor /app/compressor.py

echo
echo "=========================================="
echo "Compression run completed!"
echo "=========================================="
echo

# Restart scheduled container if it was running
if docker compose ps -a compressor | grep -q "Exited"; then
    echo "Restarting scheduled compressor container..."
    docker compose start compressor
fi

echo "Done!"
