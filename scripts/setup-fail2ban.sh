#!/bin/bash
#
# Fail2ban Configuration Deployment Script
# Copies jail.local and filter configurations to the fail2ban container config directory
#
# Usage: ./scripts/setup-fail2ban.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Deploying fail2ban configuration..."

# Check if source files exist
if [ ! -f "./fail2ban/jail.local" ]; then
    echo -e "${RED}Error: ./fail2ban/jail.local not found${NC}"
    exit 1
fi

if [ ! -d "./fail2ban/filters" ]; then
    echo -e "${RED}Error: ./fail2ban/filters directory not found${NC}"
    exit 1
fi

# Check if fail2ban config directory exists
if [ ! -d "./configs/fail2ban/fail2ban" ]; then
    echo -e "${YELLOW}Warning: ./configs/fail2ban/fail2ban directory not found${NC}"
    echo "Creating directory structure..."
    mkdir -p ./configs/fail2ban/fail2ban/filter.d
fi

# Copy jail.local
echo "Copying jail.local..."
cp ./fail2ban/jail.local ./configs/fail2ban/fail2ban/jail.local

# Copy filters
echo "Copying filters..."
mkdir -p ./configs/fail2ban/fail2ban/filter.d
cp ./fail2ban/filters/*.conf ./configs/fail2ban/fail2ban/filter.d/

# Restart fail2ban container
echo "Restarting fail2ban container..."
docker compose restart fail2ban

# Wait for container to start
echo "Waiting for fail2ban to start..."
sleep 5

# Verify jails are active
echo ""
echo "Checking fail2ban status..."
docker exec fail2ban fail2ban-client status

echo ""
echo -e "${GREEN}Fail2ban configuration deployed successfully!${NC}"
echo ""
echo "To check specific jail status:"
echo "  docker exec fail2ban fail2ban-client status <jail-name>"
echo ""
echo "To test filter patterns:"
echo "  docker exec fail2ban fail2ban-regex /remotelogs/radarr/radarr.txt /config/fail2ban/filter.d/radarr.conf"
