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
Radarr (Movie Management) → Prowlarr (Indexer Management)
    ↓
Deluge (Download Client) ──→ Gluetun (VPN Container)
    ↓                              ↓
Plex (Media Streaming)      NordVPN (OpenVPN)
```

**Request Flow:**
1. Overseerr receives movie request
2. Radarr searches indexers (managed by Prowlarr)
3. Radarr sends torrent to Deluge with category `radarr-movies`
4. Deluge downloads to `/data/Downloads`
5. Radarr hardlinks/moves from `/data/Downloads` to `/data/Movies` with proper naming
6. Plex scans `/data/Movies` and makes available for streaming

### Volume Architecture

**Critical: TRaSH Guides Compliant Unified Mount**
- All services mount parent directory: `/Volumes/Samsung_T5` → `/data`
- This ensures `/data/Downloads` and `/data/Movies` appear as same filesystem
- Hardlinks work properly (instant moves, no duplicate storage)

**Volume Mappings:**
- All Services: `/Volumes/Samsung_T5` → `/data`
  - Downloads visible at: `/data/Downloads`
  - Movies visible at: `/data/Movies`
- Configs: `./configs/[service]` → service-specific paths

**Why This Structure:**
- Avoids "split mount" problem that breaks hardlinks
- Radarr can see both download source and import destination
- No remote path mapping needed

### Network Architecture

**VPN Isolation:**
- Gluetun creates isolated network namespace
- Deluge uses `network_mode: "service:gluetun"` (shares gluetun's network)
- Deluge traffic ONLY goes through VPN tunnel
- If VPN disconnects, Deluge loses all network access (kill switch)

**Reverse Proxy (Traefik):**
- Dedicated `proxy` bridge network for Traefik-managed services
- Automatic HTTPS via Let's Encrypt (HTTP-01 challenge)
- Routes based on domain rules (Host headers)
- HTTP → HTTPS redirect on all services
- Services on proxy network: Traefik, Plex, Overseerr

**Inter-Service Communication:**
- Radarr → Deluge: `gluetun:8112` (Deluge accessible via gluetun's network)
- Prowlarr → Radarr: `radarr:7878`
- Overseerr → Plex: `plex:32400`
- Overseerr → Radarr: `radarr:7878`
- External → Services: via Traefik (domain-based routing)

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
docker exec prowlarr nc -zv radarr 7878

# Access service shells
docker exec -it radarr /bin/bash
docker exec -it deluge /bin/bash
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
- Prowlarr: `configs/prowlarr/config.xml`
- Overseerr: `configs/overseerr/settings.json`
- Deluge: `configs/deluge/auth`

### Service Configuration Files

**Radarr** (`configs/radarr/config.xml`):
- Quality profiles
- Naming scheme (TRaSH Guides compliant)
- Download client settings
- Indexer connections (synced from Prowlarr)

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
- App sync configuration (Radarr connection)
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

## TRaSH Guides Compliance

This setup follows TRaSH Guides best practices:

1. **Naming Scheme**: Prevents download loops by using consistent format
   - Pattern: `{Movie CleanTitle} {(Release Year)} {{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo AudioCodec} {MediaInfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}`

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

### Downloads Not Importing
- Check paths match: Radarr sees `/data/Downloads` where Deluge downloads
- Verify root folder set to `/data/Movies` in Radarr
- Verify hardlinks working (same filesystem, both under `/data`)
- Check Radarr logs: `docker compose logs -f radarr`

### Prowlarr Indexers Not Syncing
- Verify Radarr API key in Prowlarr app settings
- Check network connectivity: `docker exec prowlarr nc -zv radarr 7878`
- Force sync in Prowlarr UI

### Plex Not Seeing New Media
- Verify volume mount: `/Volumes/Samsung_T5` mounted to `/data`
- Verify library path set to `/data/Movies` in Plex
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

## Access URLs

**Internal Access** (local network):
- Plex: http://dev.local:32400
- Radarr: http://dev.local:7878
- Prowlarr: http://dev.local:9696
- Overseerr: http://dev.local:5055
- Deluge: http://dev.local:8112

**External Access** (via Traefik, requires DNS + port forwarding):
- Plex: https://plex.${DOMAIN}
- Overseerr: https://requests.${DOMAIN}
- Traefik Dashboard: https://traefik.${DOMAIN} (basic auth required)

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
- Server location: Configurable via NORDVPN_COUNTRY

**Checking VPN Connection:**
```bash
# View gluetun logs to see VPN status
docker compose logs gluetun --tail=50

# Check Deluge's public IP (should be VPN IP)
docker exec gluetun wget -qO- ifconfig.me

# Restart VPN connection
docker compose restart gluetun
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

**Plex** (http://dev.local:32400):
- Library Settings
  - Update library path from `/data` to `/data/Movies`
  - OR remove and re-add library with new path

**Overseerr** (http://dev.local:5055):
- Settings → Radarr
  - Update root folder to `/data/Movies`
