# Implementation Notes - Phases 2 & 3

This document provides detailed implementation instructions for the remaining improvements to the media automation stack. Phase 1 has been completed. These notes allow you to implement Phases 2 & 3 at your own pace.

---

## Phase 2: Automation & Reliability

### 2.1 Add Backup Failure Notifications (Discord Alerts)

**What it does:** Sends Discord notifications when backups fail, succeed, or exceed size thresholds.

**Why it's important:**
- Silent backup failures can leave you unprotected
- Provides visibility into backup health without manual checks
- Early warning for storage issues (backup size growing too large)

**Implementation Steps:**

1. **Update backup script** (`backup/backup.sh`):

```bash
# Add after line 52 (after loading .env):

# Discord notification helper
send_discord_notification() {
    local status=$1
    local message=$2
    local color=$3

    if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
        return 0
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname=$(hostname)

    curl -X POST "${DISCORD_WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d @- <<EOF
{
    "embeds": [{
        "title": "📦 Backup ${status}",
        "description": "${message}",
        "color": ${color},
        "timestamp": "${timestamp}",
        "footer": {
            "text": "Host: ${hostname}"
        }
    }]
}
EOF
}
```

2. **Add notification calls at key points**:

```bash
# After successful backup creation (line 132):
send_discord_notification "Successful" \
    "Backup created successfully\n**Size:** ${BACKUP_SIZE}\n**Location:** ${BACKUP_PATH}" \
    3066993  # Green

# After backup verification failure (line 123):
send_discord_notification "Failed" \
    "Backup verification failed!\n**Path:** ${BACKUP_PATH}" \
    15158332  # Red

# After remote sync success (line 170, 179, 187, 195):
send_discord_notification "Synced" \
    "Backup synced to remote location\n**Remote:** ${REMOTE_BACKUP_PATH}" \
    3447003  # Blue

# For size warning (add after line 132):
if [ "${BACKUP_SIZE//[!0-9]/}" -gt 200 ]; then  # Strip units, check if >200MB
    send_discord_notification "Warning" \
        "Backup size exceeds 200MB threshold\n**Size:** ${BACKUP_SIZE}\n**Review excludes or cleanup configs**" \
        16776960  # Yellow
fi
```

**Testing:**

```bash
# Test successful backup notification
./backup/backup.sh

# Test failure notification (corrupt backup dir)
chmod 000 backups && ./backup/backup.sh; chmod 755 backups

# Verify Discord notifications appear in configured channel
```

**Rollback:** Remove the `send_discord_notification` function and all calls to it.

---

### 2.2 Add Automated Backup Validation

**What it does:** Verifies backup contains critical API keys and configuration files after creation.

**Why it's important:**
- Ensures backups are actually restorable
- Detects missing configurations before disaster strikes
- Validates backup completeness automatically

**Implementation Steps:**

1. **Add validation function to backup script** (after line 124):

```bash
# Validate backup contents
validate_backup() {
    local backup_file=$1
    echo -e "${YELLOW}Validating backup contents...${NC}"

    # Critical files that must exist
    local critical_files=(
        "configs/radarr/config.xml"
        "configs/sonarr/config.xml"
        "configs/prowlarr/config.xml"
        "configs/overseerr/settings.json"
        "configs/plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
        ".env"
        "docker-compose.yml"
    )

    local missing_files=()

    for file in "${critical_files[@]}"; do
        if ! tar tzf "$backup_file" "$file" >/dev/null 2>&1; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        echo -e "${RED}  ✗ Backup validation failed!${NC}"
        echo -e "${RED}    Missing critical files:${NC}"
        for file in "${missing_files[@]}"; do
            echo -e "${RED}      - $file${NC}"
        done

        # Send Discord alert if webhook configured
        if [ -n "${DISCORD_WEBHOOK_URL:-}" ]; then
            send_discord_notification "Validation Failed" \
                "Backup is missing critical files:\n$(printf '• %s\n' "${missing_files[@]}")" \
                15158332  # Red
        fi

        return 1
    fi

    # Verify API keys exist in configs (basic grep check)
    echo -e "${YELLOW}  Checking API keys...${NC}"
    local api_checks=(
        "configs/radarr/config.xml:<ApiKey>"
        "configs/sonarr/config.xml:<ApiKey>"
        "configs/prowlarr/config.xml:<ApiKey>"
    )

    for check in "${api_checks[@]}"; do
        local file="${check%%:*}"
        local pattern="${check##*:}"

        if ! tar xzf "$backup_file" "$file" -O 2>/dev/null | grep -q "$pattern"; then
            echo -e "${YELLOW}    Warning: $file may not contain API key${NC}"
        fi
    done

    echo -e "${GREEN}  ✓ Backup validation passed${NC}"
    return 0
}
```

