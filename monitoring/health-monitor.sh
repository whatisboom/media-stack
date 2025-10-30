#!/bin/bash
#
# Health Monitor Script for Media Stack
# Monitors Docker services, VPN connectivity, and disk space
# Sends Discord alerts on failures and recoveries
#

set -euo pipefail

# Configuration
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/health-monitor.log"
STATE_FILE="${LOG_DIR}/.health_state.json"

# Alert configuration from environment variables
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
DISK_SPACE_THRESHOLD="${DISK_SPACE_THRESHOLD:-10}"
ALERT_COOLDOWN="${ALERT_COOLDOWN:-3600}"

# Alert colors for Discord embeds
COLOR_FAILURE=15158332   # Red
COLOR_RECOVERY=5763719   # Green
COLOR_WARNING=16776960   # Yellow
COLOR_INFO=3447003       # Blue

# Verbose mode
VERBOSE=0
CHECK_UPDATES=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        --check-updates)
            CHECK_UPDATES=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-v|--verbose] [--check-updates] [-h|--help]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose       Show detailed output"
            echo "  --check-updates     Check for Docker image updates"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
    if [ "$VERBOSE" -eq 1 ] || [ "$level" = "ERROR" ] || [ "$level" = "WARN" ]; then
        echo "[${level}] ${message}"
    fi
}

# Initialize state file if it doesn't exist
initialize_state() {
    if [ ! -f "$STATE_FILE" ]; then
        log "INFO" "Initializing state file"
        cat > "$STATE_FILE" <<'EOF'
{
  "services": {},
  "vpn": {
    "last_ip": "",
    "last_country": "",
    "last_check": ""
  },
  "disk": {
    "last_available_gb": 0,
    "last_check": ""
  },
  "alerts": {
    "last_failure_alert": 0,
    "last_recovery_alert": 0,
    "last_disk_alert": 0,
    "last_update_alert": 0
  },
  "updates": {
    "last_check": "",
    "pending": {}
  }
}
EOF
    fi
}

# Get previous service state
get_previous_state() {
    local service="$1"
    jq -r ".services.\"${service}\" // \"unknown\"" "$STATE_FILE"
}

# Update service state
update_service_state() {
    local service="$1"
    local state="$2"
    local temp_file=$(mktemp)
    jq ".services.\"${service}\" = \"${state}\"" "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"
}

# Get last alert timestamp
get_last_alert_time() {
    local alert_type="$1"  # failure, recovery, or disk
    jq -r ".alerts.last_${alert_type}_alert // 0" "$STATE_FILE"
}

# Update last alert timestamp
update_last_alert_time() {
    local alert_type="$1"
    local timestamp=$(date +%s)
    local temp_file=$(mktemp)
    jq ".alerts.last_${alert_type}_alert = ${timestamp}" "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"
}

# Check alert cooldown
check_alert_cooldown() {
    local alert_type="$1"
    local last_alert=$(get_last_alert_time "$alert_type")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_alert))

    if [ "$time_diff" -lt "$ALERT_COOLDOWN" ]; then
        log "INFO" "Alert cooldown active for ${alert_type} (${time_diff}s since last alert)"
        return 1
    fi
    return 0
}

