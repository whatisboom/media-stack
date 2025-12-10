FROM alpine:latest

# Set timezone (will be overridden by TZ env var from docker-compose)
ARG TZ=America/Chicago
ENV TZ=${TZ}

# Install required packages including tzdata
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    docker-cli \
    tzdata

# Copy monitoring script
COPY health-monitor.sh /usr/local/bin/health-monitor.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/health-monitor.sh /usr/local/bin/entrypoint.sh

# Create logs directory
RUN mkdir -p /logs

# Run monitoring loop
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
