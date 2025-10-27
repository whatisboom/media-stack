#!/bin/bash
#
# Backup Service Entrypoint
# Sets up cron daemon for automated backups
#

set -euo pipefail

# Set timezone from environment
export TZ="${TZ:-America/Chicago}"

# Configure cron schedule from environment
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 3 * * 1}"  # Default: Monday 3 AM

# Determine if remote sync should be used
REMOTE_SYNC_FLAG=""
if [ -n "${REMOTE_BACKUP_PATH:-}" ]; then
    REMOTE_SYNC_FLAG="--remote-sync"
    echo "Remote backup configured: ${REMOTE_BACKUP_PATH}"
fi

# Create logs directory
mkdir -p /logs

# Create crontab with backup schedule
echo "${BACKUP_SCHEDULE} /usr/local/bin/backup.sh ${REMOTE_SYNC_FLAG} >> /logs/backup.log 2>&1" > /etc/crontabs/root

# Log startup info
echo "====================================="
echo "Backup Scheduler Started"
echo "====================================="
echo "Current time: $(date)"
echo "Timezone: ${TZ}"
echo "Schedule: ${BACKUP_SCHEDULE}"
echo "Remote sync: ${REMOTE_BACKUP_PATH:-disabled}"
echo "====================================="
echo ""
echo "Cron schedule installed:"
cat /etc/crontabs/root
echo ""
echo "Logs will be written to: /logs/backup.log"
echo ""

# Run backup immediately on first start if requested
if [ "${RUN_ON_STARTUP:-false}" = "true" ]; then
    echo "Running initial backup..."
    /usr/local/bin/backup.sh ${REMOTE_SYNC_FLAG} | tee -a /logs/backup.log
    echo ""
fi

echo "Starting cron daemon (logs: docker compose logs backup)"
echo "Next backup will run per schedule: ${BACKUP_SCHEDULE}"
echo ""

# Start cron in foreground (keeps container running)
# -f = foreground mode
# -l 2 = log level 2 (log starts and ends of cron jobs)
exec crond -f -l 2
