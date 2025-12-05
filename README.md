# Media Server Stack

Self-hosted media automation stack built with Docker, configured following [TRaSH Guides](https://trash-guides.info/) best practices.

## Services

| Service | Port | Purpose | Access URL |
|---------|------|---------|------------|
| **Traefik** | 80, 443 | Reverse proxy with automatic HTTPS | https://traefik.${DOMAIN} |
| **Gluetun** | - | VPN container (NordVPN) | - |
| **Plex** | 32400 | Media streaming server | https://plex.${DOMAIN} (external)<br>http://dev.local:32400 (internal) |
| **Tautulli** | 8181 | Plex monitoring and analytics | http://dev.local:8181 |
| **Radarr** | 7878 | Movie library management & automation | http://dev.local:7878 |
| **Sonarr** | 8989 | TV show library management & automation | http://dev.local:8989 |
| **Bazarr** | 6767 | Subtitle management for movies & TV | http://dev.local:6767 |
| **Prowlarr** | 9696 | Indexer management (centralized) | http://dev.local:9696 |
| **Overseerr** | 5055 | Media request management | https://requests.${DOMAIN} (external)<br>http://dev.local:5055 (internal) |
| **Deluge** | 8112 | BitTorrent client (via gluetun) | http://dev.local:8112 |

## Quick Start

### Initial Setup

1. **Copy environment template**:
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` and configure**:
   - Set `PLEX_CLAIM_TOKEN` - Get from https://www.plex.tv/claim/ (expires in 4 minutes)
   - Set `DELUGE_WEB_PASSWORD` - Your preferred password
   - Set `DOMAIN` - Your domain name (e.g., example.com)
   - Set `ACME_EMAIL` - Your email for Let's Encrypt notifications
   - Set `TRAEFIK_BASIC_AUTH` - Generate with: `htpasswd -nb admin your-password`
   - Set `NORDVPN_USER` and `NORDVPN_PASSWORD` - Get service credentials from https://my.nordaccount.com/dashboard/nordvpn/
     - **IMPORTANT**: Use "Service credentials" NOT your regular NordVPN account login
     - Go to "Set up NordVPN manually" → "Service credentials"
   - Adjust `TZ` if needed (default: America/Chicago)

3. **Start services**:
   ```bash
   docker compose up -d
   ```

### Common Commands

```bash
# View logs
docker compose logs -f [service-name]

# Stop all services
docker compose down

# Restart a specific service
docker compose restart [service-name]

# Rebuild after config changes
docker compose up -d --force-recreate
```

## Directory Structure

```
torrents/
├── configs/           # Persistent configuration for all services
│   ├── bazarr/       # Bazarr subtitle settings and database
│   ├── deluge/       # Deluge settings, auth, torrents
│   ├── overseerr/    # Overseerr database and settings
│   ├── plex/         # Plex Media Server data
│   ├── prowlarr/     # Prowlarr indexer configs
│   ├── radarr/       # Radarr database and settings
│   ├── sonarr/       # Sonarr database and settings
│   ├── tautulli/     # Tautulli monitoring and statistics
│   └── traefik/      # Traefik SSL certificates
├── docker-compose.yml
└── README.md
```

## Volume Mappings

### Unified Data Path (TRaSH Guides Compliant)
All services mount the parent directory for hardlink support:
- **Host Path**: `/Volumes/Samsung_T5` → Container: `/data`

This allows:
- **Downloads**: `/data/Downloads` (visible to all services)
- **Movies**: `/data/Movies` (visible to all services)
- **Hardlinks**: Work properly (same filesystem)

### Config Paths
All configs stored in `./configs/[service-name]` and mounted to respective container config paths.

## Authentication & API Keys

### Environment Variables (User-Configured)
Configured in `.env` file:
- **Plex Claim Token**: Set via `PLEX_CLAIM_TOKEN`
- **Deluge Password**: Set via `DELUGE_WEB_PASSWORD` (default username: `admin`)
- **Timezone**: Set via `TZ`

### Auto-Generated API Keys
These are created automatically on first run. Find them in each service's web UI:

**Radarr** (http://dev.local:7878)
- Location: Settings → General → Security → API Key
- Also stored in: `configs/radarr/config.xml`

**Sonarr** (http://dev.local:8989)
- Location: Settings → General → Security → API Key
- Also stored in: `configs/sonarr/config.xml`

**Bazarr** (http://dev.local:6767)
- Configuration: Auto-generated on first run
- Radarr/Sonarr connection: Requires API keys from respective services
- Also stored in: `configs/bazarr/config/config.ini`

**Prowlarr** (http://dev.local:9696)
- Location: Settings → General → Security → API Key
- Also stored in: `configs/prowlarr/config.xml`

**Overseerr** (http://dev.local:5055)
- Location: Settings → General → API Key
- Also stored in: `configs/overseerr/settings.json`

**Tautulli** (http://dev.local:8181)
- Configuration: Auto-generated on first run
- Plex connection: Requires Plex URL and token (configured in setup wizard)
- Also stored in: `configs/tautulli/config.ini`

**Deluge**
- Web UI Password: Configured via `.env` file
- Additional users: Managed in `configs/deluge/auth`

## Configuration Details

### Radarr (Configured per TRaSH Guides)

**Download Client**: Deluge
- Host: `deluge` (Docker network)
- Port: 8112 (Web UI)
- Download Path: `/data/Downloads`
- Category: `radarr-movies`
- Auto-managed by Labels plugin

**Naming Scheme**:
```
{Movie CleanTitle} {(Release Year)} {{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo AudioCodec} {MediaInfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}
```

**Example**: `The Matrix (1999) {Edition-Extended} [Bluray-1080p][DTS 5.1][x264]-SPARKS`

**Quality Profile**: Ultra-HD
- Upgrades: Enabled
- Cutoff: Remux-2160p

### Deluge

**Key Settings**:
- Download location: `/data/Downloads`
- Listen ports: 6881-6891
- Encryption: Full Stream (level 2)
- Active torrents: 8 max (3 downloading, 5 seeding)
- Seed ratio: 2.0
- Seed time: 180 minutes

**Plugins**:
- Label (enabled for Radarr categorization)

### Prowlarr

**Connected Apps**:
- Radarr (Full Sync)
  - All movie categories (2000-2090)
  - Auto-syncs indexers to Radarr

**Indexer Management**:
- Add indexers in Prowlarr → auto-syncs to connected apps
- Configure seed goals per indexer
- Recommended: Set priorities (higher = preferred)

### Overseerr

**Integrations**:
- **Plex**: Connected and configured
- **Radarr**:
  - Profile: Ultra-HD
  - Root folder: `/data/Movies`
  - Minimum availability: Released

**Scheduled Jobs**:
- Plex recently added scan: Every 5 minutes
- Plex full scan: Daily at 3 AM
- Radarr scan: Daily at 4 AM
- Download sync: Every minute

### Tautulli

**Initial Setup** (http://dev.local:8181):
1. Access Tautulli web UI on first run
2. Follow setup wizard:
   - **Plex URL**: `http://plex:32400` (Docker network)
   - **Plex Token**: Get from Plex Settings → General → X-Plex-Token (in browser URL)
     - Or copy from existing `.env` if using PLEX_CLAIM_TOKEN
3. Complete initial configuration

**Key Features**:
- Real-time stream monitoring
- Watch history and user statistics
- Visual analytics and graphs
- Customizable notifications (Discord, Email, etc.)
- Newsletter generation for new content

**Optional Configuration**:
- **Plex LogViewer**: Already configured via volume mount (`./configs/plex:/plex-logs:ro`)
  - Enable in Tautulli: Settings → Plex Media Server → Show Advanced → Logs Folder: `/plex-logs/Plex Media Server/Logs`
- **Notifications**: Settings → Notification Agents → Add agent
- **Mobile Access**: Download Tautulli Remote app (iOS/Android)

### VPN Configuration

This stack uses **NordVPN via gluetun** for torrent traffic protection. Key features:

- **Auto-Recovery**: Health monitor automatically restarts VPN on DNS failures
- **Kill Switch**: Deluge traffic stops if VPN disconnects (network isolation)
- **Private Tracker Safe**: DHT/LSD/PEX disabled for TorrentDay compliance

**macOS Users**: If running NordVPN on host + gluetun in Docker:
- Traffic is NOT going through two VPN layers (clean separation via Docker networks)
- Occasional routing conflicts may trigger auto-restarts (< 1/day expected)
- See [CLAUDE.md](CLAUDE.md#macos-host-vpn-considerations) for details

**For Complete VPN Documentation**, see [CLAUDE.md](CLAUDE.md):
- VPN auto-recovery system (automated restart on failures)
- macOS host VPN considerations
- Manual troubleshooting steps
- DNS configuration details

## Workflow

### Movie/TV Show Automation

1. **Request** → User requests media via Overseerr
2. **Search** → Radarr/Sonarr searches configured indexers (via Prowlarr)
3. **Download** → Radarr/Sonarr sends torrent to Deluge with category (`radarr-movies` or `sonarr-tv`)
4. **Monitor** → Radarr/Sonarr monitors download progress in `/data/Downloads`
5. **Import** → When complete, Radarr/Sonarr hardlinks/moves to `/data/Movies` or `/data/Shows` with proper naming
6. **Subtitles** → Bazarr detects new media and automatically downloads subtitles based on language preferences
7. **Seed** → Deluge continues seeding until ratio/time goals met
8. **Stream** → Plex makes media available for streaming with subtitles

## Deleting Movies and TV Shows

### Quick Deletion

**Delete a Movie (Radarr)**:
1. Open Radarr: http://dev.local:7878
2. Navigate to **Library** or find the movie
3. Click the movie → **Edit** (pencil icon)
4. Click **Delete** at the bottom
5. Choose deletion options:
   - ✅ **Delete movie files** - Removes files from `/data/Movies`
   - ⬜ **Add exclusion** - Prevents re-downloading (optional)
6. Click **Delete** to confirm

**Delete a TV Show (Sonarr)**:
1. Open Sonarr: http://dev.local:8989
2. Navigate to **Series** or find the show
3. Click the show → **Edit** (pencil icon)
4. Click **Delete** at the bottom
5. Choose deletion options:
   - ✅ **Delete series folder** - Removes files from `/data/Shows`
   - ⬜ **Add exclusion** - Prevents re-downloading (optional)
6. Click **Delete** to confirm

### Complete Deletion (All Traces)

To fully remove media and free disk space, follow these steps in order:

#### 1. Delete from Radarr/Sonarr

Follow the Quick Deletion steps above. **Important**:
- Enable "Delete files" option to remove from filesystem
- This removes the library entry and files
- Does **NOT** automatically remove the torrent from Deluge

#### 2. Remove Torrent from Deluge

**Option A: Manual Removal** (Immediate)
1. Open Deluge: http://dev.local:8112
2. Find the torrent (filter by category: `radarr-movies` or `sonarr-tv`)
3. Right-click → **Remove Torrent**
4. Choose removal options:
   - ✅ **Remove torrent** - Removes from Deluge
   - ✅ **Remove data** - Deletes files from `/data/Downloads`
5. Click **Remove**

**Option B: Wait for Seed Goals** (Recommended for private trackers)
- Deluge will automatically stop seeding when ratio/time goals are met
- Radarr/Sonarr can auto-remove completed torrents if configured
- Preserves private tracker ratio requirements

**Check Seed Status**:
```bash
# View active torrents and their seed ratios
docker exec deluge deluge-console info
```

#### 3. Clean Up Plex Library

After deleting files, Plex needs to be updated:

**Automatic Cleanup** (Recommended):
1. Open Plex: http://dev.local:32400
2. Go to **Settings** → **Library**
3. Enable **"Empty trash automatically after every scan"**
4. Plex will auto-remove deleted media on next scheduled scan (every 5 min via Overseerr)

**Manual Cleanup**:
1. Open Plex: http://dev.local:32400
2. Navigate to the **Movies** or **TV Shows** library
3. Click **...** (library menu) → **Empty Trash**
4. Optional: **Settings** → **Manage** → **Troubleshooting** → **Clean Bundles** (removes unused artwork)

**Verify Removal**:
- Search for the deleted title in Plex
- It should no longer appear in your library

#### 4. Optional: Remove Request from Overseerr

Overseerr keeps request history even after media is deleted. To remove:

**Manual Removal**:
1. Open Overseerr: http://dev.local:5055
2. Go to **Requests** or search for the title
3. Click on the request → **Delete Request** (if available)

**Note**: Overseerr doesn't currently support bulk request deletion via UI. Request history is mostly harmless and can be left alone.

#### 5. Verify Complete Deletion

**Check filesystem**:
```bash
# Verify file is removed from media directory
ls -lh /Volumes/Samsung_T5/Movies/ | grep "Movie Title"
ls -lh /Volumes/Samsung_T5/Shows/ | grep "Show Title"

# Check if still in downloads (if torrent still seeding)
ls -lh /Volumes/Samsung_T5/Downloads/
```

**Check disk space**:
```bash
# View disk usage
df -h /Volumes/Samsung_T5/
```

### Important Considerations

#### Hardlinks and Disk Space

**How Hardlinks Work**:
- When Radarr/Sonarr imports media, they create **hardlinks** (not copies)
- Same file appears in both `/data/Downloads` and `/data/Movies` or `/data/Shows`
- **Only uses disk space once** (instant "move", space-efficient)

**Deletion Behavior**:
- Deleting from Radarr/Sonarr removes the file in `/data/Movies` or `/data/Shows`
- If torrent is still seeding, the file remains in `/data/Downloads`
- **Disk space is NOT freed until BOTH are removed**

**To Free Disk Space**:
1. Delete from Radarr/Sonarr (removes media library hardlink)
2. Remove torrent and data from Deluge (removes download hardlink)
3. Both hardlinks must be removed to free disk space

#### Private Tracker Seeding

**CRITICAL**: Removing torrents before meeting seed requirements can harm your ratio and risk account bans.

**Best Practices**:
- Check indexer/tracker requirements before deleting
- Let torrents seed to completion (ratio ≥ 1.0-2.0, time ≥ 7 days typical)
- Use Deluge's seeding filters to monitor progress
- Configure seed goals in Prowlarr per indexer

**Seed Goal Configuration**:
1. Open Prowlarr: http://dev.local:9696
2. Go to **Settings** → **Indexers**
3. For each private tracker:
   - Set **Seed Ratio**: 2.0 (or tracker requirement + 10-20%)
   - Set **Seed Time**: 10080 minutes (7 days, or tracker requirement)

#### Automatic Torrent Removal

**Enable in Radarr/Sonarr** (Optional):
1. Go to **Settings** → **Download Client** → Click your Deluge client
2. Scroll to **Completed Download Handling**
3. Enable **"Remove Completed"**
4. Radarr/Sonarr will auto-remove torrents after seed goals are met

**Requirements for Auto-Removal**:
- Seed goals must be configured in Prowlarr (per indexer)
- Torrent must be **stopped/paused** in Deluge
- Torrent must remain in same category (`radarr-movies`, `sonarr-tv`)

### Common Issues

#### "Files Still Showing in Plex After Deletion"

**Cause**: Plex hasn't scanned for changes or trash not emptied

**Solution**:
1. Manually scan library: **Library** → **...** → **Scan Library Files**
2. Empty trash: **Library** → **...** → **Empty Trash**
3. Wait for scheduled scan (Overseerr triggers every 5 min)

#### "Torrent Still Seeding After Movie Removed"

**Cause**: This is expected behavior - torrents continue seeding independently

**Solution**:
- **If private tracker**: Let it seed to completion (protect your ratio)
- **If public tracker**: Manually remove from Deluge
- **If ratio met**: Stop torrent in Deluge, wait for Radarr/Sonarr auto-removal

#### "Disk Space Not Freed After Deletion"

**Cause**: Hardlink still exists in `/data/Downloads` (torrent still seeding)

**Solution**:
1. Check Deluge for active torrents: http://dev.local:8112
2. Verify file exists in downloads:
   ```bash
   ls -lh /Volumes/Samsung_T5/Downloads/
   ```
3. Remove torrent AND data from Deluge (or wait for seed completion)
4. Verify space freed: `df -h /Volumes/Samsung_T5/`

#### "Cannot Re-Request Deleted Media in Overseerr"

**Cause**: Media may still exist in Radarr/Sonarr database or Overseerr cache

**Solution**:
1. Verify complete removal from Radarr/Sonarr library
2. In Overseerr: **Media** → Find title → **Clear Media Data**
3. Wait 5-10 minutes for Overseerr to sync with Radarr/Sonarr
4. Try requesting again

### Automation Recommendations

**For hands-off operation**:

1. **Enable automatic Plex trash cleanup**:
   - **Settings** → **Library** → **Empty trash automatically after every scan**

2. **Enable automatic torrent removal** (after seed goals met):
   - Configure in Radarr/Sonarr download client settings
   - Set seed goals in Prowlarr per indexer

3. **Configure seed goals conservatively**:
   - Private trackers: Follow exact requirements + buffer (e.g., ratio 2.0, time 7 days)
   - Public trackers: Reasonable goals (e.g., ratio 1.5, time 3 days)

**Manual oversight recommended for**:
- Private tracker torrents (verify ratio requirements)
- Large files (ensure adequate seeding)
- Rare/hard-to-find media (contribute back to community)

## Monitoring & Health Checks

### Service Health Status

All services are configured with health checks that run automatically:

```bash
# View health status of all services
docker compose ps

# Check detailed health information
docker inspect --format='{{.State.Health.Status}}' <service-name>
```

Health check intervals:
- **Traefik**: Every 30s (ping endpoint)
- **Gluetun**: Every 60s (VPN connectivity)
- **Plex**: Every 30s (web interface)
- **Radarr/Sonarr**: Every 30s (API ping)
- **Prowlarr**: Every 30s (API ping)
- **Overseerr**: Every 30s (status endpoint)

### Automated Health Monitoring

The health monitoring system runs in a dedicated Docker container:

**Features:**
- ✅ Containerized (portable, no host dependencies)
- ✅ Automated checks every 15 minutes
- ✅ Monitors Docker service health status
- ✅ Verifies VPN connectivity (ensures real IP is hidden)
- ✅ Tracks disk space (alerts when below threshold)
- ✅ Sends color-coded Discord notifications
  - 🔴 Red: Service failures
  - ✅ Green: Service recoveries
  - ⚠️ Yellow: Low disk space
- ✅ State tracking (detects failures and recoveries)
- ✅ Separate alert cooldowns (failure vs recovery vs disk)
- ✅ Detailed logging to `logs/health-monitor.log`

**Container Management:**

```bash
# View monitoring logs
docker compose logs -f health-monitor

# Manual health check (verbose)
docker compose exec health-monitor /usr/local/bin/health-monitor.sh -v

# Restart monitoring container
docker compose restart health-monitor

# Rebuild after script changes
docker compose build health-monitor
docker compose up -d health-monitor
```

### Setting Up Discord Alerts

1. **Create Discord Webhook**:
   - Open Discord → Server Settings → Integrations → Webhooks
   - Click "New Webhook" or select existing one
   - Customize name (e.g., "Media Stack Alerts") and select channel
   - Click "Copy Webhook URL"

2. **Configure Webhook in .env**:
   ```bash
   DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/123456789/your-webhook-token

   # Optional: Customize thresholds
   DISK_SPACE_THRESHOLD=10          # Alert when < 10GB free
   ALERT_COOLDOWN=3600               # Wait 1 hour between duplicate alerts
   ```

3. **Test Alerts**:
   ```bash
   # Stop a service to trigger failure alert (red)
   docker compose stop radarr

   # Wait 15 minutes or trigger manual check
   docker compose exec health-monitor /usr/local/bin/health-monitor.sh -v

   # Check Discord for red failure alert

   # Restart service
   docker compose start radarr

   # Wait for recovery alert (green)
   docker compose exec health-monitor /usr/local/bin/health-monitor.sh -v
   ```

### Automated Monitoring Schedule

The health monitor container runs checks automatically every 15 minutes via cron (configured in `monitoring/crontab`).

**No host setup required** - monitoring runs entirely in the container.

**To change schedule**:
1. Edit `monitoring/crontab`
2. Rebuild container: `docker compose build health-monitor`
3. Restart: `docker compose up -d health-monitor`

**Recommended Review Schedule:**
- Automated: Every 15 minutes (handled by container)
- Manual log review: Daily (`docker compose logs health-monitor`)
- Service log review: Weekly

### Health Check Alerts

You'll receive Discord alerts for:

**Service Failures** (🔴 Red):
- Container stopped or crashed
- Health check failing
- Service becomes unresponsive
- Includes: service name and state transition (healthy → stopped)

**Service Recoveries** (✅ Green):
- Container restarted successfully
- Health check now passing
- Service restored to healthy state
- Includes: service name and state transition (stopped → healthy)

**VPN Issues** (🔴 Red):
- Gluetun container down
- VPN connection lost
- Public IP exposed
- Unable to verify VPN status

**Disk Space Warnings** (⚠️ Yellow):
- Free space below threshold (default: 10GB)
- Media disk not mounted
- Potential storage issues

**Alert Format:**
Discord alerts include:
- **Color-coded embeds** (red=failure, green=recovery, yellow=warning)
- **State transitions** (e.g., "radarr (healthy → stopped)")
- **Detailed description** of the issue
- **Suggested remediation** steps with commands
- **Timestamp** of when issue was detected

**Cooldown System:**
- Separate cooldowns for failures, recoveries, and disk alerts
- Default: 1 hour between duplicate alerts
- Prevents spam while ensuring important updates

### Viewing Logs

```bash
# View health monitor logs
tail -f logs/health-monitor.log

# View service logs
docker compose logs -f [service-name]

# View all logs from last hour
docker compose logs --since=1h

# Search logs for errors
docker compose logs | grep -i error
```

### Common Health Issues

#### Service Shows "unhealthy" Status

**Cause**: Health check endpoint failing

**Solution**:
1. Check service logs: `docker compose logs -f <service>`
2. Verify service is responding: `curl http://localhost:<port>/ping`
3. Restart service: `docker compose restart <service>`
4. If persists, recreate: `docker compose up -d --force-recreate <service>`

#### VPN Health Check Failing

**Cause**: VPN connection issue or tunnel down

**Solution**:
1. Check gluetun logs: `docker compose logs -f gluetun`
2. Verify VPN credentials in `.env`
3. Test connectivity: `docker exec gluetun wget -qO- ifconfig.me`
4. Restart gluetun: `docker compose restart gluetun`
5. Restart Deluge: `docker compose restart deluge`

#### Disk Space Alerts

**Cause**: Media disk filling up

**Solution**:
1. Check disk usage: `df -h /Volumes/Samsung_T5`
2. Find large files: `du -sh /Volumes/Samsung_T5/*`
3. Remove completed torrents: See "Deleting Movies and TV Shows" section
4. Check for stuck downloads in Deluge
5. Adjust threshold in `.env` if needed

## Backup & Disaster Recovery

The stack includes automated backup scripts for catastrophic recovery scenarios. Backups are infrequent (monthly recommended) and focused on configuration preservation, not daily versioning.

### What's Backed Up

**Included (~43MB, ~10-12MB compressed):**
- Service configurations and databases (`configs/`)
- Secrets and credentials (`.env`)
- Infrastructure definition (`docker-compose.yml`)
- Health monitoring scripts (`monitoring/`)
- Documentation

**Excluded:**
- Media files (626GB) - can be re-downloaded via Radarr/Sonarr
- Plex watch history - lost in drive failure
- Plex logs and cache
- Temporary files

### Creating Backups

**Manual backup:**
```bash
./backup/backup.sh
```

**Automated backup (via container):**
The backup container runs automatically based on schedule configured in `.env`:
```bash
# Default: Weekly on Monday at 3 AM
BACKUP_SCHEDULE=0 3 * * 1
```

**With remote sync:**
```bash
# Configure in .env
REMOTE_BACKUP_PATH="s3://my-bucket/backups"      # AWS S3
REMOTE_BACKUP_PATH="user@server:/backups"        # SSH/rsync
REMOTE_BACKUP_PATH="/Volumes/External/backups"   # Local path

# Run manual backup with sync
./backup/backup.sh --remote-sync
```

**Backup location:** `./backups/media-stack-backup_YYYYMMDD_HHMMSS.tar.gz`
**Retention:** Last 12 backups (~150MB total)

### Recovery Scenarios

#### Scenario A: Drive Re-mount (2-5 minutes)
**Situation:** Drive disconnected but data intact

```bash
# 1. Stop services
docker compose down

# 2. Re-mount drive at /Volumes/Samsung_T5
# 3. Verify data
ls /Volumes/Samsung_T5/{Movies,Shows,Downloads}

# 4. Restart services
docker compose up -d
```

**Result:** No data loss, all services restored

#### Scenario B: Complete Drive Failure (hours to days)
**Situation:** Drive died, all media lost (626GB)

```bash
# 1. Get replacement drive, mount at /Volumes/Samsung_T5
# 2. Stop services
docker compose down

# 3. Restore from backup
tar xzf backups/media-stack-backup_YYYYMMDD_HHMMSS.tar.gz

# 4. Recreate directory structure
mkdir -p /Volumes/Samsung_T5/{Downloads,Movies,Shows}

# 5. Start services
docker compose up -d

# 6. Re-download media
# In Radarr: Movies → Select All → Search All Missing
# In Sonarr: Series → Select All → Search All Missing
```

**Data Recovery:**
- ✅ Service settings and API keys
- ✅ Movie/show library lists (from databases)
- ✅ Indexer configurations
- ✅ Quality profiles and automations
- ❌ Actual media files (must re-download)
- ❌ Plex watch history
- ❌ Deluge seeding ratios

**For detailed recovery procedures, see:** [`DISASTER_RECOVERY.md`](DISASTER_RECOVERY.md)

### Disk Usage

| Retention | Uncompressed | Compressed |
|-----------|--------------|------------|
| 1 backup | 43MB | 10-12MB |
| 12 backups (1 year) | 516MB | 120-150MB |

## Important Notes

### TRaSH Guides Configuration
This setup follows [TRaSH Guides](https://trash-guides.info/) recommendations:
- ✅ Proper naming scheme (prevents download loops)
- ✅ Separate download/media directories
- ✅ Labels plugin for download client categorization
- ✅ Centralized indexer management via Prowlarr
- ✅ Quality profiles with upgrades enabled
- ✅ Seed goals in indexer settings (not download client)

### Hardlinks
All services mount `/Volumes/Samsung_T5` as `/data`, ensuring `/data/Downloads` and `/data/Movies` are on the same filesystem. This enables hardlinks for instant moves and space-efficient operations (file exists in both locations but only uses space once).

### Private Trackers
**CRITICAL:** Private trackers (like TorrentDay) require specific settings to avoid bans:

**Already Configured:**
- ✅ DHT disabled (`"dht": false`) - REQUIRED for private trackers
- ✅ LSD disabled (`"lsd": false`) - REQUIRED for private trackers
- ✅ PEX disabled (`"utpex": false`) - REQUIRED for private trackers
- ✅ UPnP disabled (`"upnp": false`) - Security best practice
- ✅ NAT-PMP disabled (`"natpmp": false`) - Security best practice
- ✅ Anonymous mode enabled - Reduces client info leakage

**Network Security:**
- Web UI bound to localhost only (127.0.0.1:8112)
- Daemon port bound to localhost only (127.0.0.1:58846)
- Only torrent ports (6881) exposed to network

## Security

### Current Setup

**✅ Implemented - Private Tracker Compliance:**
- DHT, LSD, PEX disabled (required for private trackers)
- UPnP, NAT-PMP disabled (prevents automatic port exposure)
- Anonymous mode enabled (reduces fingerprinting)
- Web UI restricted to localhost (127.0.0.1:8112)

**✅ Implemented - Data Security:**
- Secrets stored in `.env` file (not in version control)
- `.gitignore` prevents committing sensitive data
- Configs directory excluded from git (contains auto-generated API keys)

**✅ Implemented - VPN Protection:**
- All Deluge traffic routed through gluetun VPN container
- Using NordVPN via OpenVPN
- Automatic kill switch (if VPN disconnects, torrent traffic stops)
- No IP leaks possible (Deluge shares gluetun's network stack)

**⚠️ Still Needed for Production:**
- No HTTPS configured (reverse proxy recommended)
- Some services lack authentication
- No network isolation between services

### VPN Architecture

**Gluetun Container**
- Uses qmcgaw/gluetun image
- Connects to NordVPN via OpenVPN
- Creates isolated network namespace for VPN tunnel
- Exposes Deluge ports through VPN connection

**Deluge Network Routing**
- Uses `network_mode: "service:gluetun"`
- Shares gluetun's network stack (shares VPN tunnel)
- ALL traffic (torrent + web UI) goes through VPN
- If VPN fails, Deluge has no network access (kill switch)

**Port Mapping**
- Ports configured on gluetun (not Deluge)
- Web UI: 127.0.0.1:8112 (localhost only)
- Torrent: 6881 (TCP/UDP, for peer connections)
- Daemon: 127.0.0.1:58846 (localhost only)

**Changing VPN Server**

**Current setup:** VPN uses specific server `us5500.nordvpn.com` for reliability.

**Why:** NordVPN auth servers are unreliable when auto-selecting by country (known gluetun issue). Using a specific server avoids authentication failures.

**To change servers:**
1. Edit `docker-compose.yml`
2. Change `SERVER_HOSTNAMES=us5500.nordvpn.com` to a different server
3. Find server list: https://nordvpn.com/servers/tools/
4. Recreate container: `docker compose up -d gluetun`

**Recommended servers:** us####.nordvpn.com (US-based servers tend to be more reliable)

### Traefik Reverse Proxy

**Overview**
- Automatic HTTPS via Let's Encrypt
- Routes traffic to services based on domain
- HTTP to HTTPS redirect
- Dashboard protected with basic auth

**Services Exposed**
- `plex.${DOMAIN}` → Plex Media Server
- `requests.${DOMAIN}` → Overseerr
- `traefik.${DOMAIN}` → Traefik Dashboard (optional)

**DNS Configuration Required**
Create A records pointing to your public IP:
```
plex.example.com     → your-public-ip
requests.example.com → your-public-ip
traefik.example.com  → your-public-ip
```

**Port Forwarding Required**
Configure your router to forward:
- Port 80 (HTTP) → Docker host
- Port 443 (HTTPS) → Docker host

**Certificate Storage**
Let's Encrypt certificates stored in: `./configs/traefik/letsencrypt/acme.json`

**First-Time Setup**
1. Configure DNS records
2. Set up port forwarding
3. Update `.env` with domain and email
4. Generate basic auth: `htpasswd -nb admin yourpassword`
5. Start Traefik: `docker compose up -d traefik`
6. Check logs: `docker compose logs -f traefik`
7. Verify certificates: Look for "Certificate obtained for domain" messages

**Troubleshooting**
- Ensure ports 80/443 are accessible from internet
- Verify DNS propagation: `nslookup plex.yourdomain.com`
- Check Traefik logs for ACME errors
- Let's Encrypt has rate limits (5 certs/week per domain)

### Recommendations for Production
1. ✅ **VPN**: Implemented with gluetun + NordVPN
2. ✅ **Reverse Proxy**: Implemented with Traefik and Let's Encrypt (requires DNS/port forwarding setup)
3. **Authentication**: Enable on all services (especially Prowlarr/Radarr)
4. ✅ **Network Isolation**: Proxy network configured for Traefik-managed services
5. **Regular Updates**: Keep all containers up to date

### Secret Management
- **Never commit** `.env` file to version control
- **Rotate API keys** if they are ever exposed
- **Use strong passwords** for Deluge and other services
- **Backup configs** securely (they contain API keys)

## Adding Indexers

1. Access Prowlarr: http://dev.local:9696
2. Navigate to: **Indexers → Add Indexer**
3. Search for your indexer (public or private)
4. Configure credentials/settings
5. Test connection
6. Save

Indexers will automatically sync to Radarr within seconds.

### Recommended Public Indexers
- 1337x (general purpose)
- YTS (movies, smaller files)

### Seed Ratio Configuration (per TRaSH Guides)
Set in Prowlarr for each indexer:
- Minimum Seeders: 1
- Seed Ratio: 2.0
- Seed Time: 168 hours (7 days)

## Troubleshooting

### Check Service Logs
```bash
docker compose logs -f radarr
docker compose logs -f deluge
docker compose logs -f prowlarr
```

### Restart Services
```bash
docker compose restart radarr
docker compose restart deluge
```

### Test Connectivity
```bash
# From Radarr to Deluge
docker exec radarr nc -zv deluge 8112

# From Prowlarr to Radarr
docker exec prowlarr nc -zv radarr 7878
```

### Clear Download Client Category Issues
If Radarr can't set categories in Deluge:
1. Verify Labels plugin enabled in `configs/deluge/core.conf`
2. Restart Deluge: `docker compose restart deluge`
3. Test connection in Radarr: Settings → Download Clients → Test

## Next Steps

- [ ] Add indexers to Prowlarr
- [ ] Configure custom formats in Radarr (optional)
- [x] Set up Sonarr for TV shows
- [x] Set up Bazarr for subtitle automation
- [ ] Configure Bazarr subtitle providers and language preferences
- [ ] Configure notifications (Discord, Email, etc.)
- [ ] Set up Tautulli notifications for stream activity
- [x] Add VPN container for secure torrenting
- [x] Set up reverse proxy with HTTPS
- [x] Add Tautulli for Plex monitoring
- [ ] Configure DNS records for Traefik domains
- [ ] Set up router port forwarding (80, 443)

## Resources

- [TRaSH Guides](https://trash-guides.info/) - Configuration best practices
- [Radarr Wiki](https://wiki.servarr.com/radarr)
- [Prowlarr Wiki](https://wiki.servarr.com/prowlarr)
- [Deluge Documentation](https://dev.deluge-torrent.org/)
