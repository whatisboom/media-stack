# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted media automation stack using Docker Compose with VPN protection. Services work together to automate movie downloading, management, and streaming following [TRaSH Guides](https://trash-guides.info/) best practices.

**Key Features:**
- ✅ VPN-protected torrenting (NordVPN via gluetun)
- ✅ TRaSH Guides compliant (hardlinks, proper paths)
- ✅ Private tracker safe (DHT/LSD/PEX disabled)
- ✅ Centralized indexer management (Prowlarr)
- ✅ Reverse proxy with automatic HTTPS (Traefik + Let's Encrypt)

## Architecture

### Service Dependencies & Data Flow

```
Overseerr (Requests)
    ↓
    ├─→ Radarr (Movie Management) ──┐
    │           ↓                    │
    │      Bazarr (Subtitles) ───────┤
    │                                │
    └─→ Sonarr (TV Management) ──────┤
                ↓                    │
           Bazarr (Subtitles) ───────┘
                                     ↓
                            Prowlarr (Indexer Management)
                                     ↓
                       Deluge (Download Client) ──→ Gluetun (VPN Container)
                                     ↓                       ↓
                            Plex (Media Streaming)    NordVPN (Wireguard)
                                     ↓
                            Tautulli (Plex Monitoring)
```

**Movie Request Flow:**
1. Overseerr receives movie request
2. Radarr searches indexers (managed by Prowlarr)
3. Radarr sends torrent to Deluge with category `radarr-movies`
4. Deluge downloads to `/data/Downloads`
5. Radarr hardlinks/moves from `/data/Downloads` to `/data/Movies` with proper naming
6. Plex scans `/data/Movies` and makes available for streaming

**TV Show Request Flow:**
1. Overseerr receives TV show request
2. Sonarr searches indexers (managed by Prowlarr)
3. Sonarr sends torrent to Deluge with category `sonarr-tv`
4. Deluge downloads to `/data/Downloads`
5. Sonarr hardlinks/moves from `/data/Downloads` to `/data/Shows` with proper naming
6. Plex scans `/data/Shows` and makes available for streaming

**Subtitle Download Flow:**
1. Bazarr monitors Radarr and Sonarr for new media
2. When new movie/episode is added, Bazarr searches configured subtitle providers
3. Bazarr downloads subtitles based on language preferences and quality settings
4. Subtitles saved alongside media files in `/data/Movies` or `/data/Shows`
5. Plex automatically detects and uses subtitles

**Compression & Storage Management Flow:**
1. Radarr/Sonarr remove torrents from Deluge after seeding goals met (72h OR 2.0 ratio)
2. Files remain in `/data/Downloads` after torrent removal
3. Compressor service runs daily (3 AM) to find orphaned video files
4. For each file in Downloads, compressor finds matching file in Movies/Shows
5. Compressor encodes to HEVC (x265) with CRF 23 for 40-50% size reduction
6. Atomically replaces original file in media library (preserves Plex metadata)
7. Deletes original from `/data/Downloads`
8. Triggers Plex library scan
9. Sends Discord notification with space saved

### Volume Architecture

**Critical: TRaSH Guides Compliant Unified Mount**
- All services mount parent directory: `/Volumes/Samsung_T5` → `/data`
- This ensures `/data/Downloads`, `/data/Movies`, and `/data/Shows` appear as same filesystem
- Hardlinks work properly (instant moves, no duplicate storage)

**Volume Mappings:**
- All Services: `/Volumes/Samsung_T5` → `/data`
  - Downloads visible at: `/data/Downloads`
  - Movies visible at: `/data/Movies`
  - TV Shows visible at: `/data/Shows`
- Configs: `./configs/[service]` → service-specific paths

**Why This Structure:**
- Avoids "split mount" problem that breaks hardlinks
- Radarr and Sonarr can see both download source and import destination
- No remote path mapping needed

### Network Architecture

**Network Segmentation (Least-Privilege Isolation):**
The stack uses isolated Docker networks to limit lateral movement and enforce security boundaries:

1. **proxy** - Public-facing services
   - Traefik (reverse proxy)
   - Plex (media streaming)
   - Overseerr (request management)

2. **media** - Media consumption
   - Plex (media server)
   - Tautulli (monitoring)
   - Compressor (storage optimization, needs Plex API access)

3. **automation** - Media management (*arr stack)
   - Radarr (movies)
   - Sonarr (TV shows)
   - Bazarr (subtitles)
   - Prowlarr (indexers)
   - Overseerr (connects automation → media)

4. **download** - Torrenting (isolated)
   - Gluetun (VPN tunnel)
   - Deluge (torrent client via gluetun)

5. **monitoring** - Health checks (read-only)
   - health-monitor (connects to all networks for status checks)
   - Watchtower (update monitoring)

**VPN Isolation (Critical Security Layer):**
- Gluetun creates isolated network namespace
- Deluge uses `network_mode: "service:gluetun"` (shares gluetun's network)
- Deluge traffic ONLY goes through VPN tunnel
- If VPN disconnects, Deluge loses all network access (kill switch)

**Fail2ban Protection:**
- Operates at host network level (`network_mode: host`)
- Monitors service logs for auth failures
- Automatically bans IPs via iptables
- Protects: Radarr, Sonarr, Prowlarr, Overseerr, Plex

**Reverse Proxy (Traefik):**
- Dedicated `proxy` bridge network for Traefik-managed services
- Automatic HTTPS via Let's Encrypt (HTTP-01 challenge)
- Routes based on domain rules (Host headers)
- HTTP → HTTPS redirect on all services

**Inter-Service Communication:**
Services can only communicate with others on their shared networks:
- Radarr/Sonarr → Deluge: `gluetun:8112` (automation + download networks)
- Radarr/Sonarr ← Prowlarr: `radarr:7878`, `sonarr:8989` (automation network)
- Radarr/Sonarr → Bazarr: `radarr:7878`, `sonarr:8989` (automation network)
- Overseerr → Plex: `plex:32400` (media network)
- Overseerr → Radarr/Sonarr: `radarr:7878`, `sonarr:8989` (automation network)
- Tautulli → Plex: `plex:32400` (media network)
- External → Services: via Traefik (proxy network, domain-based routing)

**Network Isolation Benefits:**
- ✅ Radarr cannot directly access Plex
- ✅ Deluge isolated in download network (VPN-only)
- ✅ Fail2ban protects all exposed services
- ✅ Lateral movement limited by network boundaries

**Port Exposure:**
- Traefik: 80 (HTTP), 443 (HTTPS) - publicly accessible
- Gluetun exposes Deluge's ports (8112, 6881, 58846)
- Deluge Web UI restricted to localhost (127.0.0.1:8112)
- Only torrent port (6881) accessible from network

## Development Commands

### Docker Operations

```bash
# Start all services
docker compose up -d

# View logs (follow mode)
docker compose logs -f [service-name]

# Restart service after config changes
docker compose restart [service-name]

# Rebuild and recreate (force config reload)
docker compose up -d --force-recreate

# Stop all services
docker compose down
```

### Maintenance Mode

To avoid false-positive alerts when restarting services or performing maintenance:

```bash
# Stop health monitor before maintenance
docker compose stop health-monitor-alerts

# Perform your maintenance (restart services, make changes, etc.)
docker compose restart plex-media-server
docker compose up -d --force-recreate

# Restart health monitor when done
docker compose start health-monitor-alerts
```

**Note:** For quick service restarts, you can optionally skip stopping the health-monitor. Services typically report as "healthy" within 30-60 seconds after restart.

### Service-Specific Commands

```bash
# Test connectivity between services
docker exec radarr nc -zv gluetun 8112  # Note: deluge is via gluetun
docker exec sonarr nc -zv gluetun 8112
docker exec bazarr nc -zv radarr 7878
docker exec bazarr nc -zv sonarr 8989
docker exec prowlarr nc -zv radarr 7878
docker exec prowlarr nc -zv sonarr 8989
docker exec tautulli nc -zv plex 32400

# Access service shells
docker exec -it radarr /bin/bash
docker exec -it sonarr /bin/bash
docker exec -it bazarr /bin/bash
docker exec -it deluge /bin/bash
docker exec -it tautulli /bin/bash
docker exec -it gluetun sh

# Check VPN status and public IP
docker compose logs gluetun --tail=20
docker exec gluetun wget -qO- ifconfig.me
docker exec gluetun wget -qO- http://ipinfo.io/country

# Check Traefik status and certificate generation
docker compose logs traefik --tail=50
docker compose logs traefik | grep -i "certificate"

# Run media compression manually
./scripts/compress-media.sh                # Run compression now
./scripts/compress-media.sh --dry-run      # Test without making changes

# Check compression logs
docker compose logs compressor --tail=50
tail -f logs/compressor.log
```

## Configuration Management

### Secret Handling

**CRITICAL:** Never commit `.env` or `configs/` directory
- `.env`: User-configured secrets (Plex token, Deluge password)
- `configs/`: Auto-generated API keys, databases, app state

**API Key Locations:**
- Radarr: `configs/radarr/config.xml`
- Sonarr: `configs/sonarr/config.xml`
- Bazarr: `configs/bazarr/config/config.ini`
- Prowlarr: `configs/prowlarr/config.xml`
- Overseerr: `configs/overseerr/settings.json`
- Tautulli: `configs/tautulli/config.ini`
- Deluge: `configs/deluge/auth`

### Service Configuration Files

**Radarr** (`configs/radarr/config.xml`):
- Quality profiles
- Naming scheme (TRaSH Guides compliant)
- Download client settings
- Indexer connections (synced from Prowlarr)
- **Seeding goals** (Settings → Indexers → [Indexer]):
  - Seed Ratio: 2.0 (exceeds TorrentDay minimum)
  - Seed Time: 4320 minutes (72 hours)
  - Enables automatic torrent removal after goals met

**Sonarr** (`configs/sonarr/config.xml`):
- Quality profiles
- Naming scheme (TRaSH Guides compliant for TV shows)
- Download client settings
- Indexer connections (synced from Prowlarr)
- Series type settings (Standard, Daily, Anime)
- **Seeding goals** (Settings → Indexers → [Indexer]):
  - Seed Ratio: 2.0
  - Seed Time: 4320 minutes (72 hours)
  - Works with Completed Download Handling to remove torrents

**Bazarr** (`configs/bazarr/config/config.ini`):
- Radarr and Sonarr connection settings
- Subtitle language preferences
- Subtitle provider configurations (OpenSubtitles, Subscene, etc.)
- Subtitle search and download automation settings
- Path mappings for media files

**Deluge** (`configs/deluge/core.conf`):
- Download path: `/data/Downloads`
- Seed ratios and time limits
- Port configuration
- Plugin settings (Labels plugin required for categorization)
- **Security settings** (CRITICAL for private trackers):
  - DHT disabled (`"dht": false`) - Required for TorrentDay
  - LSD disabled (`"lsd": false`) - Required for TorrentDay
  - PEX disabled (`"utpex": false`) - Required for TorrentDay
  - UPnP/NAT-PMP disabled - Security hardening
  - Anonymous mode enabled - Privacy

**Prowlarr** (`configs/prowlarr/config.xml`):
- Indexer definitions
- App sync configuration (Radarr and Sonarr connections)
- Category mappings

**Traefik** (`configs/traefik/letsencrypt/acme.json`):
- Let's Encrypt SSL certificates
- Automatically generated and renewed
- File must have 600 permissions
- Contains private keys - DO NOT commit to version control

**Traefik Configuration** (docker-compose.yml labels):
- Routing rules: Domain-based routing via Host() matcher
- TLS: Automatic cert resolver via Let's Encrypt
- Entrypoints: web (80) and websecure (443)
- Middleware: Basic auth for dashboard

**Tautulli** (`configs/tautulli/config.ini`):
- Plex connection settings (URL and token)
- Notification agent configurations
- User and library settings
- Watch history and statistics database
- Optional Plex logs path for LogViewer feature

**Compressor** (`.env` configuration):
- **COMPRESSION_CRF**: Quality setting (23 = visually lossless, 28 = aggressive)
- **COMPRESSION_PRESET**: Encoding speed (slow = better compression, fast = quicker)
- **COMPRESSION_SCHEDULE**: Cron schedule (default: `0 3 * * *` = 3 AM daily)
- **MIN_COMPRESSION_RATIO**: Only keep compressed if <80% original size
- **DRY_RUN**: Set to `true` to test without making changes
- Automatically compresses video files after torrent removal
- Uses HEVC (x265) codec for 40-50% space savings
- Preserves Plex metadata and watch history

## TRaSH Guides Compliance

This setup follows TRaSH Guides best practices:

1. **Naming Scheme**: Prevents download loops by using consistent format
   - **Movies (Radarr)**: `{Movie CleanTitle} {(Release Year)} {{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo AudioCodec} {MediaInfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}`
   - **TV Shows (Sonarr)**: Configure per TRaSH Guides TV naming recommendations

2. **Directory Structure**: Separate download/media directories for hardlinks

3. **Download Client**: Labels plugin enabled for category management

4. **Indexer Management**: Centralized in Prowlarr with auto-sync to apps

5. **Seed Goals**: Configured per indexer (not in download client)

## Common Issues

### Radarr Can't Connect to Deluge
- Verify gluetun is running: `docker compose ps gluetun`
- Check VPN connection: `docker compose logs gluetun --tail=20`
- Radarr must connect to `gluetun:8112` (not `deluge:8112`)
- Test connectivity: `docker exec radarr nc -zv gluetun 8112`

### Radarr Can't Set Categories in Deluge
- Verify Labels plugin enabled in `configs/deluge/core.conf`
- Restart both containers: `docker compose restart gluetun deluge`
- Test in Radarr: Settings → Download Clients → Test

### Sonarr Can't Connect to Deluge
- Verify gluetun is running: `docker compose ps gluetun`
- Check VPN connection: `docker compose logs gluetun --tail=20`
- Sonarr must connect to `gluetun:8112` (not `deluge:8112`)
- Test connectivity: `docker exec sonarr nc -zv gluetun 8112`

### Sonarr Can't Set Categories in Deluge
- Verify Labels plugin enabled in `configs/deluge/core.conf`
- Restart both containers: `docker compose restart gluetun deluge`
- Test in Sonarr: Settings → Download Clients → Test

### Downloads Not Importing
- Check paths match: Radarr/Sonarr sees `/data/Downloads` where Deluge downloads
- Verify root folder set to `/data/Movies` in Radarr or `/data/Shows` in Sonarr
- Verify hardlinks working (same filesystem, all under `/data`)
- Check logs: `docker compose logs -f radarr` or `docker compose logs -f sonarr`

### Prowlarr Indexers Not Syncing
- Verify Radarr/Sonarr API keys in Prowlarr app settings
- Check network connectivity: `docker exec prowlarr nc -zv radarr 7878` or `docker exec prowlarr nc -zv sonarr 8989`
- Force sync in Prowlarr UI

### Plex Not Seeing New Media
- Verify volume mount: `/Volumes/Samsung_T5` mounted to `/data`
- Verify library paths set correctly in Plex:
  - Movies: `/data/Movies`
  - TV Shows: `/data/Shows`
- Check Overseerr scheduled job (Plex scan every 5 min)
- Manual scan: Plex UI → Library → Scan Library Files

### Traefik Certificate Issues
- Check Traefik logs: `docker compose logs traefik | grep -i "acme\|certificate"`
- Verify DNS records pointing to correct IP: `nslookup plex.${DOMAIN}`
- Verify ports 80/443 forwarded to Docker host
- Check Let's Encrypt rate limits (5 certs/week per domain)
- Verify domain is publicly accessible: `curl -I http://${DOMAIN}`
- Delete `configs/traefik/letsencrypt/acme.json` to retry cert generation

### Traefik Not Routing to Service
- Verify service is on `proxy` network in docker-compose.yml
- Check Traefik labels on service (traefik.enable=true, routers, etc.)
- Verify service is running: `docker compose ps`
- Check Traefik dashboard for registered routers and services
- Test internal connectivity: `docker exec traefik wget -O- http://plex:32400`

### Tautulli Can't Connect to Plex
- Verify Plex is running: `docker compose ps plex`
- Test connectivity: `docker exec tautulli nc -zv plex 32400`
- Use Plex URL: `http://plex:32400` (Docker network)
- Get Plex token from: Settings → General → X-Plex-Token parameter in browser
- Check logs: `docker compose logs -f tautulli`

### Tautulli Not Showing Stream Activity
- Verify Plex connection in Tautulli: Settings → Plex Media Server
- Check Plex token is valid
- Verify Tautulli has permissions to access Plex
- Check activity feed refresh interval in Tautulli settings
- Restart Tautulli: `docker compose restart tautulli`

### Bazarr Can't Connect to Radarr/Sonarr
- Verify Radarr/Sonarr are running: `docker compose ps radarr sonarr`
- Test connectivity: `docker exec bazarr nc -zv radarr 7878` or `docker exec bazarr nc -zv sonarr 8989`
- Use correct URLs in Bazarr settings:
  - Radarr: `http://radarr:7878`
  - Sonarr: `http://sonarr:8989`
- Verify API keys are correct (copy from Radarr/Sonarr UI)
- Check logs: `docker compose logs -f bazarr`

### Bazarr Not Downloading Subtitles
- Verify subtitle providers are configured and enabled
- Check provider credentials (if required)
- Verify language profiles are set correctly
- Check path mappings in Bazarr match Radarr/Sonarr paths
- Verify Bazarr has write permissions to media directories
- Check minimum score threshold in subtitle settings
- Review logs: `docker compose logs -f bazarr`

### Torrents Not Being Removed After Seeding
- Verify per-indexer seeding goals configured in Radarr/Sonarr (Settings → Indexers → [Indexer])
- Check "Remove" enabled in Completed Download Handling (Settings → Download Clients)
- Verify Deluge config has `"remove_seed_at_ratio": true` in `configs/deluge/core.conf`
- Check Radarr/Sonarr logs: `docker compose logs radarr | grep -i "remov"`
- Manually test: Add a movie, wait for it to seed, verify torrent removed

### Compressor Not Running or Finding Files
- Check if compressor is running: `docker compose ps compressor`
- Verify scheduled time in .env: `COMPRESSION_SCHEDULE=0 3 * * *`
- Check logs: `docker compose logs compressor` or `tail -f logs/compressor.log`
- Verify files exist in `/data/Downloads` with no active torrent
- Test manually: `./scripts/compress-media.sh --dry-run`
- Check Discord webhook configured: `DISCORD_WEBHOOK_URL` in .env

### Compression Failed or Poor Quality
- Check ffmpeg errors in logs: `docker compose logs compressor`
- Verify sufficient disk space for temporary files (needs 2x file size free)
- Adjust CRF for quality: Lower = better quality (23-28 recommended)
- Change preset for speed: `fast` encodes quicker, `slow` compresses better
- Test single file: Run manually with `--dry-run` first
- Verify compressed file plays: Open in Plex before deletion confirmed

### Plex Not Detecting Compressed Files
- Verify Plex running: `docker compose ps plex`
- Manually trigger scan: Plex UI → Library → Scan Library Files
- Check Plex logs: `docker compose logs plex | grep -i scan`
- Verify file permissions: Compressor should preserve ownership
- Check watch history: Should be preserved if filename unchanged

### VPN Connectivity Alerts (False Positives)
- Symptom: Discord alerts "Unable to determine VPN public IP" but VPN is working
- Cause: Gluetun uses DNS-over-TLS (port 853) which can timeout through VPN
- Check gluetun logs: `docker compose logs gluetun | grep -i "dns\|timeout"`
- Verify VPN working: `docker exec gluetun wget -qO- https://api.ipify.org`
- Health monitor now retries 3 times before alerting (as of commit eb65747)
- If alerts persist: Consider switching gluetun to plain DNS (see docker-compose.yml DNS_UPSTREAM_RESOLVER_TYPE)
- Gluetun container may show as "unhealthy" during DNS timeouts but VPN tunnel still works

## Access URLs

**Internal Access** (local network):
- Plex: http://dev.local:32400
- Tautulli: http://dev.local:8181
- Radarr: http://dev.local:7878
- Sonarr: http://dev.local:8989
- Bazarr: http://dev.local:6767
- Prowlarr: http://dev.local:9696
- Overseerr: http://dev.local:5055
- Deluge: http://dev.local:8112

**External Access** (via Traefik, requires DNS + port forwarding):
- Plex: https://plex.${DOMAIN}
- Overseerr: https://requests.${DOMAIN}
- Traefik Dashboard: https://traefik.${DOMAIN} (basic auth required)

## Backup & Disaster Recovery

### Automated Backup System

**Container-Based Backup:**
- Backup service is run-once container (manual execution)
- Configured as Docker Compose profile: `--profile tools`
- No host dependencies required (fully portable)
- Automatic retention: Keeps last 12 backups (~80-100MB each)
- Remote sync: Cloudflare R2 (r2:media-stack) with --remote-sync flag

**What's Backed Up:**
- Service configurations and databases (`configs/`)
- **Plex databases** (watch history, library metadata ~1MB)
- Environment variables (`.env`)
- Infrastructure definition (`docker-compose.yml`)
- Monitoring scripts (`monitoring/`)
- Documentation files

**What's NOT Backed Up:**
- Media files (re-downloadable via Radarr/Sonarr)
- Plex logs, cache, and crash reports (excluded)
- Plex SQLite temporary files (WAL/SHM)

**Manual Backup:**
```bash
# Run backup manually (local only)
./backup/backup.sh

# With remote sync to R2
./backup/backup.sh --remote-sync

# Or via Docker Compose
docker compose --profile tools up backup
```

**Plex Database Checkpoints:**
For risky operations (batch imports, major changes), create safety checkpoints:
```bash
# Create checkpoint before risky operation
./scripts/plex-checkpoint.sh create

# List available checkpoints
./scripts/plex-checkpoint.sh list

# Restore from checkpoint (requires Plex stopped)
docker compose stop plex
./scripts/plex-checkpoint.sh restore 20251030_041500
docker compose start plex
```

Checkpoints are lightweight (~6.5MB), keep last 7, and provide quick recovery from database corruption.

**Remote Sync:**
Configure in `.env` to automatically sync backups to cloud storage:
```bash
# Cloudflare R2 (recommended - 10GB free, zero egress fees)
REMOTE_BACKUP_PATH=r2:media-stack-backups

# AWS S3
REMOTE_BACKUP_PATH=s3://my-bucket/backups

# SSH/rsync
REMOTE_BACKUP_PATH=user@server:/backups

# Local path
REMOTE_BACKUP_PATH=/Volumes/External/backups
```

**Disaster Recovery:**
- See `DISASTER_RECOVERY.md` for detailed recovery procedures
- Two scenarios covered: Drive re-mount (5 min) and complete drive failure (hours-days)
- Service configs fully recoverable from backup
- Media requires re-downloading (automated via Radarr/Sonarr)

### Plex Database Protection

**Problem:** Plex uses SQLite databases that can corrupt during rapid batch imports or concurrent write operations.

**Prevention Strategies:**

1. **Safe Batch Import Procedure** (for importing multiple movies/shows manually):
   ```bash
   # 1. Create checkpoint before import
   ./scripts/plex-checkpoint.sh create

   # 2. Import files via Radarr/Sonarr Manual Import
   #    (Use Radarr UI → Library Import or Sonarr UI → Library Import)

   # 3. Wait for all imports to complete

   # 4. Verify no errors in Plex logs
   docker compose logs plex --tail=50 | grep -i error

   # 5. If corruption detected, restore checkpoint:
   docker compose stop plex
   ./scripts/plex-checkpoint.sh restore <timestamp>
   docker compose start plex
   ```

2. **Rate Limiting** - When manually adding torrents for multiple movies:
   - Add 1-2 at a time, wait for import to complete
   - Avoid adding 4+ movies simultaneously
   - Let Plex finish scanning before adding next batch

3. **Database Monitoring:**
   - Check logs periodically: `docker compose logs plex | grep -i "database\|corruption"`
   - Database size: Should grow gradually, not jump suddenly
   - Normal size: ~1-2MB per 100 movies

**Recovery from Corruption:**
1. Stop Plex: `docker compose stop plex`
2. Restore from checkpoint: `./scripts/plex-checkpoint.sh restore <timestamp>`
3. OR restore from stack backup: Extract Plex databases from backup tarball
4. Start Plex: `docker compose start plex`
5. Verify functionality, trigger manual library scan if needed

**Root Cause:** SQLite WAL (Write-Ahead Logging) mode can fail to checkpoint during rapid concurrent writes. Plex scans trigger metadata writes for each file simultaneously.

## Security & Privacy

### Private Tracker Configuration
**CRITICAL:** TorrentDay (and other private trackers) will ban you if these are enabled:
- ❌ DHT (Distributed Hash Table)
- ❌ LSD (Local Service Discovery)
- ❌ PEX (Peer Exchange)

**Current Status:** ✅ All disabled in `configs/deluge/core.conf`

### Network Exposure
**Web UI Access:**
- Deluge: `127.0.0.1:8112` (localhost only)
- Other services: `0.0.0.0:port` (network accessible)

**Torrent Ports:**
- 6881 (TCP/UDP) exposed for incoming connections

### VPN Status
**✅ CONFIGURED:** Gluetun VPN container with NordVPN Wireguard (NordLynx)
- All Deluge traffic routes through VPN tunnel
- Kill switch enabled (network_mode prevents IP leaks)
- VPN credentials in `.env` (NORDVPN_PRIVATE_KEY, NORDVPN_ADDRESSES)
- Current server: us5500.nordvpn.com (hardcoded in docker-compose.yml)
- **Protocol:** Wireguard (4x faster than OpenVPN, more reliable)

**Getting Wireguard Credentials:**
1. Generate NordVPN access token: https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/
2. Get your private key via API:
```bash
curl -s -u token:YOUR_ACCESS_TOKEN https://api.nordvpn.com/v1/users/services/credentials | grep -o '"nordlynx_private_key":"[^"]*"' | cut -d'"' -f4
```
3. Add to `.env`:
```bash
NORDVPN_PRIVATE_KEY=<paste_private_key_from_step_2>
NORDVPN_ADDRESSES=10.5.0.2/32  # Standard for all NordVPN Wireguard
```

**Checking VPN Connection:**
```bash
# View gluetun logs to see VPN status (should see "Wireguard" not "OpenVPN")
docker compose logs gluetun --tail=50

# Check Deluge's public IP (should be VPN IP, not your real IP)
docker exec gluetun wget -qO- ifconfig.me

# Verify Wireguard connection (should see "Wireguard setup is complete")
docker compose logs gluetun | grep -i "wireguard"
```

**Changing VPN Server:**
```bash
# Edit docker-compose.yml and change SERVER_HOSTNAMES value
# Then recreate container (not just restart):
docker compose up -d gluetun

# Recreate Deluge to reconnect to new gluetun network namespace:
docker compose up -d deluge
```

## Important Notes

- Plex claim token expires in 4 minutes after generation
- Deluge default username: `admin` (password set in `.env`)
- First-time setup requires accessing each service to complete initial configuration
- API keys auto-generate on first run and persist in `configs/` directory
- **Private tracker compliance:** DHT/LSD/PEX must stay disabled

### Required UI Configuration After Volume Changes

After changing volume mounts, update paths in service UIs:

**Radarr** (http://dev.local:7878):
- Settings → Media Management → Root Folders
  - Update existing root folder from `/movies` to `/data/Movies`
  - OR delete old and add new root folder
- Settings → Download Clients → Deluge
  - Verify "Remote Path" shows `/data/Downloads`

**Sonarr** (http://dev.local:8989):
- Settings → Media Management → Root Folders
  - Add root folder: `/data/Shows`
- Settings → Download Clients → Deluge
  - Host: `gluetun` (NOT `deluge`)
  - Port: `8112`
  - Password: from `.env` DELUGE_WEB_PASSWORD
  - Category: `sonarr-tv`
  - Remote Path: `/data/Downloads`

**Plex** (http://dev.local:32400):
- Library Settings
  - Movies: `/data/Movies`
  - TV Shows: `/data/Shows` (add new library if needed)
  - OR remove and re-add libraries with new paths

**Prowlarr** (http://dev.local:9696):
- Settings → Apps → Add Application
  - Add Sonarr:
    - Sync Level: Full Sync
    - Sonarr Server: `http://sonarr:8989`
    - API Key: from Sonarr UI (Settings → General → Security)
  - Radarr should already be configured

### Required Seeding Goals Configuration

**CRITICAL:** These settings enable automatic torrent removal after seeding requirements are met.

**Option 1: Configure in Radarr/Sonarr (Recommended if not using Prowlarr Full Sync)**

**Radarr** (http://dev.local:7878):
- Settings → Indexers → [Click your TorrentDay indexer]
  - **Seed Ratio**: `2.0` (exceeds TorrentDay minimum of 1.0)
  - **Seed Time**: `4320` (72 hours in minutes)

**Sonarr** (http://dev.local:8989):
- Settings → Indexers → **Click "Show Advanced" button at the top** (Required!)
  - [Click your TorrentDay indexer]
  - **Seed Ratio**: `2.0`
  - **Seed Time**: `4320` (72 hours in minutes)
  - Note: These are Advanced options, hidden by default

**IMPORTANT: Prowlarr Sync Mode Consideration**

⚠️ **Prowlarr does NOT have seed ratio/time settings.** If you use Prowlarr's "Full Sync" mode, it may overwrite seed goals configured in Radarr/Sonarr.

**Recommended Solution:**
Change Prowlarr sync mode to **"Add and Remove Only"**:
- Prowlarr → Settings → Apps → [Edit Radarr/Sonarr connections]
- Change **Sync Level** from `Full Sync` to `Add and Remove Only`
- This allows you to configure seed goals in Radarr/Sonarr without them being overwritten

**Enable Completed Download Handling:**

Both Radarr and Sonarr need this enabled to actually remove torrents:
- **Radarr**: Settings → Download Clients → Completed Download Handling → Enable "Remove" checkbox
- **Sonarr**: Settings → Download Clients → Completed Download Handling → Enable "Remove" checkbox

**Overseerr** (http://dev.local:5055):
- Settings → Radarr
  - Update root folder to `/data/Movies`
- Settings → Sonarr (if configured)
  - Sonarr Server: `http://sonarr:8989`
  - API Key: from Sonarr UI
  - Root folder: `/data/Shows`

**Bazarr** (http://dev.local:6767):
- Settings → Radarr
  - Enabled: Yes
  - Hostname or IP: `radarr`
  - Port: `7878`
  - API Key: from Radarr UI (Settings → General → Security)
  - Path Mappings: Not required (unified `/data` mount)
- Settings → Sonarr
  - Enabled: Yes
  - Hostname or IP: `sonarr`
  - Port: `8989`
  - API Key: from Sonarr UI (Settings → General → Security)
  - Path Mappings: Not required (unified `/data` mount)
- Settings → Languages
  - Configure preferred subtitle languages
- Settings → Providers
  - Enable and configure subtitle providers (OpenSubtitles, Subscene, etc.)
