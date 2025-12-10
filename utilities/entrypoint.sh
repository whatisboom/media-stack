#!/bin/bash
set -e

echo "Starting utilities container..."
echo "  - MCP-Arr server available via: docker exec -i utilities-daemon mcp-arr-server"
echo "  - Compressor running on cron schedule: 0 3 * * *"

# Start crond in background
crond -l 2

# Keep container running
exec tail -f /dev/null
