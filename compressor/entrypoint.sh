#!/bin/bash
set -e

echo "Starting media compressor scheduler..."
echo "Schedule: ${COMPRESSION_SCHEDULE:-0 3 * * *} (Daily at 3 AM)"
echo "CRF: ${COMPRESSION_CRF:-23}"
echo "Preset: ${COMPRESSION_PRESET:-slow}"
echo "Dry run: ${DRY_RUN:-false}"

# Run initial compression on startup (optional)
if [ "${RUN_ON_STARTUP:-false}" = "true" ]; then
    echo "Running initial compression..."
    cd /app && python compressor.py
fi

# Start cron in foreground
echo "Starting cron daemon..."
crond -f -l 2