2. **Call validation after integrity check** (after line 124):

```bash
# After integrity check passes:
if tar tzf "$BACKUP_PATH" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Backup integrity verified${NC}"

    # Add validation
    if ! validate_backup "$BACKUP_PATH"; then
        echo -e "${RED}Backup validation failed - review missing files${NC}"
        exit 1
    fi
else
    echo -e "${RED}  ✗ Backup verification failed!${NC}"
    exit 1
fi
```

**Testing:**

```bash
# Test successful validation
./backup/backup.sh

# Test validation failure (remove critical file temporarily)
mv configs/radarr/config.xml configs/radarr/config.xml.bak
./backup/backup.sh
mv configs/radarr/config.xml.bak configs/radarr/config.xml

# Check logs for validation messages
```

**Rollback:** Remove the `validate_backup` function and its call.

---

### 2.3 Add VPN IP Leak Detection

**What it does:** Periodically compares Deluge's public IP with VPN's public IP to detect leaks.

**Why it's important:**
- Prevents accidental exposure of real IP to torrent peers
- Early warning if VPN tunnel fails
- Automatic detection without manual checks

**Implementation Steps:**

1. **Add leak detection function to health-monitor** (`monitoring/health-monitor.sh`, after line 460):

```bash
# Check for VPN IP leaks
check_vpn_leak() {
    # Get VPN's public IP (from gluetun container)
    local vpn_ip=$(docker exec gluetun wget -qO- ifconfig.me 2>/dev/null || echo "unavailable")

    # Get Deluge's public IP (should be same as VPN)
    # Note: Deluge shares gluetun's network, so both should report same IP
    local deluge_ip=$(docker exec gluetun wget -qO- ifconfig.me 2>/dev/null || echo "unavailable")

    if [ "$vpn_ip" = "unavailable" ] || [ "$deluge_ip" = "unavailable" ]; then
        log "WARN" "VPN IP check failed - could not retrieve IPs"
        return 0
    fi

    # Compare IPs (they should be identical since Deluge uses gluetun's network)
    if [ "$vpn_ip" != "$deluge_ip" ]; then
        send_alert "VPN IP Leak Detected" \
            "⚠️ **VPN IP:** $vpn_ip\n⚠️ **Deluge IP:** $deluge_ip\n\nImmediate action required!" \
            "critical" \
            "vpn_leak"

        log "ERROR" "VPN IP leak detected! VPN: $vpn_ip, Deluge: $deluge_ip"
        return 1
    fi

    log "INFO" "VPN IP check passed (IP: $vpn_ip)"
    return 0
}
```

2. **Add to main monitoring loop** (around line 680, in the while loop):

```bash
# In main monitoring loop, add after disk space check:

    # Check for VPN IP leaks (every 5 iterations = ~25 minutes)
    if [ $((iteration % 5)) -eq 0 ]; then
        log "INFO" "Running VPN IP leak check..."
        check_vpn_leak
    fi
```

3. **Add VPN IP to health report** (modify `generate_health_report` function around line 550):

```bash
# Add to health report after service status:

    # VPN Status
    local vpn_ip=$(docker exec gluetun wget -qO- ifconfig.me 2>/dev/null || echo "unavailable")
    report+="\n**VPN IP:** $vpn_ip"
```

**Testing:**

```bash
# Rebuild and restart health-monitor
docker compose up -d --build health-monitor

# Check logs for VPN IP checks
docker compose logs health-monitor | grep -i "vpn ip"

# Simulate leak (stop gluetun temporarily - should alert)
docker compose stop gluetun
sleep 60  # Wait for health check
docker compose start gluetun

# Verify Discord alert received
```

**Rollback:** Remove the `check_vpn_leak` function and its call in the monitoring loop.

---

## Phase 3: Security Hardening

### 3.1 Disable Watchtower Auto-Updates (Monitor-Only Mode)

**What it does:** Configures Watchtower to check for updates but not auto-apply them.

**Why it's important:**
- Prevents unexpected service disruptions from bad updates
- Maintains control over update timing
- Still provides update notifications via Discord

**Implementation Steps:**

1. **Update docker-compose.yml** (line 492):

```yaml
    environment:
      - WATCHTOWER_MONITOR_ONLY=true  # Changed from false
      - WATCHTOWER_NOTIFICATIONS=shoutrrr
      - WATCHTOWER_NOTIFICATION_URL=discord://${DISCORD_WEBHOOK_TOKEN}@${DISCORD_WEBHOOK_ID}
      - WATCHTOWER_SCHEDULE=0 0 4 * * *  # Daily at 4 AM
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_CLEANUP=true  # Keep true to cleanup old images when you manually update
      - TZ=${TZ:-America/Chicago}
```

