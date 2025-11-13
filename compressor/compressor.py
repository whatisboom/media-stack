#!/usr/bin/env python3
"""
Media Compressor Service
Automatically compresses seeded media files using HEVC (x265) to save storage space.
"""

import os
import sys
import json
import subprocess
import logging
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional
import requests

# Configuration from environment variables
CONFIG = {
    'downloads_dir': Path(os.getenv('DOWNLOADS_DIR', '/data/Downloads')),
    'movies_dir': Path(os.getenv('MOVIES_DIR', '/data/Movies')),
    'shows_dir': Path(os.getenv('SHOWS_DIR', '/data/Shows')),
    'crf': int(os.getenv('COMPRESSION_CRF', '23')),
    'preset': os.getenv('COMPRESSION_PRESET', 'slow'),
    'dry_run': os.getenv('DRY_RUN', 'false').lower() == 'true',
    'discord_webhook': os.getenv('DISCORD_WEBHOOK_URL', ''),
    'plex_url': os.getenv('PLEX_URL', 'http://plex:32400'),
    'plex_token': os.getenv('PLEX_CLAIM', ''),  # Optional
    'min_compression_ratio': float(os.getenv('MIN_COMPRESSION_RATIO', '0.8')),  # Only keep if <80% original size
}

# Video file extensions to process
VIDEO_EXTENSIONS = {'.mkv', '.mp4', '.avi', '.mov', '.m4v', '.wmv'}

# Setup logging (JSON format for structured logs)
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/logs/compressor.log', mode='a')
    ]
)
logger = logging.getLogger(__name__)


def send_discord_notification(message: str, is_error: bool = False):
    """Send notification to Discord webhook."""
    if not CONFIG['discord_webhook']:
        return

    try:
        payload = {
            'content': f"{'❌' if is_error else '✅'} **Media Compressor**\n{message}"
        }
        requests.post(CONFIG['discord_webhook'], json=payload, timeout=10)
    except Exception as e:
        logger.warning(f"Failed to send Discord notification: {e}")


def find_video_files(directory: Path) -> List[Path]:
    """Find all video files in a directory recursively."""
    video_files = []
    if not directory.exists():
        logger.warning(f"Directory does not exist: {directory}")
        return video_files

    for file_path in directory.rglob('*'):
        if file_path.is_file() and file_path.suffix.lower() in VIDEO_EXTENSIONS:
            video_files.append(file_path)

    return video_files


def find_matching_media_file(downloads_file: Path) -> Optional[Path]:
    """Find matching file in Movies or Shows directory by filename."""
    filename = downloads_file.name

    # Search in Movies
    for media_file in CONFIG['movies_dir'].rglob(filename):
        if media_file.is_file():
            return media_file

    # Search in Shows
    for media_file in CONFIG['shows_dir'].rglob(filename):
        if media_file.is_file():
            return media_file

    return None


def get_file_size_gb(file_path: Path) -> float:
    """Get file size in GB."""
    return file_path.stat().st_size / (1024 ** 3)


def get_video_codec(file_path: Path) -> Optional[str]:
    """Get video codec name using ffprobe."""
    try:
        result = subprocess.run(
            ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
             '-show_entries', 'stream=codec_name',
             '-of', 'default=noprint_wrappers=1:nokey=1', str(file_path)],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            return result.stdout.strip().lower()
        return None
    except Exception as e:
        logger.error(f"Failed to get codec for: {file_path} - {e}")
        return None


def verify_video_playable(file_path: Path) -> bool:
    """Verify video file is playable using ffprobe."""
    try:
        result = subprocess.run(
            ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
             '-of', 'default=noprint_wrappers=1:nokey=1', str(file_path)],
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.returncode == 0 and result.stdout.strip() != ''
    except Exception as e:
        logger.error(f"Failed to verify video: {file_path} - {e}")
        return False


def compress_video(input_path: Path, output_path: Path) -> bool:
    """
    Compress video using ffmpeg with HEVC (x265).
    Returns True if successful, False otherwise.
    """
    logger.info(f"Compressing: {input_path} -> {output_path}")

    cmd = [
        'ffmpeg',
        '-i', str(input_path),
        '-c:v', 'libx265',
        '-preset', CONFIG['preset'],
        '-crf', str(CONFIG['crf']),
        '-c:a', 'copy',  # Copy audio without re-encoding
        '-c:s', 'copy',  # Copy subtitles
        '-y',  # Overwrite output file
        str(output_path)
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=7200  # 2 hour timeout for large files
        )

        if result.returncode != 0:
            logger.error(f"FFmpeg failed: {result.stderr}")
            return False

        return True
    except subprocess.TimeoutExpired:
        logger.error(f"Compression timeout for: {input_path}")
        return False
    except Exception as e:
        logger.error(f"Compression error: {e}")
        return False


