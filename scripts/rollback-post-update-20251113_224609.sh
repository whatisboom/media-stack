#!/bin/bash
# Docker Image Rollback Script - POST UPDATE
# Created: $(date)
# 
# This script contains the NEW image versions (after update).
# To rollback to PRE-UPDATE versions, use: ./scripts/rollback-20251113_222923.sh
#
# This script is for reference and future rollbacks if needed.

echo "=== POST-UPDATE Image Versions ==="
echo "These are the NEW versions after the 2025-11-13 update:"
echo ""

services=(tautulli homarr watchtower gluetun deluge prowlarr radarr sonarr bazarr traefik plex overseerr fail2ban)

for service in "${services[@]}"; do
    container_name=$(docker compose ps -q $service 2>/dev/null | xargs docker inspect --format='{{.Name}}' 2>/dev/null | sed 's#^/##')
    if [ -n "$container_name" ]; then
        image=$(docker inspect "$container_name" --format='{{.Config.Image}}')
        digest=$(docker inspect "$container_name" --format='{{index .Image}}' | cut -c1-19)
        created=$(docker inspect "$container_name" --format='{{.Created}}')
        echo "Service: $service"
        echo "  Image: $image"
        echo "  Digest: $digest"
        echo "  Updated: $created"
        echo ""
    fi
done

echo "=== To Rollback to Pre-Update Versions ==="
echo "Run: ./scripts/rollback-20251113_222923.sh"
echo ""
echo "=== Current Stack Status ==="
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Image}}"
