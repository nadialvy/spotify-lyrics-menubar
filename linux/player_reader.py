"""
PlayerReader - Reads current playback state from Spotify (or any MPRIS2 player) via D-Bus.
"""

import dbus


class PlayerState:
    __slots__ = ("track", "artist", "position", "duration", "id", "playing", "source")

    def __init__(self, track: str, artist: str, position: float, duration: float,
                 id: str, playing: bool, source: str):
        self.track = track
        self.artist = artist
        self.position = position
        self.duration = duration
        self.id = id
        self.playing = playing
        self.source = source


# MPRIS2 players to check, in priority order
PLAYERS = [
    "spotify",
    "rhythmbox",
    "vlc",
    "audacious",
    "clementine",
    "strawberry",
]

MPRIS_PREFIX = "org.mpris.MediaPlayer2."
MPRIS_PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"


def _get_session_bus():
    return dbus.SessionBus()


def _get_running_players() -> list[str]:
    """Find all running MPRIS2 players on the session bus."""
    bus = _get_session_bus()
    bus_obj = bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus")
    names = bus_obj.ListNames(dbus_interface="org.freedesktop.DBus")
    players = []
    for name in names:
        if str(name).startswith(MPRIS_PREFIX):
            players.append(str(name))
    return players


def _get_player_state(bus_name: str) -> PlayerState | None:
    """Query a single MPRIS2 player for its current state."""
    try:
        bus = _get_session_bus()
        player_obj = bus.get_object(bus_name, "/org/mpris/MediaPlayer2")
        props = dbus.Interface(player_obj, DBUS_PROPERTIES_IFACE)

        playback_status = str(props.Get(MPRIS_PLAYER_IFACE, "PlaybackStatus"))
        metadata = props.Get(MPRIS_PLAYER_IFACE, "Metadata")
        position_us = int(props.Get(MPRIS_PLAYER_IFACE, "Position"))  # microseconds

        track = str(metadata.get("xesam:title", ""))
        artists = metadata.get("xesam:artist", [])
        artist = str(artists[0]) if artists else ""
        duration_us = int(metadata.get("mpris:length", 0))  # microseconds
        track_id = str(metadata.get("mpris:trackid", ""))

        if not track:
            return None

        source_name = bus_name.replace(MPRIS_PREFIX, "").split(".")[0].capitalize()

        return PlayerState(
            track=track,
            artist=artist,
            position=position_us / 1_000_000,  # convert to seconds
            duration=duration_us / 1_000_000,   # convert to seconds
            id=f"{source_name}:{track_id}",
            playing=(playback_status == "Playing"),
            source=source_name,
        )
    except (dbus.DBusException, KeyError, IndexError, ValueError):
        return None


def current_state() -> PlayerState | None:
    """
    Get the current player state. Prefers the player that is actively playing.
    Falls back to the first paused player found.
    """
    running = _get_running_players()
    if not running:
        return None

    # Sort: prioritize known players
    def priority(name: str) -> int:
        lower = name.lower()
        for i, p in enumerate(PLAYERS):
            if p in lower:
                return i
        return len(PLAYERS)

    running.sort(key=priority)

    states = []
    for bus_name in running:
        state = _get_player_state(bus_name)
        if state:
            states.append(state)

    # Prefer playing over paused
    for s in states:
        if s.playing:
            return s
    return states[0] if states else None
