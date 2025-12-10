FROM python:3.11-alpine

# Install Node.js 18 and system dependencies
RUN apk add --no-cache \
    nodejs \
    npm \
    ffmpeg \
    bash \
    dcron

# Install mcp-arr-server globally
RUN npm install -g mcp-arr-server

# Create working directory for utilities
WORKDIR /app

# Copy compressor requirements and install Python packages
COPY requirements.txt /app/compressor/
RUN pip install --no-cache-dir -r /app/compressor/requirements.txt

# Copy compressor application files
COPY compressor.py /app/compressor/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create cron job for daily compression (3 AM)
RUN echo "0 3 * * * cd /app/compressor && python compressor.py >> /logs/compressor-cron.log 2>&1" > /etc/crontabs/root

# Container runs persistently with crond
ENTRYPOINT ["/entrypoint.sh"]
