#!/bin/bash
set -e

echo "Starting backup scheduler..."
echo "Schedule: ${BACKUP_SCHEDULE:-weekly} (Sundays at 2 AM)"
echo "Remote sync: ${REMOTE_BACKUP_PATH:-not configured}"

# Run initial backup on startup (optional)
if [ "${RUN_ON_STARTUP:-false}" = "true" ]; then
    echo "Running initial backup..."
    /usr/local/bin/backup.sh --remote-sync
fi

# Start cron in foreground
echo "Starting cron daemon..."
crond -f -l 2
