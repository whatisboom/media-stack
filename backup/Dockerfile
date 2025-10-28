FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    bash \
    tar \
    gzip \
    rclone \
    tzdata

# Copy backup script
COPY backup.sh /usr/local/bin/backup.sh

# Make script executable
RUN chmod +x /usr/local/bin/backup.sh

# Set working directory
WORKDIR /workspace

# Run backup script directly
ENTRYPOINT ["/usr/local/bin/backup.sh"]
CMD ["--remote-sync"]
