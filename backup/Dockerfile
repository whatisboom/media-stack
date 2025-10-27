FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    bash \
    tar \
    gzip \
    rclone \
    dcron \
    tzdata

# Copy backup script and entrypoint
COPY backup.sh /usr/local/bin/backup.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

# Set working directory
WORKDIR /workspace

# Run entrypoint (starts cron daemon)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
