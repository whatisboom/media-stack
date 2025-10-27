# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted media automation stack using Docker Compose. Services work together to automate movie downloading, management, and streaming following [TRaSH Guides](https://trash-guides.info/) best practices.

## Architecture

### Service Dependencies & Data Flow

```
Overseerr (Requests)
    ↓
Radarr (Movie Management) → Prowlarr (Indexer Management)
    ↓
Deluge (Download Client)
    ↓
Plex (Media Streaming)
```

**Request Flow:**
1. Overseerr receives movie request
2. Radarr searches indexers (managed by Prowlarr)
3. Radarr sends torrent to Deluge with category `radarr-movies`
4. Deluge downloads to `/downloads`
5. Radarr imports completed download to `/movies` with proper naming
6. Plex scans and makes available for streaming

### Volume Architecture

**Critical: Hardlinks Requirement**
- `/downloads` and `/movies` MUST be on same filesystem for hardlinks
- Current setup: Both on `/Volumes/Samsung_T5/`
- Hardlinks enable instant moves and prevent duplicate storage

**Volume Mappings:**
- Downloads: `/Volumes/Samsung_T5/Downloads` → `/downloads`
- Movies: `/Volumes/Samsung_T5/Movies` → `/movies` (Radarr) / `/data` (Plex)
- Configs: `./configs/[service]` → service-specific paths

### Network Architecture

All services on Docker default bridge network. Inter-service communication uses container names:
- Radarr → Deluge: `deluge:8112`
- Prowlarr → Radarr: `radarr:7878`
- Overseerr → Plex: `plex:32400`
- Overseerr → Radarr: `radarr:7878`

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
docker exec radarr nc -zv deluge 8112
docker exec prowlarr nc -zv radarr 7878

# Access service shells
docker exec -it radarr /bin/bash
docker exec -it deluge /bin/bash
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
- Download paths
- Seed ratios and time limits
- Port configuration
- Plugin settings (Labels plugin required for categorization)

**Prowlarr** (`configs/prowlarr/config.xml`):
- Indexer definitions
- App sync configuration (Radarr connection)
- Category mappings

## TRaSH Guides Compliance

This setup follows TRaSH Guides best practices:

1. **Naming Scheme**: Prevents download loops by using consistent format
   - Pattern: `{Movie CleanTitle} {(Release Year)} {{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo AudioCodec} {MediaInfo AudioChannels]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo VideoCodec]}{-Release Group}`

2. **Directory Structure**: Separate download/media directories for hardlinks

3. **Download Client**: Labels plugin enabled for category management

4. **Indexer Management**: Centralized in Prowlarr with auto-sync to apps

5. **Seed Goals**: Configured per indexer (not in download client)

## Common Issues

### Radarr Can't Set Categories in Deluge
- Verify Labels plugin enabled in `configs/deluge/core.conf`
- Restart Deluge: `docker compose restart deluge`
- Test in Radarr: Settings → Download Clients → Test

### Downloads Not Importing
- Check paths match: Radarr sees same `/downloads` as Deluge
- Verify hardlinks working (same filesystem)
- Check Radarr logs: `docker compose logs -f radarr`

### Prowlarr Indexers Not Syncing
- Verify Radarr API key in Prowlarr app settings
- Check network connectivity: `docker exec prowlarr nc -zv radarr 7878`
- Force sync in Prowlarr UI

### Plex Not Seeing New Media
- Verify volume mount: `/Volumes/Samsung_T5/Movies` mounted to `/data`
- Check Overseerr scheduled job (Plex scan every 5 min)
- Manual scan: Plex UI → Library → Scan Library Files

## Access URLs

All services accessible at `dev.local`:
- Plex: http://dev.local:32400
- Radarr: http://dev.local:7878
- Prowlarr: http://dev.local:9696
- Overseerr: http://dev.local:5055
- Deluge: http://dev.local:8112

## Important Notes

- Plex claim token expires in 4 minutes after generation
- Deluge default username: `admin` (password set in `.env`)
- First-time setup requires accessing each service to complete initial configuration
- API keys auto-generate on first run and persist in `configs/` directory
