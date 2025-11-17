#!/bin/bash
# Docker Image Rollback Script
# Generated: $(date)
# Use this script to rollback to pre-update image versions

echo "=== Docker Image Rollback Script ==="
echo "Current image digests (before update):"
echo ""

services=(tautulli homarr recyclarr watchtower gluetun deluge prowlarr radarr sonarr bazarr traefik plex overseerr fail2ban)

for service in "${services[@]}"; do
    container_name=$(docker compose ps -q $service 2>/dev/null | xargs docker inspect --format='{{.Name}}' 2>/dev/null | sed 's#^/##')
    if [ -n "$container_name" ]; then
        image=$(docker inspect "$container_name" --format='{{.Config.Image}}')
        digest=$(docker inspect "$container_name" --format='{{index .Image}}')
        echo "# $service"
        echo "# Image: $image"
        echo "# Digest: $digest"
        echo "docker tag $digest $image"
        echo ""
    fi
done

echo "=== To rollback a service ==="
echo "1. Run the docker tag command for that service (from above)"
echo "2. Run: docker compose up -d [service-name]"
echo ""
echo "=== To rollback all services ==="
echo "Run all docker tag commands above, then: docker compose up -d"