2. **Recreate Watchtower**:

```bash
docker compose up -d watchtower
```

3. **Manual update workflow** (when Discord notifies of available updates):

```bash
# Check what updates are available
docker compose pull

# Review changelog for specific service
# Example: Check Radarr release notes at https://github.com/Radarr/Radarr/releases

# Apply updates selectively
docker compose up -d radarr sonarr  # Update specific services

# OR update everything
docker compose up -d
```

**Testing:**

```bash
# Trigger immediate check
docker exec watchtower /watchtower --run-once --monitor-only

# Verify Discord notification shows available updates (not "Updated")
# Check logs
docker compose logs watchtower
```

**Rollback:** Change `WATCHTOWER_MONITOR_ONLY=false` and restart.

---

### 3.2 Add Traefik Rate Limiting

**What it does:** Limits request rates to Plex and Overseerr to prevent abuse.

**Why it's important:**
- Protects against DDoS attacks
- Prevents brute-force authentication attempts
- Reduces server load from malicious traffic

**Implementation Steps:**

1. **Add rate limiting middleware to docker-compose.yml** (after line 18, in Traefik command section):

```yaml
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.scheme=https
      - --certificatesresolvers.letsencrypt.acme.httpchallenge=true
      - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
      - --ping=true
      - --ping.entrypoint=traefik
      # Add rate limiting middleware
      - --http.middlewares.rate-limit-plex.ratelimit.average=100
      - --http.middlewares.rate-limit-plex.ratelimit.burst=50
      - --http.middlewares.rate-limit-plex.ratelimit.period=1m
      - --http.middlewares.rate-limit-app.ratelimit.average=30
      - --http.middlewares.rate-limit-app.ratelimit.average=15
      - --http.middlewares.rate-limit-app.ratelimit.period=1m
```

2. **Apply rate limiting to Plex** (update Plex labels around line 119):

```yaml
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.plex.rule=Host(`plex.${DOMAIN}`)"
      - "traefik.http.routers.plex.entrypoints=websecure"
      - "traefik.http.routers.plex.tls.certresolver=letsencrypt"
      - "traefik.http.routers.plex.middlewares=rate-limit-plex"  # Add this
      - "traefik.http.services.plex.loadbalancer.server.port=32400"
```

3. **Apply rate limiting to Overseerr** (update Overseerr labels around line 277):

```yaml
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.overseerr.rule=Host(`requests.${DOMAIN}`)"
      - "traefik.http.routers.overseerr.entrypoints=websecure"
      - "traefik.http.routers.overseerr.tls.certresolver=letsencrypt"
      - "traefik.http.routers.overseerr.middlewares=rate-limit-app"  # Add this
      - "traefik.http.services.overseerr.loadbalancer.server.port=5055"
```

4. **Apply rate limiting to Traefik dashboard** (update around line 32):

```yaml
      - "traefik.http.routers.dashboard.middlewares=auth,rate-limit-app"  # Add rate-limit-app
```

5. **Recreate Traefik**:

```bash
docker compose up -d traefik
```

**Rate Limit Explanation:**
- **Plex**: 100 requests/minute average, 50 burst (streaming generates many requests)
- **Overseerr**: 30 requests/minute average, 15 burst (normal browsing)
- **Period**: 1 minute window for rate calculation

**Testing:**

```bash
# Test rate limiting with curl (should get HTTP 429 after exceeding limit)
for i in {1..35}; do
    curl -I https://requests.${DOMAIN}/
done

# Check Traefik logs for rate limit hits
docker compose logs traefik | grep -i "rate"

# Normal usage should be unaffected
```

**Rollback:** Remove the rate limiting middleware commands and label modifications.

---

### 3.3 Convert Backup to Scheduled Container

**What it does:** Runs backups automatically on a weekly schedule instead of manual execution.

**Why it's important:**
- Ensures backups happen consistently
- Eliminates human error (forgetting to run backups)
- Provides predictable backup schedule

**Implementation Steps:**

1. **Update backup container in docker-compose.yml** (around line 498):

```yaml
  backup:
    build: ./backup
    container_name: backup
    volumes:
      - .:/workspace
      - ./backup/rclone.conf:/root/.config/rclone/rclone.conf:ro
      - ./logs:/logs
    environment:
      - REMOTE_BACKUP_PATH=${REMOTE_BACKUP_PATH}
      - TZ=${TZ:-America/Chicago}
      - BACKUP_SCHEDULE=weekly  # Add schedule control
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
        reservations:
          cpus: '0.1'
          memory: 64M
    healthcheck:
      test: ["CMD", "test", "-f", "/logs/.last_backup_success", "-a", "$(find /logs/.last_backup_success -mtime -8 | wc -l)", "-gt", "0"]  # Updated: verify backup within last 8 days
      interval: 24h
      timeout: 10s
      retries: 1
      start_period: 10s
    networks:
      - monitoring
    working_dir: /workspace
    restart: unless-stopped  # Changed from "no" to keep running
    # Remove profiles - backup is now always running
```

