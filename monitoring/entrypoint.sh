#!/bin/bash
#
# Entrypoint for health monitor container
# Runs health checks and update checks on schedule
#

set -euo pipefail

# Health check interval in seconds (default: 300 = 5 minutes)
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-300}

echo "Starting health monitor..."
echo "Health check interval: ${HEALTH_CHECK_INTERVAL} seconds ($(($HEALTH_CHECK_INTERVAL / 60)) minutes)"
echo "Update check schedule: daily at 3:45 AM"

# Run initial health check
/usr/local/bin/health-monitor.sh

# Track last update check date
LAST_UPDATE_CHECK_DATE=""

# Loop forever
while true; do
    # Sleep for the configured interval
    sleep "$HEALTH_CHECK_INTERVAL"

    # Run health check
    /usr/local/bin/health-monitor.sh

    # Check if it's time for update check (3:45 AM)
    CURRENT_HOUR=$(date +%H)
    CURRENT_MINUTE=$(date +%M)
    CURRENT_DATE=$(date +%Y-%m-%d)

    if [ "$CURRENT_HOUR" = "03" ] && [ "$CURRENT_MINUTE" -ge 45 ] && [ "$CURRENT_MINUTE" -lt 50 ] && [ "$LAST_UPDATE_CHECK_DATE" != "$CURRENT_DATE" ]; then
        echo "Running scheduled update check..."
        /usr/local/bin/health-monitor.sh --check-updates
        LAST_UPDATE_CHECK_DATE="$CURRENT_DATE"
    fi
done