def process_file(downloads_file: Path) -> Dict:
    """
    Process a single file: find matching media file, compress, and replace.
    Returns statistics about the operation.
    """
    stats = {
        'file': str(downloads_file),
        'success': False,
        'original_size_gb': 0.0,
        'compressed_size_gb': 0.0,
        'space_saved_gb': 0.0,
        'error': None
    }

    # Find matching file in media directories
    media_file = find_matching_media_file(downloads_file)
    if not media_file:
        logger.info(f"No matching media file found for: {downloads_file.name}")
        stats['error'] = 'No matching media file'
        return stats

    original_size = get_file_size_gb(media_file)
    stats['original_size_gb'] = original_size

    logger.info(f"Found match: {downloads_file.name} -> {media_file}")
    logger.info(f"Original size: {original_size:.2f} GB")

    # Check if already HEVC-encoded (skip re-encoding for minimal gains)
    video_codec = get_video_codec(media_file)
    if video_codec in ('hevc', 'h265'):
        logger.info(f"Skipping already HEVC-encoded file (codec: {video_codec}): {media_file.name}")
        stats['error'] = f'Already HEVC ({video_codec})'
        return stats

    # Create temporary compressed file (preserve extension for ffmpeg)
    temp_output = media_file.parent / f".{media_file.stem}.tmp{media_file.suffix}"

    if CONFIG['dry_run']:
        logger.info(f"[DRY RUN] Would compress: {media_file}")
        stats['success'] = True
        stats['compressed_size_gb'] = original_size * 0.5  # Estimate 50% compression
        stats['space_saved_gb'] = original_size * 0.5
        return stats

    # Compress video
    if not compress_video(media_file, temp_output):
        stats['error'] = 'Compression failed'
        if temp_output.exists():
            temp_output.unlink()
        return stats

    # Verify compressed file
    if not verify_video_playable(temp_output):
        logger.error(f"Compressed file is not playable: {temp_output}")
        stats['error'] = 'Compressed file not playable'
        temp_output.unlink()
        return stats

    compressed_size = get_file_size_gb(temp_output)
    stats['compressed_size_gb'] = compressed_size
    stats['space_saved_gb'] = original_size - compressed_size

    # Check if compression achieved sufficient reduction
    compression_ratio = compressed_size / original_size
    if compression_ratio > CONFIG['min_compression_ratio']:
        logger.warning(
            f"Compression ratio {compression_ratio:.2f} exceeds threshold "
            f"{CONFIG['min_compression_ratio']}. Keeping original."
        )
        temp_output.unlink()
        stats['error'] = f'Insufficient compression ({compression_ratio:.2%})'
        return stats

    logger.info(f"Compressed size: {compressed_size:.2f} GB ({compression_ratio:.1%})")
    logger.info(f"Space saved: {stats['space_saved_gb']:.2f} GB")

    # Atomically replace original with compressed version
    try:
        media_file.unlink()  # Delete original
        temp_output.rename(media_file)  # Rename temp to original name

        # Delete file from Downloads (now that media file is safely replaced)
        if downloads_file.exists():
            downloads_file.unlink()
            logger.info(f"Deleted from Downloads: {downloads_file}")

        stats['success'] = True
        logger.info(f"Successfully replaced: {media_file}")

    except Exception as e:
        logger.error(f"Failed to replace file: {e}")
        stats['error'] = f'Failed to replace: {e}'
        if temp_output.exists():
            temp_output.unlink()
        return stats

    return stats


def trigger_plex_scan():
    """Trigger Plex library scan (best effort)."""
    if not CONFIG['plex_token']:
        logger.info("No Plex token configured, skipping library scan")
        return

    try:
        url = f"{CONFIG['plex_url']}/library/sections/all/refresh"
        headers = {'X-Plex-Token': CONFIG['plex_token']}
        response = requests.get(url, headers=headers, timeout=10)

        if response.status_code == 200:
            logger.info("Triggered Plex library scan")
        else:
            logger.warning(f"Failed to trigger Plex scan: {response.status_code}")
    except Exception as e:
        logger.warning(f"Failed to trigger Plex scan: {e}")


def main():
    """Main compression workflow."""
    start_time = datetime.now()
    logger.info("=" * 60)
    logger.info(f"Media Compressor started at {start_time}")
    logger.info(f"Configuration: CRF={CONFIG['crf']}, Preset={CONFIG['preset']}, DryRun={CONFIG['dry_run']}")
    logger.info("=" * 60)

    # Find all video files in Downloads
    downloads_videos = find_video_files(CONFIG['downloads_dir'])
    logger.info(f"Found {len(downloads_videos)} video files in Downloads")

    if not downloads_videos:
        logger.info("No videos to process")
        send_discord_notification("No videos found in Downloads directory")
        return

    # Process each file
    results = []
    total_space_saved = 0.0
    successful_compressions = 0

    for video_file in downloads_videos:
        logger.info(f"\nProcessing: {video_file.name}")
        stats = process_file(video_file)
        results.append(stats)

        if stats['success']:
            successful_compressions += 1
            total_space_saved += stats['space_saved_gb']

    # Summary
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds() / 60

    logger.info("=" * 60)
    logger.info("Compression Summary")
    logger.info("=" * 60)
    logger.info(f"Total files processed: {len(results)}")
    logger.info(f"Successful compressions: {successful_compressions}")
    logger.info(f"Total space saved: {total_space_saved:.2f} GB")
    logger.info(f"Duration: {duration:.1f} minutes")

    # Discord notification
    if successful_compressions > 0:
        message = (
            f"Compressed {successful_compressions}/{len(results)} video files\n"
            f"Space saved: **{total_space_saved:.2f} GB**\n"
            f"Duration: {duration:.1f} min"
        )
        send_discord_notification(message)

        # Trigger Plex scan
        trigger_plex_scan()

    # Log detailed results
    logger.info("\nDetailed Results:")
    for result in results:
        logger.info(json.dumps(result))

    logger.info("=" * 60)
    logger.info("Media Compressor finished")
    logger.info("=" * 60)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        send_discord_notification(f"Fatal error: {e}", is_error=True)
        sys.exit(1)
