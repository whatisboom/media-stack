#!/bin/bash
#
# Media Stack Backup Script
# Creates compressed backups of critical configuration files for disaster recovery
#
# Usage: ./backup/backup.sh [--remote-sync]
#

set -euo pipefail

# Ensure script runs from /workspace directory
WORKSPACE_DIR="/workspace"
if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "Error: $WORKSPACE_DIR does not exist" >&2
    exit 1
fi

cd "$WORKSPACE_DIR" || {
    echo "Error: Cannot change to $WORKSPACE_DIR" >&2
    exit 1
}

# Configuration
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="media-stack-backup_${TIMESTAMP}.tar.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
RETENTION_COUNT=12  # Keep last 12 backups

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
REMOTE_SYNC=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote-sync)
            REMOTE_SYNC=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--remote-sync]"
            echo ""
            echo "Options:"
            echo "  --remote-sync    Upload backup to remote location (configure REMOTE_BACKUP_PATH in .env)"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load environment variables if .env exists
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

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

echo -e "${GREEN}=== Media Stack Backup ===${NC}"
echo "Backup timestamp: ${TIMESTAMP}"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create temporary exclude file
EXCLUDE_FILE=$(mktemp)
cat > "$EXCLUDE_FILE" <<'EOF'
# Plex - exclude logs, cache, crash reports (keep databases for watch history)
configs/plex/Library/Application Support/Plex Media Server/Logs/*
configs/plex/Library/Application Support/Plex Media Server/Cache/*
configs/plex/Library/Application Support/Plex Media Server/Crash Reports/*

# Plex - exclude SQLite temporary files (WAL/SHM will be recreated)
configs/plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases/*.db-wal
configs/plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases/*.db-shm

# Gluetun (7MB static file, easily re-downloaded)
configs/gluetun/servers.json

# Temporary files
*.tmp
*.swp
*~
EOF

# Files and directories to backup
BACKUP_ITEMS=(
    "configs"
    ".env"
    "docker-compose.yml"
    "monitoring"
    "README.md"
    "CLAUDE.md"
    ".gitignore"
)

# Check if all items exist
echo -e "${YELLOW}Checking backup items...${NC}"
for item in "${BACKUP_ITEMS[@]}"; do
    if [ ! -e "$item" ]; then
        echo -e "${RED}Warning: $item not found, skipping${NC}"
    else
        echo "  ✓ $item"
    fi
done
echo ""

# Create backup
echo -e "${YELLOW}Creating compressed backup...${NC}"
tar czf "$BACKUP_PATH" \
    --exclude-from="$EXCLUDE_FILE" \
    "${BACKUP_ITEMS[@]}" \
    2>/dev/null || {
        # If tar fails for some items, continue with what exists
        echo -e "${YELLOW}Some items may have been skipped${NC}"
    }

# Clean up exclude file
rm -f "$EXCLUDE_FILE"

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
                "Backup is missing critical files:\\n$(printf '• %s\\n' "${missing_files[@]}")" \
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

# Verify backup
echo -e "${YELLOW}Verifying backup integrity...${NC}"
if tar tzf "$BACKUP_PATH" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Backup integrity verified${NC}"

    # Add validation
    if ! validate_backup "$BACKUP_PATH"; then
        echo -e "${RED}Backup validation failed - review missing files${NC}"
        exit 1
    fi
else
    echo -e "${RED}  ✗ Backup verification failed!${NC}"
    send_discord_notification "Failed" \
        "Backup verification failed!\\n**Path:** ${BACKUP_PATH}" \
        15158332  # Red
    exit 1
fi

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
echo ""
echo -e "${GREEN}Backup created successfully!${NC}"
echo "  Location: $BACKUP_PATH"
echo "  Size: $BACKUP_SIZE"
echo ""

# Send success notification
send_discord_notification "Successful" \
    "Backup created successfully\\n**Size:** ${BACKUP_SIZE}\\n**Location:** ${BACKUP_PATH}" \
    3066993  # Green

# Check backup size and warn if exceeding threshold
if [ "${BACKUP_SIZE//[!0-9]/}" -gt 200 ]; then  # Strip units, check if >200MB
    send_discord_notification "Warning" \
        "Backup size exceeds 200MB threshold\\n**Size:** ${BACKUP_SIZE}\\n**Review excludes or cleanup configs**" \
        16776960  # Yellow
fi

# Apply retention policy
echo -e "${YELLOW}Applying retention policy (keep last ${RETENTION_COUNT} backups)...${NC}"
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/media-stack-backup_*.tar.gz 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt "$RETENTION_COUNT" ]; then
    DELETE_COUNT=$((BACKUP_COUNT - RETENTION_COUNT))
    echo "  Found $BACKUP_COUNT backups, removing oldest $DELETE_COUNT"

    ls -1t "${BACKUP_DIR}"/media-stack-backup_*.tar.gz | tail -n "$DELETE_COUNT" | while read -r old_backup; do
        echo "  Removing: $(basename "$old_backup")"
        rm -f "$old_backup"
    done
else
    echo "  Found $BACKUP_COUNT backups (within retention limit)"
fi
echo ""

# List current backups
echo -e "${GREEN}Current backups:${NC}"
ls -lh "${BACKUP_DIR}"/media-stack-backup_*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""

# Remote sync (optional)
if [ "$REMOTE_SYNC" -eq 1 ]; then
    if [ -z "${REMOTE_BACKUP_PATH:-}" ]; then
        echo -e "${YELLOW}Warning: REMOTE_BACKUP_PATH not configured in .env${NC}"
        echo "Skipping remote sync."
    else
        echo -e "${YELLOW}Syncing to remote location...${NC}"
        echo "  Remote: $REMOTE_BACKUP_PATH"

        # Detect remote type and sync accordingly
        if [[ "$REMOTE_BACKUP_PATH" =~ ^[a-zA-Z0-9_-]+: ]]; then
            # rclone remote (e.g., r2:bucket-name, b2:bucket-name)
            if command -v rclone &> /dev/null; then
                rclone copy "$BACKUP_PATH" "$REMOTE_BACKUP_PATH/"
                echo -e "${GREEN}  ✓ Synced via rclone${NC}"
                send_discord_notification "Synced" \
                    "Backup synced to remote location\\n**Remote:** ${REMOTE_BACKUP_PATH}" \
                    3447003  # Blue
            else
                echo -e "${RED}  ✗ rclone not installed${NC}"
                echo -e "${YELLOW}  Install: brew install rclone (macOS) or see https://rclone.org${NC}"
            fi
        elif [[ "$REMOTE_BACKUP_PATH" =~ ^s3:// ]]; then
            # AWS S3 (native AWS CLI)
            if command -v aws &> /dev/null; then
                aws s3 cp "$BACKUP_PATH" "$REMOTE_BACKUP_PATH/"
                echo -e "${GREEN}  ✓ Synced to S3${NC}"
                send_discord_notification "Synced" \
                    "Backup synced to remote location\\n**Remote:** ${REMOTE_BACKUP_PATH}" \
                    3447003  # Blue
            else
                echo -e "${RED}  ✗ AWS CLI not installed${NC}"
            fi
        elif [[ "$REMOTE_BACKUP_PATH" =~ @ ]]; then
            # SSH/rsync
            if command -v rsync &> /dev/null; then
                rsync -avz "$BACKUP_PATH" "$REMOTE_BACKUP_PATH/"
                echo -e "${GREEN}  ✓ Synced via rsync${NC}"
                send_discord_notification "Synced" \
                    "Backup synced to remote location\\n**Remote:** ${REMOTE_BACKUP_PATH}" \
                    3447003  # Blue
            else
                echo -e "${RED}  ✗ rsync not installed${NC}"
            fi
        else
            # Local path
            mkdir -p "$REMOTE_BACKUP_PATH"
            cp "$BACKUP_PATH" "$REMOTE_BACKUP_PATH/"
            echo -e "${GREEN}  ✓ Copied to remote path${NC}"
            send_discord_notification "Synced" \
                "Backup synced to remote location\\n**Remote:** ${REMOTE_BACKUP_PATH}" \
                3447003  # Blue
        fi
        echo ""
    fi
fi

# Summary
echo -e "${GREEN}=== Backup Complete ===${NC}"
echo ""
echo "To restore from this backup:"
echo "  tar xzf $BACKUP_PATH"
echo ""
echo "For disaster recovery instructions, see:"
echo "  DISASTER_RECOVERY.md"

# Create healthcheck marker file for Docker
touch /logs/.last_backup_success
