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
                            Plex (Media Streaming)    NordVPN (OpenVPN)
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

**Sonarr** (`configs/sonarr/config.xml`):
- Quality profiles
- Naming scheme (TRaSH Guides compliant for TV shows)
- Download client settings
- Indexer connections (synced from Prowlarr)
- Series type settings (Standard, Daily, Anime)

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

**Container-Based Scheduling:**
- Backup service runs continuously with built-in cron (dcron)
- No host dependencies required (fully portable)
- Schedule configured via `.env`: `BACKUP_SCHEDULE=0 3 * * 1` (Weekly Monday 3 AM)
- Automatic retention: Keeps last 12 backups (~150MB total)

**What's Backed Up:**
- Service configurations and databases (`configs/`)
- Environment variables (`.env`)
- Infrastructure definition (`docker-compose.yml`)
- Monitoring scripts (`monitoring/`)
- Documentation files

**What's NOT Backed Up:**
- Media files (626GB) - Re-downloadable via Radarr/Sonarr
- Plex watch history - Lost in drive failure
- Plex logs and cache

**Manual Backup:**
```bash
# Run backup manually
./backup/backup.sh

# With remote sync
./backup/backup.sh --remote-sync

# Or via container
docker compose exec backup /usr/local/bin/backup.sh
```

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
**✅ CONFIGURED:** Gluetun VPN container with NordVPN
- All Deluge traffic routes through VPN tunnel
- Kill switch enabled (network_mode prevents IP leaks)
- VPN credentials in `.env` (NORDVPN_USER, NORDVPN_PASSWORD)
- Current server: us5500.nordvpn.com (hardcoded in docker-compose.yml)
- **Note:** Using specific server instead of country-based auto-selection due to NordVPN auth reliability issues

**Checking VPN Connection:**
```bash
# View gluetun logs to see VPN status
docker compose logs gluetun --tail=50

# Check Deluge's public IP (should be VPN IP, not your real IP)
docker exec gluetun wget -qO- ifconfig.me

# Verify VPN is connected (should see "Initialization Sequence Completed")
docker compose logs gluetun | grep -i "initialized\|completed"
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
