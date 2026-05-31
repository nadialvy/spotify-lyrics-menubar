#!/usr/bin/env python3
"""
Lyrics MenuBar for Linux (Ubuntu/GNOME)

Shows time-synced lyrics for the currently playing song in the top panel
using AppIndicator3. Reads playback state from any MPRIS2-compatible player
(Spotify, Rhythmbox, VLC, etc.) via D-Bus.

Usage:
    python3 main.py

Dependencies:
    sudo apt install python3-gi python3-dbus gir1.2-appindicator3-0.1
    pip install requests
"""

import signal
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from indicator_controller import IndicatorController


def main():
    # Allow Ctrl+C to quit gracefully
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    print("♪ Lyrics MenuBar (Linux) starting...")
    print("  Listening for MPRIS2 players (Spotify, etc.) via D-Bus")
    print("  Press Ctrl+C to quit")

    _controller = IndicatorController()
    Gtk.main()


if __name__ == "__main__":
    main()