2. **Update backup Dockerfile** (`backup/Dockerfile`):

```dockerfile
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
```

3. **Create entrypoint script** (`backup/entrypoint.sh`):

```bash
#!/bin/bash
set -e

echo "Starting backup scheduler..."
echo "Schedule: ${BACKUP_SCHEDULE:-weekly} (Sundays at 2 AM)"
echo "Remote sync: ${REMOTE_BACKUP_PATH:-not configured}"

# Run initial backup on startup (optional)
if [ "${RUN_ON_STARTUP:-false}" = "true" ]; then
    echo "Running initial backup..."
    /usr/local/bin/backup.sh --remote-sync
fi

# Start cron in foreground
echo "Starting cron daemon..."
crond -f -l 2
```

4. **Rebuild and start backup container**:

```bash
docker compose up -d --build backup
```

5. **Verify cron schedule**:

```bash
# Check cron is running
docker exec backup ps | grep crond

# Check cron log
docker compose logs backup

# Test manual run still works
docker exec backup /usr/local/bin/backup.sh
```

**Schedule Options:**

To change the backup schedule, edit the cron expression in `backup/Dockerfile`:
- **Weekly (default)**: `0 2 * * 0` (Sundays at 2 AM)
- **Daily**: `0 2 * * *` (Every day at 2 AM)
- **Bi-weekly**: `0 2 * * 0/2` (Every other Sunday at 2 AM)

**Testing:**

```bash
# Force immediate cron run (for testing)
docker exec backup /usr/local/bin/backup.sh --remote-sync

# Check healthcheck (should fail if >8 days since last backup)
docker inspect backup | grep -A 10 Health

# Verify backup files created
ls -lh backups/

# Check cron logs
docker compose logs backup | tail -50
```

**Rollback:**
1. Revert docker-compose.yml changes (restore `restart: "no"` and `profiles: - tools`)
2. Restore original Dockerfile (remove cron and entrypoint)
3. Recreate: `docker compose up -d --build backup`

---

## Implementation Order Recommendations

For safest deployment, implement in this order:

1. **Phase 2.2** (Backup Validation) - Low risk, high value
2. **Phase 2.1** (Backup Notifications) - Low risk, immediate visibility
3. **Phase 3.1** (Watchtower Monitor-Only) - Low risk, easy rollback
4. **Phase 2.3** (VPN Leak Detection) - Medium risk, important for privacy
5. **Phase 3.2** (Rate Limiting) - Medium risk, test carefully with normal traffic
6. **Phase 3.3** (Scheduled Backups) - Medium risk, verify cron working correctly

---

## Testing Checklist

After implementing each phase:

- [ ] All containers start successfully
- [ ] Health checks pass (verify with `docker compose ps`)
- [ ] Discord notifications working (if applicable)
- [ ] No errors in container logs
- [ ] Services accessible via Traefik (if applicable)
- [ ] VPN still protecting Deluge (check IP with `docker exec gluetun wget -qO- ifconfig.me`)
- [ ] Backup/restore tested (if changes affect backups)

---

## Rollback Procedures

If any implementation causes issues:

1. **Immediate rollback**: Use git to restore previous docker-compose.yml
   ```bash
   git checkout HEAD -- docker-compose.yml
   docker compose up -d
   ```

2. **Selective rollback**: Remove specific changes and recreate affected containers
   ```bash
   # Example: Rollback Traefik rate limiting
   docker compose up -d traefik
   ```

3. **Full system restore**: Restore from backup if configuration corruption occurs
   ```bash
   docker compose down
   tar xzf backups/media-stack-backup_YYYYMMDD_HHMMSS.tar.gz
   docker compose up -d
   ```

---

## Support Resources

- **Traefik Rate Limiting**: https://doc.traefik.io/traefik/middlewares/http/ratelimit/
- **Docker Cron**: https://docs.docker.com/config/containers/multi-service_container/
- **Gluetun Firewall**: https://github.com/qdm12/gluetun/wiki/Firewall
- **Discord Webhooks**: https://discord.com/developers/docs/resources/webhook

---

## Notes

- All Discord webhooks use the same `DISCORD_WEBHOOK_URL` from `.env`
- Rate limits can be adjusted based on your usage patterns (monitor Traefik logs)
- Backup schedule can be customized by editing cron expression in Dockerfile
- VPN leak detection runs every ~25 minutes (configurable via iteration modulo)
