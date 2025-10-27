#!/bin/bash
#
# Media Stack Backup Script
# Creates compressed backups of critical configuration files for disaster recovery
#
# Usage: ./scripts/backup.sh [--remote-sync]
#

set -euo pipefail

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

echo -e "${GREEN}=== Media Stack Backup ===${NC}"
echo "Backup timestamp: ${TIMESTAMP}"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create temporary exclude file
EXCLUDE_FILE=$(mktemp)
cat > "$EXCLUDE_FILE" <<'EOF'
# Plex
configs/plex/Library/Application Support/Plex Media Server/Logs/*
configs/plex/Library/Application Support/Plex Media Server/Cache/*
configs/plex/Library/Application Support/Plex Media Server/Crash Reports/*

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

# Verify backup
echo -e "${YELLOW}Verifying backup integrity...${NC}"
if tar tzf "$BACKUP_PATH" > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Backup integrity verified${NC}"
else
    echo -e "${RED}  ✗ Backup verification failed!${NC}"
    exit 1
fi

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
echo ""
echo -e "${GREEN}Backup created successfully!${NC}"
echo "  Location: $BACKUP_PATH"
echo "  Size: $BACKUP_SIZE"
echo ""

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
            else
                echo -e "${RED}  ✗ rclone not installed${NC}"
                echo -e "${YELLOW}  Install: brew install rclone (macOS) or see https://rclone.org${NC}"
            fi
        elif [[ "$REMOTE_BACKUP_PATH" =~ ^s3:// ]]; then
            # AWS S3 (native AWS CLI)
            if command -v aws &> /dev/null; then
                aws s3 cp "$BACKUP_PATH" "$REMOTE_BACKUP_PATH/"
                echo -e "${GREEN}  ✓ Synced to S3${NC}"
            else
                echo -e "${RED}  ✗ AWS CLI not installed${NC}"
            fi
        elif [[ "$REMOTE_BACKUP_PATH" =~ @ ]]; then
            # SSH/rsync
            if command -v rsync &> /dev/null; then
                rsync -avz "$BACKUP_PATH" "$REMOTE_BACKUP_PATH/"
                echo -e "${GREEN}  ✓ Synced via rsync${NC}"
            else
                echo -e "${RED}  ✗ rsync not installed${NC}"
            fi
        else
            # Local path
            mkdir -p "$REMOTE_BACKUP_PATH"
            cp "$BACKUP_PATH" "$REMOTE_BACKUP_PATH/"
            echo -e "${GREEN}  ✓ Copied to remote path${NC}"
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
