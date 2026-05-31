"""
LyricsFetcher - Fetches lyrics from lrclib.net and parses LRC format.
"""

import re
from dataclasses import dataclass

import requests

LRC_PATTERN = re.compile(r"\[(\d+):(\d+\.?\d*)\](.*)")
PAREN_PATTERN = re.compile(r"\s*[\(\[].*?[\)\]]\s*")

USER_AGENT = "LyricsMenuBar-Linux v1.0 (personal use)"
TIMEOUT = 6


@dataclass
class LyricLine:
    time: float
    text: str


def fetch(track: str, artist: str, duration: float) -> tuple[list[LyricLine], bool]:
    """
    Fetch lyrics for a track. Returns (lines, is_synced).
    Tries direct match first, then search fallback.
    """
    clean_track = PAREN_PATTERN.sub("", track).strip()
    clean_artist = artist.split(",")[0].strip()

    # Try direct match
    params = {
        "track_name": clean_track,
        "artist_name": clean_artist,
        "duration": int(duration),
    }
    payload = _fetch_json(f"https://lrclib.net/api/get", params=params)

    # Fallback to search
    if payload is None:
        search_params = {
            "track_name": clean_track,
            "artist_name": clean_artist,
        }
        results = _fetch_json("https://lrclib.net/api/search", params=search_params)
        if results and isinstance(results, list):
            payload = _select_entry_with_lyrics(results)

    if not payload:
        return ([], False)

    # Parse synced lyrics
    synced = payload.get("syncedLyrics", "")
    if synced:
        lines = _parse_lrc(synced)
        if lines:
            return (lines, True)

    # Fallback to plain lyrics with estimated timing
    plain = payload.get("plainLyrics", "")
    if plain and duration > 0:
        text_lines = [line.strip() for line in plain.split("\n") if line.strip()]
        if text_lines:
            step = duration / len(text_lines)
            lines = [LyricLine(time=i * step, text=text) for i, text in enumerate(text_lines)]
            return (lines, False)

    return ([], False)


def _select_entry_with_lyrics(results: list[dict]) -> dict | None:
    """Select the first search result that has lyrics."""
    for entry in results:
        synced = entry.get("syncedLyrics", "")
        plain = entry.get("plainLyrics", "")
        if synced or plain:
            return entry
    return None


def _fetch_json(url: str, params: dict = None):
    """Fetch JSON from a URL, returns parsed JSON or None."""
    try:
        resp = requests.get(
            url,
            params=params,
            headers={"User-Agent": USER_AGENT},
            timeout=TIMEOUT,
        )
        if resp.status_code == 200:
            return resp.json()
    except (requests.RequestException, ValueError):
        pass
    return None


def _parse_lrc(text: str) -> list[LyricLine]:
    """Parse LRC formatted lyrics into a sorted list of LyricLine."""
    result = []
    for line in text.split("\n"):
        match = LRC_PATTERN.match(line.strip())
        if not match:
            continue
        minutes = float(match.group(1))
        seconds = float(match.group(2))
        body = match.group(3).strip()
        if not body:
            continue
        result.append(LyricLine(time=minutes * 60 + seconds, text=body))
    result.sort(key=lambda l: l.time)
    return result