# Send Discord alert
send_alert() {
    local subject="$1"
    local body="$2"
    local color="$3"
    local alert_type="$4"  # failure, recovery, or disk

    # Check if Discord webhook is configured
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        log "WARN" "Discord webhook not configured. Skipping alert: $subject"
        return 0
    fi

    # Check alert cooldown
    if ! check_alert_cooldown "$alert_type"; then
        return 0
    fi

    # Escape JSON special characters in body
    local escaped_body=$(echo "$body" | jq -Rs .)

    # Create Discord embed JSON
    local discord_payload=$(cat <<EOF
{
  "username": "Media Stack Monitor",
  "avatar_url": "https://cdn-icons-png.flaticon.com/512/2103/2103633.png",
  "embeds": [{
    "title": "${subject}",
    "description": ${escaped_body},
    "color": ${color},
    "footer": {
      "text": "Media Stack Health Monitor"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)

    # Send to Discord webhook
    log "INFO" "Sending Discord alert: $subject"
    if curl -s -H "Content-Type: application/json" \
        -d "$discord_payload" \
        "$DISCORD_WEBHOOK_URL" > /dev/null; then
        log "INFO" "Alert sent successfully to Discord"
        update_last_alert_time "$alert_type"
    else
        log "ERROR" "Failed to send alert to Discord"
    fi
}

# Check Docker service health
check_docker_health() {
    log "INFO" "Checking Docker service health..."

    local services=(traefik gluetun plex radarr sonarr prowlarr overseerr homarr deluge fail2ban)
    local failed_services=()
    local recovered_services=()

    for service in "${services[@]}"; do
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "no-healthcheck")
        local running_status=$(docker inspect --format='{{.State.Running}}' "$service" 2>/dev/null || echo "false")
        local previous_state=$(get_previous_state "$service")
        local current_state="unknown"

        # Determine current state
        if [ "$running_status" != "true" ]; then
            current_state="stopped"
            log "ERROR" "Service $service is not running"
        elif [ "$health_status" = "unhealthy" ]; then
            current_state="unhealthy"
            log "ERROR" "Service $service is unhealthy"
        elif [ "$health_status" = "starting" ]; then
            current_state="starting"
            log "WARN" "Service $service is still starting"
        elif [ "$health_status" = "healthy" ]; then
            current_state="healthy"
            log "INFO" "Service $service is healthy"
        elif [ "$health_status" = "no-healthcheck" ]; then
            current_state="no-healthcheck"
            log "INFO" "Service $service has no healthcheck (assumed healthy)"
        fi

        # Detect state changes
        if [ "$previous_state" != "unknown" ] && [ "$previous_state" != "$current_state" ]; then
            # State changed
            if [ "$current_state" = "healthy" ] || [ "$current_state" = "no-healthcheck" ]; then
                # Service recovered
                if [ "$previous_state" = "stopped" ] || [ "$previous_state" = "unhealthy" ]; then
                    recovered_services+=("$service ($previous_state → $current_state)")
                    log "INFO" "Service $service recovered: $previous_state → $current_state"
                fi
            elif [ "$current_state" = "stopped" ] || [ "$current_state" = "unhealthy" ]; then
                # Service failed
                if [ "$previous_state" = "healthy" ] || [ "$previous_state" = "no-healthcheck" ]; then
                    failed_services+=("$service ($previous_state → $current_state)")
                    log "ERROR" "Service $service failed: $previous_state → $current_state"
                fi
            fi
        fi

        # Update state
        update_service_state "$service" "$current_state"
    done

    # Send failure alerts
    if [ ${#failed_services[@]} -gt 0 ]; then
        local alert_body="🔴 The following services have failed:

$(printf '%s\n' "${failed_services[@]}")

**Actions:**
\`\`\`bash
# Check logs
docker compose logs -f [service-name]

# Restart service
docker compose restart [service-name]
\`\`\`"

        send_alert "[ALERT] Media Stack: Services Failed" "$alert_body" "$COLOR_FAILURE" "failure"
    fi

    # Send recovery alerts
    if [ ${#recovered_services[@]} -gt 0 ]; then
        local alert_body="✅ The following services have recovered:

$(printf '%s\n' "${recovered_services[@]}")

All affected services are now healthy."

        send_alert "[RECOVERY] Media Stack: Services Restored" "$alert_body" "$COLOR_RECOVERY" "recovery"
    fi

    # Return failure if any services are currently unhealthy
    local current_unhealthy=0
    for service in "${services[@]}"; do
        local state=$(get_previous_state "$service")
        if [ "$state" = "stopped" ] || [ "$state" = "unhealthy" ]; then
            current_unhealthy=1
        fi
    done

    return $current_unhealthy
}

# Check VPN connectivity
check_vpn() {
    log "INFO" "Checking VPN connectivity..."

    # Check if gluetun is running
    if ! docker inspect --format='{{.State.Running}}' gluetun &>/dev/null; then
        log "ERROR" "VPN container (gluetun) is not running"
        send_alert "[ALERT] Media Stack: VPN Container Down" "The gluetun VPN container is not running. Torrent traffic may be exposed!" "$COLOR_FAILURE" "failure"
        return 1
    fi

    # Get public IP from gluetun
    local vpn_ip=$(docker exec gluetun wget -qO- https://api.ipify.org 2>/dev/null || echo "")

    if [ -z "$vpn_ip" ]; then
        log "ERROR" "Failed to get VPN public IP"
        send_alert "[ALERT] Media Stack: VPN Connectivity Issue" "Unable to determine VPN public IP. The VPN connection may be down." "$COLOR_FAILURE" "failure"
        return 1
    fi

    log "INFO" "VPN is connected. Public IP: $vpn_ip"

    # Optional: Check if IP is a NordVPN IP (basic check)
    local vpn_country=$(docker exec gluetun wget -qO- https://ipinfo.io/country 2>/dev/null || echo "")
    if [ -n "$vpn_country" ]; then
        log "INFO" "VPN location: $vpn_country"
    fi

    return 0
}

# Check disk space
check_disk_space() {
    log "INFO" "Checking disk space..."

    local media_disk="/data"

    if [ ! -d "$media_disk" ]; then
        log "ERROR" "Media disk not mounted: $media_disk"
        send_alert "[ALERT] Media Stack: Media Disk Not Mounted" "The media disk ($media_disk) is not accessible. Services may fail." "$COLOR_FAILURE" "failure"
        return 1
    fi

    # Get available space in GB
    local available_space=$(df -k "$media_disk" | tail -1 | awk '{printf "%.0f", $3/1024/1024}')

    log "INFO" "Available disk space: ${available_space}GB"

    if [ "$available_space" -lt "$DISK_SPACE_THRESHOLD" ]; then
        log "WARN" "Low disk space: ${available_space}GB (threshold: ${DISK_SPACE_THRESHOLD}GB)"

        local alert_body="⚠️ Available disk space is low:

**Available:** ${available_space}GB
**Threshold:** ${DISK_SPACE_THRESHOLD}GB
**Location:** $media_disk

**Consider:**
- Removing old/watched media
- Checking for stuck downloads
- Running cleanup scripts"

        send_alert "[WARNING] Media Stack: Low Disk Space" "$alert_body" "$COLOR_WARNING" "disk"
        return 1
    fi

    return 0
}

# Check fail2ban status
check_fail2ban() {
    log "INFO" "Checking fail2ban status..."

    # Check if fail2ban container is running
    if ! docker inspect --format='{{.State.Running}}' fail2ban &>/dev/null; then
        log "ERROR" "fail2ban container is not running"
        return 1
    fi

    # Get ban statistics
    local total_banned=0
    local jail_status=""

    # List all active jails and count banned IPs
    local jails=(radarr sonarr prowlarr overseerr plex)
    for jail in "${jails[@]}"; do
        local banned_count=$(docker exec fail2ban fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned:" | awk '{print $NF}' || echo "0")
        if [ "$banned_count" != "0" ]; then
            total_banned=$((total_banned + banned_count))
            jail_status="${jail_status}\n- ${jail}: ${banned_count} banned IPs"
            log "INFO" "fail2ban jail ${jail}: ${banned_count} banned IPs"
        fi
    done

    # Log ban activity if any IPs are banned
    if [ "$total_banned" -gt 0 ]; then
        log "INFO" "fail2ban has banned $total_banned IPs across all jails"
    else
        log "INFO" "fail2ban is active with no banned IPs"
    fi

    return 0
}

# Fetch changelog from LinuxServer.io API
fetch_linuxserver_changelog() {
    local image_name="$1"  # e.g., "deluge", "radarr"

    log "INFO" "Fetching changelog for LinuxServer.io image: $image_name"

    local api_response=$(curl -sX GET 'https://api.linuxserver.io/api/v1/images?include_config=false&include_deprecated=false')

    if [ -z "$api_response" ]; then
        log "WARN" "Failed to fetch LinuxServer.io API response"
        echo "Unable to fetch changelog"
        return 1
    fi

    local changelog=$(echo "$api_response" | jq -r ".data.repositories.linuxserver | .[] | select(.name == \"$image_name\") | .changelog[0:3] | .[] | \"• \" + .date + \": \" + .desc" 2>/dev/null)

    if [ -z "$changelog" ]; then
        log "WARN" "No changelog found for $image_name"
        echo "No changelog available"
        return 1
    fi

    echo "$changelog"
    return 0
}

# Fetch changelog from GitHub Releases API
fetch_github_changelog() {
    local org_repo="$1"  # e.g., "ajnart/homarr" or "recyclarr/recyclarr"

    log "INFO" "Fetching changelog for GitHub repo: $org_repo"

    # Build curl command with optional GitHub token for increased rate limits
    local curl_cmd="curl -sL"
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_cmd="$curl_cmd -H \"Authorization: token $GITHUB_TOKEN\""
    fi

    local api_response=$(eval "$curl_cmd \"https://api.github.com/repos/$org_repo/releases?per_page=3\"" 2>/dev/null)

    if [ -z "$api_response" ] || echo "$api_response" | jq -e 'type == "object" and .message' > /dev/null 2>&1; then
        log "WARN" "Failed to fetch GitHub releases for $org_repo"
        echo "Unable to fetch changelog"
        return 1
    fi

    local changelog=$(echo "$api_response" | jq -r '.[] | "• " + .tag_name + (if .name and .name != "" and .name != .tag_name then " - " + .name else "" end)' 2>/dev/null | head -3)

    if [ -z "$changelog" ]; then
        log "WARN" "No releases found for $org_repo"
        echo "No changelog available"
        return 1
    fi

    echo "$changelog"
    return 0
}

# Fetch generic changelog message for other registries
fetch_generic_changelog() {
    local image="$1"
    local registry_url="$2"

    echo "Update available - check project page for details"
    if [ -n "$registry_url" ]; then
        echo "Registry: $registry_url"
    fi
    return 0
}

# Get image digest from local Docker
get_local_image_digest() {
    local image="$1"
    docker inspect "$image" --format='{{index .RepoDigests 0}}' 2>/dev/null | cut -d'@' -f2 | cut -c1-12 || echo "unknown"
}

# Get remote image digest without pulling
get_remote_image_digest() {
    local image="$1"
    # Use docker manifest inspect to check remote without pulling
    docker manifest inspect "$image" 2>/dev/null | jq -r '.config.digest // .manifests[0].digest' 2>/dev/null | cut -c1-19 || echo ""
}

# Check for image updates
check_image_updates() {
    log "INFO" "Checking for Docker image updates..."

    # Define services and their images
    declare -A services_images=(
        ["traefik"]="traefik:v3.0|dockerhub|"
        ["gluetun"]="qmcgaw/gluetun|dockerhub|"
        ["plex"]="plexinc/pms-docker|dockerhub|https://www.plex.tv/media-server-downloads/"
        ["tautulli"]="lscr.io/linuxserver/tautulli:latest|linuxserver|tautulli"
        ["radarr"]="lscr.io/linuxserver/radarr:latest|linuxserver|radarr"
        ["sonarr"]="lscr.io/linuxserver/sonarr:latest|linuxserver|sonarr"
        ["bazarr"]="lscr.io/linuxserver/bazarr:latest|linuxserver|bazarr"
        ["overseerr"]="sctx/overseerr:latest|dockerhub|https://overseerr.dev"
        ["homarr"]="ghcr.io/ajnart/homarr:latest|github|ajnart/homarr"
        ["deluge"]="lscr.io/linuxserver/deluge:latest|linuxserver|deluge"
        ["prowlarr"]="lscr.io/linuxserver/prowlarr:latest|linuxserver|prowlarr"
        ["fail2ban"]="lscr.io/linuxserver/fail2ban:latest|linuxserver|fail2ban"
        ["recyclarr"]="ghcr.io/recyclarr/recyclarr:latest|github|recyclarr/recyclarr"
        ["watchtower"]="containrrr/watchtower:latest|dockerhub|https://github.com/containrrr/watchtower"
    )

    local updates_found=0
    local updates_json="{"

    for service in "${!services_images[@]}"; do
        IFS='|' read -r image registry metadata <<< "${services_images[$service]}"

        log "INFO" "Checking $service ($image)"

        # Get local digest
        local local_digest=$(get_local_image_digest "$image")

        # Check if image exists locally
        if [ "$local_digest" = "unknown" ]; then
            log "WARN" "Image $image not found locally, skipping update check"
            continue
        fi

        # Get remote manifest digest without pulling
        log "INFO" "Checking remote manifest for $image"
        local remote_digest=$(get_remote_image_digest "$image")

        if [ -z "$remote_digest" ]; then
            log "WARN" "Failed to get remote digest for $image"
            continue
        fi

        # Truncate remote digest to same length for comparison
        local new_digest=$(echo "$remote_digest" | cut -c1-12)

        # Compare digests
        if [ "$local_digest" != "$new_digest" ]; then
            log "INFO" "Update available for $service: $local_digest → $new_digest"
            updates_found=$((updates_found + 1))

            # Fetch changelog based on registry type
            local changelog=""
            case "$registry" in
                linuxserver)
                    changelog=$(fetch_linuxserver_changelog "$metadata")
                    ;;
                github)
                    changelog=$(fetch_github_changelog "$metadata")
                    ;;
                dockerhub)
                    changelog=$(fetch_generic_changelog "$image" "$metadata")
                    ;;
            esac

            # Build JSON entry (escaping for jq)
            if [ "$updates_found" -gt 1 ]; then
                updates_json="$updates_json,"
            fi

            local escaped_changelog=$(echo "$changelog" | jq -Rs .)
            updates_json="$updates_json\"$service\":{\"image\":\"$image\",\"current\":\"$local_digest\",\"new\":\"$new_digest\",\"changelog\":$escaped_changelog}"
        else
            log "INFO" "No update available for $service"
        fi
    done

    updates_json="$updates_json}"

    # If updates found, send notification
    if [ "$updates_found" -gt 0 ]; then
        log "INFO" "Found $updates_found update(s)"
        send_update_notification "$updates_json" "$updates_found"

        # Update state file
        local temp_file=$(mktemp)
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq ".updates.last_check = \"$timestamp\" | .updates.pending = $updates_json" "$STATE_FILE" > "$temp_file"
        mv "$temp_file" "$STATE_FILE"
    else
        log "INFO" "No updates found"
    fi

    return 0
}

# Send update notification to Discord
send_update_notification() {
    local updates_json="$1"
    local update_count="$2"

    # Check if Discord webhook is configured
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        log "WARN" "Discord webhook not configured. Skipping update notification"
        return 0
    fi

    # Check alert cooldown
    if ! check_alert_cooldown "update"; then
        return 0
    fi

    log "INFO" "Sending update notification to Discord"

    # Build Discord embed fields
    local fields="["
    local first=true

    for service in $(echo "$updates_json" | jq -r 'keys[]'); do
        local image=$(echo "$updates_json" | jq -r ".$service.image")
        local current=$(echo "$updates_json" | jq -r ".$service.current")
        local new=$(echo "$updates_json" | jq -r ".$service.new")
        local changelog=$(echo "$updates_json" | jq -r ".$service.changelog")

        if [ "$first" = false ]; then
            fields="$fields,"
        fi
        first=false

        # Truncate changelog to fit Discord limits (1024 chars per field)
        local truncated_changelog=$(echo "$changelog" | head -c 900)
        if [ ${#changelog} -gt 900 ]; then
            truncated_changelog="$truncated_changelog\n..."
        fi

        local escaped_changelog=$(echo "$truncated_changelog" | jq -Rs .)
        local field_value="**Image:** \`$image\`\n**Current:** \`$current\`\n**New:** \`$new\`\n\n**Recent Changes:**\n$truncated_changelog"
        local escaped_field_value=$(echo -e "$field_value" | jq -Rs .)

        fields="$fields{\"name\":\"📦 $service\",\"value\":$escaped_field_value,\"inline\":false}"
    done

    fields="$fields]"

    # Create Discord embed JSON
    local footer_text="Watchtower will auto-update these services at 4:00 AM"
    local discord_payload=$(cat <<EOF
{
  "username": "Media Stack Monitor",
  "avatar_url": "https://cdn-icons-png.flaticon.com/512/2103/2103633.png",
  "embeds": [{
    "title": "🔔 Docker Image Updates Available",
    "description": "Found **$update_count** update(s) ready to install.",
    "color": ${COLOR_INFO},
    "fields": $fields,
    "footer": {
      "text": "$footer_text"
    },
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)

    # Send to Discord webhook
    if curl -s -H "Content-Type: application/json" \
        -d "$discord_payload" \
        "$DISCORD_WEBHOOK_URL" > /dev/null; then
        log "INFO" "Update notification sent successfully to Discord"
        update_last_alert_time "update"
    else
        log "ERROR" "Failed to send update notification to Discord"
    fi
}

# Main health check
main() {
    # Initialize state file
    initialize_state

    # If --check-updates flag is set, only run update checks
    if [ "$CHECK_UPDATES" -eq 1 ]; then
        log "INFO" "Running Docker image update checks..."
        check_image_updates
        return $?
    fi

    # Otherwise, run regular health checks
    log "INFO" "Starting health check..."

    local check_failed=0

    # Run checks
    if ! check_docker_health; then
        check_failed=1
    fi

    if ! check_vpn; then
        check_failed=1
    fi

    if ! check_disk_space; then
        check_failed=1
    fi

    if ! check_fail2ban; then
        check_failed=1
    fi

    if [ "$check_failed" -eq 0 ]; then
        log "INFO" "All health checks passed"
    else
        log "ERROR" "Some health checks failed"
    fi
}

# Run main function
main
