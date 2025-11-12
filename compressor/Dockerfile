FROM python:3.11-alpine

# Install ffmpeg and other dependencies
RUN apk add --no-cache \
    ffmpeg \
    bash \
    dcron

# Create working directory
WORKDIR /app

# Copy requirements and install Python packages
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY compressor.py /app/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create cron job for daily compression (3 AM)
RUN echo "0 3 * * * cd /app && python compressor.py >> /logs/compressor-cron.log 2>&1" > /etc/crontabs/root

ENTRYPOINT ["/entrypoint.sh"]
