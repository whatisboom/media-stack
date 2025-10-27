# Media Server Stack

Self-hosted media automation stack built with Docker, configured following [TRaSH Guides](https://trash-guides.info/) best practices.

## Services

| Service | Port | Purpose | Access URL |
|---------|------|---------|------------|
| **Plex** | 32400 | Media streaming server | http://dev.local:32400 |
| **Radarr** | 7878 | Movie library management & automation | http://dev.local:7878 |
| **Prowlarr** | 9696 | Indexer management (centralized) | http://dev.local:9696 |
| **Overseerr** | 5055 | Media request management | http://dev.local:5055 |
| **Deluge** | 8112 | BitTorrent client | http://dev.local:8112 |

## Quick Start

### Initial Setup

1. **Copy environment template**:
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` and configure**:
   - Set `PLEX_CLAIM_TOKEN` - Get from https://www.plex.tv/claim/ (expires in 4 minutes)
   - Set `DELUGE_WEB_PASSWORD` - Your preferred password
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
│   ├── deluge/       # Deluge settings, auth, torrents
│   ├── overseerr/    # Overseerr database and settings
│   ├── plex/         # Plex Media Server data
│   ├── prowlarr/     # Prowlarr indexer configs
│   └── radarr/       # Radarr database and settings
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

**Prowlarr** (http://dev.local:9696)
- Location: Settings → General → Security → API Key
- Also stored in: `configs/prowlarr/config.xml`

**Overseerr** (http://dev.local:5055)
- Location: Settings → General → API Key
- Also stored in: `configs/overseerr/settings.json`

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

## Workflow

1. **Request** → User requests movie via Overseerr
2. **Search** → Radarr searches configured indexers (via Prowlarr)
3. **Download** → Radarr sends torrent to Deluge with category `radarr-movies`
4. **Monitor** → Radarr monitors download progress in `/data/Downloads`
5. **Import** → When complete, Radarr hardlinks/moves to `/data/Movies` with proper naming
6. **Seed** → Deluge continues seeding until ratio/time goals met
7. **Stream** → Plex makes movie available for streaming

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
If using private trackers, disable DHT, LSD, and UPnP in Deluge:
```
configs/deluge/core.conf:
- "dht": false
- "lsd": false
- "upnp": false
```

## Security

### Current Setup
✅ **Implemented**:
- Secrets stored in `.env` file (not in version control)
- `.gitignore` prevents committing sensitive data
- Configs directory excluded from git (contains auto-generated API keys)

⚠️ **Still Needed for Production**:
- No HTTPS configured
- Some services lack authentication
- No VPN for torrent traffic

### Recommendations for Production
1. **Reverse Proxy**: Use Nginx/Traefik with HTTPS and Let's Encrypt
2. **Authentication**: Enable on all services (especially Prowlarr/Radarr)
3. **VPN**: Route Deluge through VPN container for privacy
4. **Network Isolation**: Use Docker networks to limit service access
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
- [ ] Set up Sonarr for TV shows (optional)
- [ ] Configure notifications (Discord, Email, etc.)
- [ ] Add VPN container for secure torrenting
- [ ] Set up reverse proxy with HTTPS

## Resources

- [TRaSH Guides](https://trash-guides.info/) - Configuration best practices
- [Radarr Wiki](https://wiki.servarr.com/radarr)
- [Prowlarr Wiki](https://wiki.servarr.com/prowlarr)
- [Deluge Documentation](https://dev.deluge-torrent.org/)
