# Disaster Recovery Guide

This guide covers catastrophic failure scenarios and how to recover your media stack.

## Table of Contents

1. [Backup Strategy](#backup-strategy)
2. [What's Backed Up](#whats-backed-up)
3. [Scenario A: Drive Re-mount](#scenario-a-drive-re-mount)
4. [Scenario B: Complete Drive Failure](#scenario-b-complete-drive-failure)
5. [Data Recovery Matrix](#data-recovery-matrix)
6. [Verification Checklist](#verification-checklist)

---

## Backup Strategy

**Purpose:** Catastrophic recovery only (not versioned configuration management)

**Frequency:** On-demand or monthly
```bash
# Manual backup
./scripts/backup.sh

# Monthly backup (via cron)
# Add to crontab: 0 3 1 * * cd /Users/brandon/projects/torrents && ./scripts/backup.sh
```

**Backup Contents:**
- `configs/` - All service configurations and databases (43MB)
- `.env` - Secrets and credentials (3KB)
- `docker-compose.yml` - Infrastructure definition (6.7KB)
- `monitoring/` - Health check scripts (24KB)
- Documentation files (40KB)

**Exclusions:**
- Plex logs and cache (can reach 100MB+)
- Gluetun server list (7MB static file, easily re-downloaded)
- Temporary files

**Compressed Size:** ~10-12MB per backup
**Retention:** Last 12 backups (~150MB total)
**Location:** `./backups/media-stack-backup_YYYYMMDD_HHMMSS.tar.gz`

**Optional Remote Sync:**
```bash
# Configure in .env
REMOTE_BACKUP_PATH="s3://my-bucket/media-stack"          # AWS S3
REMOTE_BACKUP_PATH="user@backup-server:/backups"        # SSH/rsync
REMOTE_BACKUP_PATH="/Volumes/ExternalDrive/backups"     # Local path

# Run with remote sync
./scripts/backup.sh --remote-sync
```

---

## What's Backed Up

### Fully Recoverable ✅
These are saved in the backup and can be fully restored:

- **Service configurations:** All settings, API keys, download client configs
- **Radarr database:** Complete movie library list with quality preferences
- **Sonarr database:** Complete TV show/episode library with tracking
- **Prowlarr:** All indexer credentials and configurations
- **Overseerr:** User accounts, request history, approval workflows
- **Deluge:** Download client settings, category configurations
- **Traefik:** SSL certificates from Let's Encrypt
- **Quality profiles:** Custom quality and naming schemes
- **Network settings:** VPN configuration, proxy rules

### Lost Forever ❌
These are NOT in the backup and cannot be recovered:

- **Media files (626GB):** All movies in `/data/Movies` and shows in `/data/Shows`
- **Plex watch history:** Which episodes you've watched, ratings
- **Plex "Continue Watching":** Resume positions for in-progress media
- **Deluge seeding history:** Upload ratios and torrent state
- **Custom Plex collections:** Manual playlists and smart collections
- **Plex intro/credit markers:** Auto-skip configurations

### Auto-Recoverable 🔄
These can be rebuilt automatically after restoration:

- **Media files:** Radarr/Sonarr will detect missing files and can re-download automatically
- **Plex metadata:** Will rescan and re-download from online sources
- **Indexer sync:** Prowlarr will re-sync to Radarr/Sonarr on startup

---

## Scenario A: Drive Re-mount

**Situation:** External drive disconnected, macOS rebooted, USB cable unplugged, etc.
**Data Status:** ✅ Media files intact
**Recovery Time:** 2-5 minutes
**Risk Level:** 🟢 Low

### Symptoms
- Docker containers can't access `/Volumes/Samsung_T5`
- Services reporting "media disk not mounted" errors
- Radarr/Sonarr showing all media as missing
- Plex libraries empty

### Recovery Steps

**1. Stop all services**
```bash
cd /Users/brandon/projects/torrents
docker compose down
```

**2. Verify drive is connected**
```bash
# Check if drive is physically connected
diskutil list | grep Samsung_T5

# If not visible, reconnect drive and wait 10 seconds
```

**3. Mount the drive (if unmounted)**
```bash
# macOS should auto-mount at /Volumes/Samsung_T5
# If not, manually mount:
diskutil mount Samsung_T5

# Verify mount
ls -la /Volumes/Samsung_T5
```

**4. Verify data integrity**
```bash
# Quick check: count movies and shows
find /Volumes/Samsung_T5/Movies -name "*.mkv" -o -name "*.mp4" | wc -l
find /Volumes/Samsung_T5/Shows -name "*.mkv" -o -name "*.mp4" | wc -l

# Should match your expected library size
```

**5. Restart services**
```bash
docker compose up -d
```

**6. Wait for health checks**
```bash
# Monitor service health
docker compose ps

# All services should show "healthy" status after 30-60 seconds
```

**7. Verify recovery**
- Radarr: Browse to http://dev.local:7878 → Movies → All files should be present
- Sonarr: Browse to http://dev.local:8989 → Series → All episodes should show
- Plex: Browse to http://dev.local:32400 → Libraries should populate
- Check Discord for recovery alerts from health monitor

### Expected Results
- ✅ All services healthy within 2 minutes
- ✅ All media files visible in Radarr/Sonarr
- ✅ Plex libraries fully populated
- ✅ No data loss

---

## Scenario B: Complete Drive Failure

**Situation:** Drive died, corrupted, physically lost, or formatted
**Data Status:** ❌ All media files lost (626GB)
**Recovery Time:** Hours to days (depending on re-download speed)
**Risk Level:** 🔴 High

### Symptoms
- Drive not recognized by macOS
- Disk Utility shows drive as "unreadable" or doesn't appear
- Smart status shows drive failure
- Physical damage to drive

### Before You Begin

**⚠️ Important Warnings:**
1. **Seeding ratios will be lost:** If using private trackers, inform admins of data loss
2. **Watch history is gone:** You'll lose track of what you've watched
3. **Re-downloading takes time:** 626GB at 10MB/s = ~17 hours of downloading
4. **Some torrents may be unavailable:** Old/rare content might not seed anymore

### Recovery Steps

**1. Acquire replacement drive**
- Minimum capacity: 1TB (current usage: 626GB + room for growth)
- Recommended: Same or larger than original Samsung T5
- Format as: APFS or HFS+ (macOS Extended Journaled)

**2. Mount new drive at same location**
```bash
# Verify new drive name
diskutil list

# If drive is named differently, rename it
diskutil rename /Volumes/NewDriveName Samsung_T5

# Verify mount point
ls -la /Volumes/Samsung_T5
```

**3. Stop all services (if running)**
```bash
cd /Users/brandon/projects/torrents
docker compose down
```

**4. Restore from latest backup**
```bash
# List available backups
ls -lh backups/

# Extract latest backup
tar xzf backups/media-stack-backup_YYYYMMDD_HHMMSS.tar.gz

# This restores:
# - configs/
# - .env
# - docker-compose.yml
# - monitoring/
# - All documentation
```

**5. Recreate directory structure**
```bash
# Create required directories on new drive
mkdir -p /Volumes/Samsung_T5/Downloads
mkdir -p /Volumes/Samsung_T5/Movies
mkdir -p /Volumes/Samsung_T5/Shows

# Set permissions (if needed)
chmod -R 755 /Volumes/Samsung_T5/
```

**6. Start all services**
```bash
docker compose up -d
```

**7. Wait for services to initialize**
```bash
# Monitor logs for any errors
docker compose logs -f

# Wait for all services to report healthy
docker compose ps

# This may take 2-3 minutes on first startup
```

**8. Verify service restoration**
- Radarr: http://dev.local:7878 → Should show all your movies (marked as missing)
- Sonarr: http://dev.local:8989 → Should show all your shows (episodes missing)
- Prowlarr: http://dev.local:9696 → Indexers should be configured
- Overseerr: http://dev.local:5055 → Request history should be intact
- Plex: http://dev.local:32400 → Libraries exist but empty

**9. Re-download media (choose one method)**

**Option A: Automatic Re-download (Recommended)**
```bash
# In Radarr
1. Go to: Movies → Select All
2. Click: Search → Search All Missing
3. Wait for downloads to queue in Deluge

# In Sonarr
1. Go to: Series → Select All
2. Click: Search → Search All Missing
3. Wait for downloads to queue in Deluge
```

**Option B: Manual Re-download**
```bash
# Re-add content one by one through Overseerr
# This gives you a chance to curate what you actually want back
```

**10. Monitor download progress**
```bash
# Check Deluge
http://dev.local:8112

# Check VPN is working
docker exec gluetun wget -qO- https://api.ipify.org
# Should show VPN IP (185.x.x.x range for NordVPN US)

# Monitor disk space
df -h /Volumes/Samsung_T5
```

**11. Wait for imports**
- Deluge will download to `/data/Downloads`
- Radarr/Sonarr will automatically detect completed downloads
- Files will be hardlinked to `/data/Movies` or `/data/Shows`
- Plex will auto-scan and add media (if configured)
- Check Overseerr scheduled task for Plex scans (every 5 min)

### Expected Timeline

| Step | Time |
|------|------|
| Backup restoration | 1-2 minutes |
| Service startup | 2-3 minutes |
| First movie download | 10-30 minutes (depends on size/speed) |
| Full library re-download | Hours to days (626GB) |
| Plex metadata rebuild | 1-2 hours (after media available) |

### Expected Results
- ✅ All services restored with original settings
- ✅ Radarr knows what movies you had
- ✅ Sonarr knows what shows you had
- ✅ Indexers and download client configured
- ⏳ Media files downloading/importing
- ❌ Watch history lost
- ❌ Seeding ratios reset

---

## Data Recovery Matrix

| Data Type | Scenario A (Re-mount) | Scenario B (Drive Failure) |
|-----------|----------------------|---------------------------|
| Media files (626GB) | ✅ Intact | ❌ Lost → Re-download |
| Service configs | ✅ Intact | ✅ From backup |
| API keys | ✅ Intact | ✅ From backup |
| Movie/show lists | ✅ Intact | ✅ From backup (databases) |
| Quality profiles | ✅ Intact | ✅ From backup |
| Indexer credentials | ✅ Intact | ✅ From backup |
| Download client settings | ✅ Intact | ✅ From backup |
| Plex watch history | ✅ Intact | ❌ Lost forever |
| Plex libraries | ✅ Intact | 🔄 Auto-rebuild from files |
| Deluge seeding ratios | ✅ Intact | ❌ Lost forever |
| Overseerr requests | ✅ Intact | ✅ From backup |
| SSL certificates | ✅ Intact | ✅ From backup |

---

## Verification Checklist

After recovery, verify each component:

### Infrastructure
- [ ] All Docker containers running: `docker compose ps`
- [ ] All services healthy: `docker compose ps` (check health status)
- [ ] Drive mounted: `ls /Volumes/Samsung_T5`
- [ ] Directory structure intact: `ls /Volumes/Samsung_T5/{Movies,Shows,Downloads}`

### Services
- [ ] Traefik dashboard accessible: https://traefik.${DOMAIN} (if configured)
- [ ] VPN connected: `docker exec gluetun wget -qO- https://api.ipify.org`
- [ ] Plex accessible: http://dev.local:32400
- [ ] Radarr accessible: http://dev.local:7878
- [ ] Sonarr accessible: http://dev.local:8989
- [ ] Prowlarr accessible: http://dev.local:9696
- [ ] Overseerr accessible: http://dev.local:5055
- [ ] Deluge accessible via VPN: http://dev.local:8112

### Functionality
- [ ] Radarr → Settings → Download Clients → Test (should succeed)
- [ ] Sonarr → Settings → Download Clients → Test (should succeed)
- [ ] Prowlarr → Settings → Apps → Test All (should succeed)
- [ ] Overseerr → Settings → Plex → Test (should succeed)
- [ ] Overseerr → Settings → Radarr → Test (should succeed)
- [ ] Overseerr → Settings → Sonarr → Test (should succeed)
- [ ] Plex libraries visible (may be empty if Scenario B)
- [ ] Health monitor running: `docker compose logs health-monitor`

### Data Integrity (Scenario A only)
- [ ] Movie count matches: `find /Volumes/Samsung_T5/Movies -name "*.mkv" -o -name "*.mp4" | wc -l`
- [ ] Show count matches: `find /Volumes/Samsung_T5/Shows -name "*.mkv" -o -name "*.mp4" | wc -l`
- [ ] Radarr shows 0 missing movies
- [ ] Sonarr shows all episodes present
- [ ] Plex watch history intact

### Downloads (Scenario B only)
- [ ] Radarr queued missing movies
- [ ] Sonarr queued missing episodes
- [ ] Deluge shows active downloads
- [ ] VPN protecting torrent traffic
- [ ] Disk space sufficient for downloads

### Alerts
- [ ] Discord webhook functional: Check recent messages
- [ ] Health monitor sent recovery notification (if applicable)
- [ ] No critical errors in logs: `docker compose logs --tail=100`

---

## Backup Best Practices

1. **Test backups regularly:** Extract and verify contents monthly
   ```bash
   tar tzf backups/media-stack-backup_YYYYMMDD_HHMMSS.tar.gz | head -20
   ```

2. **Store backups off-site:** Use `--remote-sync` to backup to cloud/another machine
   ```bash
   ./scripts/backup.sh --remote-sync
   ```

3. **Document credentials:** Keep VPN and service credentials in password manager

4. **Monitor disk health:** Check SMART status regularly
   ```bash
   diskutil info Samsung_T5 | grep -i smart
   ```

5. **Keep drive connected:** External drives fail more often when frequently disconnected

6. **Update backups after changes:** Run backup after adding new services or major config changes

---

## Emergency Contacts

**Private Tracker Support:**
- TorrentDay: Contact staff about ratio reset due to catastrophic failure
- Other trackers: Check forums for data loss policies

**Service Documentation:**
- Radarr: https://wiki.servarr.com/radarr
- Sonarr: https://wiki.servarr.com/sonarr
- TRaSH Guides: https://trash-guides.info/

**Discord Alerts:**
- Webhook URL stored in `.env`
- Test alerts: Stop a service and wait for notification

---

## Quick Reference Commands

```bash
# Create backup
./scripts/backup.sh

# List backups
ls -lh backups/

# Restore backup
tar xzf backups/media-stack-backup_YYYYMMDD_HHMMSS.tar.gz

# Check drive status
df -h /Volumes/Samsung_T5

# Service health
docker compose ps

# Check VPN IP
docker exec gluetun wget -qO- https://api.ipify.org

# View logs
docker compose logs -f [service-name]

# Restart everything
docker compose down && docker compose up -d
```
