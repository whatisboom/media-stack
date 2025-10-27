#!/bin/bash
#
# Entrypoint for health monitor container
# Runs health checks on a schedule using sleep loop
#

set -euo pipefail

# Check interval in seconds (default: 900 = 15 minutes)
CHECK_INTERVAL=${CHECK_INTERVAL:-900}

echo "Starting health monitor..."
echo "Check interval: ${CHECK_INTERVAL} seconds ($(($CHECK_INTERVAL / 60)) minutes)"

# Run initial health check
/usr/local/bin/health-monitor.sh

# Loop forever, running health checks
while true; do
    # Sleep for the configured interval
    sleep "$CHECK_INTERVAL"

    # Run health check
    /usr/local/bin/health-monitor.sh
done
