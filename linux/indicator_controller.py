"""
IndicatorController - Shows lyrics in the Ubuntu/GNOME top panel using AppIndicator3.

This is the Linux equivalent of MenuBarController.swift.
Uses libappindicator3 to display text in the system tray / top panel area.
"""

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AppIndicator3", "0.1")

from gi.repository import AppIndicator3, GLib, Gtk

from player_reader import current_state, PlayerState
from lyrics_fetcher import fetch, LyricLine


PLACEHOLDER = "♪ Lyrics"
MAX_CHARS = 70
POLL_INTERVAL_MS = 500  # 0.5 seconds


class IndicatorController:
    def __init__(self):
        # Create the AppIndicator
        self.indicator = AppIndicator3.Indicator.new(
            "lyrics-menubar",
            "audio-x-generic",
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self.indicator.set_label(PLACEHOLDER, "")

        # Build the menu
        self.menu = Gtk.Menu()

        self.now_playing_item = Gtk.MenuItem(label="Now Playing: -")
        self.now_playing_item.set_sensitive(False)
        self.menu.append(self.now_playing_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        refresh_item = Gtk.MenuItem(label="Refresh Lyrics")
        refresh_item.connect("activate", self._on_refresh)
        self.menu.append(refresh_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", self._on_quit)
        self.menu.append(quit_item)

        self.menu.show_all()
        self.indicator.set_menu(self.menu)

        # State
        self.current_track_id: str | None = None
        self.lyrics: list[LyricLine] = []
        self.last_displayed: str = ""
        self._fetching: bool = False

        # Start polling
        GLib.timeout_add(POLL_INTERVAL_MS, self._poll)

    def _on_refresh(self, _widget):
        """Force refetch lyrics."""
        self.current_track_id = None
        self.lyrics = []
        self.last_displayed = ""

    def _on_quit(self, _widget):
        """Quit the application."""
        Gtk.main_quit()

    def _poll(self) -> bool:
        """Poll the player state and update the indicator. Returns True to keep the timer alive."""
        state = current_state()
        self._handle_state(state)
        return True  # Keep the timer running

    def _handle_state(self, state: PlayerState | None):
        if state is None:
            if self.current_track_id is not None:
                self.current_track_id = None
                self.lyrics = []
                self.last_displayed = ""
                self.indicator.set_label(PLACEHOLDER, "")
                self.now_playing_item.set_label("Now Playing: -")
            return

        # Track changed
        if state.id != self.current_track_id:
            self.current_track_id = state.id
            self.lyrics = []
            self.last_displayed = ""
            self.now_playing_item.set_label(f"♪ [{state.source}] {state.track} — {state.artist}")
            self.indicator.set_label("Loading lyrics...", "")
            self._start_fetch(state.track, state.artist, state.duration, state.id)
            return

        # Update current lyric line
        if not state.playing or not self.lyrics:
            return

        current_line = ""
        for line in self.lyrics:
            if line.time <= state.position:
                current_line = line.text
            else:
                break

        if not current_line:
            if self.last_displayed:
                self.indicator.set_label(PLACEHOLDER, "")
                self.last_displayed = ""
            return

        if current_line == self.last_displayed:
            return

        display = current_line
        if len(display) > MAX_CHARS:
            display = display[: MAX_CHARS - 1] + "…"

        self.indicator.set_label(display, "")
        self.last_displayed = current_line

    def _start_fetch(self, track: str, artist: str, duration: float, track_id: str):
        """Fetch lyrics in a background thread to avoid blocking the UI."""
        import threading

        def _do_fetch():
            lines, _is_synced = fetch(track=track, artist=artist, duration=duration)
            # Schedule UI update on the main thread
            GLib.idle_add(self._on_fetch_complete, lines, track_id)

        thread = threading.Thread(target=_do_fetch, daemon=True)
        thread.start()

    def _on_fetch_complete(self, lines: list[LyricLine], track_id: str) -> bool:
        """Called on the main thread when lyrics fetch completes."""
        if self.current_track_id != track_id:
            return False  # Track changed while fetching

        self.lyrics = lines
        if not lines:
            self.indicator.set_label("♪ (no lyrics found)", "")
        return False  # Don't repeat this idle callback
