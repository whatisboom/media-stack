FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    bash \
    tar \
    gzip \
    curl \
    rclone \
    dcron

# Copy backup script
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create cron job for weekly backups (Sundays at 2 AM)
RUN echo "0 2 * * 0 /usr/local/bin/backup.sh --remote-sync >> /logs/backup-cron.log 2>&1" > /etc/crontabs/root

ENTRYPOINT ["/entrypoint.sh"]
