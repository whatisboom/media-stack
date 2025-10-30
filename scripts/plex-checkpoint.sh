#!/bin/bash
#
# Plex Database Checkpoint Script
# Creates a safety checkpoint of Plex databases before risky operations
#
# Usage: ./scripts/plex-checkpoint.sh [create|restore|list|clean]
#

set -euo pipefail

# Configuration
CHECKPOINT_DIR="./backups/plex-checkpoints"
PLEX_DB_DIR="./configs/plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases"
RETENTION_COUNT=7  # Keep last 7 checkpoints

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Command
COMMAND="${1:-create}"

case "$COMMAND" in
    create)
        echo -e "${GREEN}=== Creating Plex Database Checkpoint ===${NC}"

        # Create checkpoint directory
        mkdir -p "$CHECKPOINT_DIR"

        # Generate timestamp
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        CHECKPOINT_NAME="plex-checkpoint_${TIMESTAMP}"
        CHECKPOINT_PATH="${CHECKPOINT_DIR}/${CHECKPOINT_NAME}.tar.gz"

        echo "Timestamp: $TIMESTAMP"
        echo ""

        # Check if Plex is running
        if docker ps --format '{{.Names}}' | grep -q '^plex$'; then
            echo -e "${YELLOW}Warning: Plex is running${NC}"
            echo "For best results, stop Plex before creating checkpoint:"
            echo "  docker compose stop plex"
            echo ""
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Aborted."
                exit 1
            fi
        fi

        # Create checkpoint
        echo -e "${YELLOW}Creating checkpoint...${NC}"
        tar czf "$CHECKPOINT_PATH" -C "$PLEX_DB_DIR" \
            --exclude="*.db-wal" \
            --exclude="*.db-shm" \
            . 2>/dev/null

        # Verify
        if tar tzf "$CHECKPOINT_PATH" > /dev/null 2>&1; then
            CHECKPOINT_SIZE=$(du -h "$CHECKPOINT_PATH" | cut -f1)
            echo -e "${GREEN}  ✓ Checkpoint created${NC}"
            echo "  Location: $CHECKPOINT_PATH"
            echo "  Size: $CHECKPOINT_SIZE"
        else
            echo -e "${RED}  ✗ Checkpoint verification failed${NC}"
            exit 1
        fi

        # Apply retention
        echo ""
        echo -e "${YELLOW}Applying retention policy (keep last ${RETENTION_COUNT})...${NC}"
        CHECKPOINT_COUNT=$(ls -1 "${CHECKPOINT_DIR}"/plex-checkpoint_*.tar.gz 2>/dev/null | wc -l)

        if [ "$CHECKPOINT_COUNT" -gt "$RETENTION_COUNT" ]; then
            DELETE_COUNT=$((CHECKPOINT_COUNT - RETENTION_COUNT))
            echo "  Found $CHECKPOINT_COUNT checkpoints, removing oldest $DELETE_COUNT"

            ls -1t "${CHECKPOINT_DIR}"/plex-checkpoint_*.tar.gz | tail -n "$DELETE_COUNT" | while read -r old_checkpoint; do
                echo "  Removing: $(basename "$old_checkpoint")"
                rm -f "$old_checkpoint"
            done
        else
            echo "  Found $CHECKPOINT_COUNT checkpoints (within retention limit)"
        fi

        echo ""
        echo -e "${GREEN}=== Checkpoint Complete ===${NC}"
        echo ""
        echo "To restore from this checkpoint:"
        echo "  ./scripts/plex-checkpoint.sh restore $TIMESTAMP"
        ;;

    restore)
        TIMESTAMP="${2:-}"
        if [ -z "$TIMESTAMP" ]; then
            echo -e "${RED}Error: Timestamp required${NC}"
            echo "Usage: $0 restore TIMESTAMP"
            echo ""
            echo "Available checkpoints:"
            ls -1 "${CHECKPOINT_DIR}"/plex-checkpoint_*.tar.gz 2>/dev/null | sed 's/.*plex-checkpoint_//;s/.tar.gz//' | while read -r ts; do
                echo "  $ts"
            done
            exit 1
        fi

        CHECKPOINT_PATH="${CHECKPOINT_DIR}/plex-checkpoint_${TIMESTAMP}.tar.gz"

        if [ ! -f "$CHECKPOINT_PATH" ]; then
            echo -e "${RED}Error: Checkpoint not found: $CHECKPOINT_PATH${NC}"
            exit 1
        fi

        echo -e "${YELLOW}=== Restoring Plex Database from Checkpoint ===${NC}"
        echo "Checkpoint: $TIMESTAMP"
        echo ""

        # Check if Plex is running
        if docker ps --format '{{.Names}}' | grep -q '^plex$'; then
            echo -e "${RED}Error: Plex is running${NC}"
            echo "Stop Plex before restoring:"
            echo "  docker compose stop plex"
            exit 1
        fi

        # Backup current state before restore
        echo -e "${YELLOW}Creating safety backup of current state...${NC}"
        SAFETY_BACKUP="${CHECKPOINT_DIR}/pre-restore-backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar czf "$SAFETY_BACKUP" -C "$PLEX_DB_DIR" . 2>/dev/null
        echo -e "${GREEN}  ✓ Safety backup created: $SAFETY_BACKUP${NC}"
        echo ""

        # Restore checkpoint
        echo -e "${YELLOW}Restoring checkpoint...${NC}"

        # Clear current databases
        rm -f "${PLEX_DB_DIR}"/*.db* 2>/dev/null || true

        # Extract checkpoint
        tar xzf "$CHECKPOINT_PATH" -C "$PLEX_DB_DIR"

        echo -e "${GREEN}  ✓ Checkpoint restored${NC}"
        echo ""
        echo -e "${GREEN}=== Restore Complete ===${NC}"
        echo ""
        echo "Start Plex to verify:"
        echo "  docker compose start plex"
        ;;

    list)
        echo -e "${GREEN}=== Available Plex Checkpoints ===${NC}"
        echo ""

        if ls "${CHECKPOINT_DIR}"/plex-checkpoint_*.tar.gz &>/dev/null; then
            ls -lht "${CHECKPOINT_DIR}"/plex-checkpoint_*.tar.gz | awk '{
                # Extract timestamp from filename
                match($9, /plex-checkpoint_([0-9_]+)\.tar\.gz/, arr)
                ts = arr[1]
                # Format: YYYYMMDD_HHMMSS -> YYYY-MM-DD HH:MM:SS
                date = substr(ts, 1, 4) "-" substr(ts, 5, 2) "-" substr(ts, 7, 2)
                time = substr(ts, 10, 2) ":" substr(ts, 12, 2) ":" substr(ts, 14, 2)
                print "  " date " " time " - " $5 " - " ts
            }'
        else
            echo "  No checkpoints found"
        fi
        echo ""
        ;;

    clean)
        echo -e "${YELLOW}=== Cleaning Old Checkpoints ===${NC}"
        echo "This will remove all checkpoints except the last ${RETENTION_COUNT}"
        echo ""
        read -p "Continue? (y/N) " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi

        CHECKPOINT_COUNT=$(ls -1 "${CHECKPOINT_DIR}"/plex-checkpoint_*.tar.gz 2>/dev/null | wc -l)

        if [ "$CHECKPOINT_COUNT" -gt "$RETENTION_COUNT" ]; then
            DELETE_COUNT=$((CHECKPOINT_COUNT - RETENTION_COUNT))
            echo "Removing oldest $DELETE_COUNT checkpoints..."

            ls -1t "${CHECKPOINT_DIR}"/plex-checkpoint_*.tar.gz | tail -n "$DELETE_COUNT" | while read -r old_checkpoint; do
                echo "  Removing: $(basename "$old_checkpoint")"
                rm -f "$old_checkpoint"
            done

            echo -e "${GREEN}Cleanup complete${NC}"
        else
            echo "Nothing to clean (found $CHECKPOINT_COUNT checkpoints)"
        fi
        ;;

    *)
        echo "Usage: $0 {create|restore|list|clean}"
        echo ""
        echo "Commands:"
        echo "  create          Create a new checkpoint of Plex databases"
        echo "  restore TIME    Restore from checkpoint (e.g., 20251030_041500)"
        echo "  list            List available checkpoints"
        echo "  clean           Remove old checkpoints (keep last $RETENTION_COUNT)"
        exit 1
        ;;
esac
