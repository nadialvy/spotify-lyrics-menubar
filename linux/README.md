# Lyrics MenuBar — Linux

Shows time-synced lyrics for the currently playing song in the **Ubuntu/GNOME top panel** using AppIndicator3.

![Linux](https://img.shields.io/badge/Linux-Ubuntu%2022.04%2B-orange) ![Python](https://img.shields.io/badge/Python-3.10%2B-blue)

This is the Linux port of the [macOS Lyrics MenuBar](../README.md) app.

---

## How It Works

- Reads the current track, artist, and playback position via **D-Bus MPRIS2** from any compatible player (Spotify, Rhythmbox, VLC, etc.)
- If multiple players are running, prefers the one that is actively playing
- Fetches synced lyrics from [lrclib.net](https://lrclib.net) (falls back to plain lyrics with estimated timing)
- Updates the top panel label in real time as the song progresses

## Supported Players

Any player that implements the [MPRIS2 D-Bus interface](https://specifications.freedesktop.org/mpris-spec/latest/):

- **Spotify** (primary target)
- Rhythmbox
- VLC
- Audacious
- Clementine / Strawberry
- Any other MPRIS2-compatible player

---

## Install & Run

### Quick Start

```bash
cd linux/
chmod +x install.sh
./install.sh
```

This will:
1. Install required system packages (`python3-gi`, `python3-dbus`, `gir1.2-appindicator3-0.1`)
2. Install Python dependencies (`requests`)
3. Set up autostart so it launches on login

### Manual Install

```bash
# System dependencies
sudo apt install python3-gi python3-dbus gir1.2-appindicator3-0.1

# Python dependencies
pip3 install requests

# Run
python3 main.py
```

### Run

```bash
python3 linux/main.py
```

The lyrics will appear in your top panel. Click the indicator for options:

| Item | Action |
| --- | --- |
| **Now Playing** | Shows the current track and source |
| **Refresh Lyrics** | Force a refetch |
| **Quit** | Quit the app |

---

## Configuration

Edit the constants at the top of `indicator_controller.py`:

| Constant | Default | Purpose |
| --- | --- | --- |
| `PLACEHOLDER` | `♪ Lyrics` | Text shown when nothing is playing |
| `MAX_CHARS` | `70` | Max characters before truncation |
| `POLL_INTERVAL_MS` | `500` | How often (ms) to poll the player |

---

## Troubleshooting

**Nothing appears in the top panel.**

Make sure AppIndicator support is enabled. On GNOME, you may need the [AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/):

```bash
sudo apt install gnome-shell-extension-appindicator
```

Then enable it in GNOME Extensions or restart your session.

**"No lyrics found"**

The track isn't in lrclib.net's database. Test manually:

```bash
curl "https://lrclib.net/api/get?track_name=SONG&artist_name=ARTIST&duration=240"
```

**Spotify not detected.**

Make sure Spotify is running. Verify MPRIS2 is working:

```bash
dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify \
  /org/mpris/MediaPlayer2 \
  org.freedesktop.DBus.Properties.Get \
  string:"org.mpris.MediaPlayer2.Player" string:"Metadata"
```

**Lyrics out of sync.**

For synced LRC lyrics, timing comes from lrclib. For plain lyrics (fallback), lines are distributed evenly across the track duration.

---

## Requirements

- Ubuntu 22.04+ / GNOME 42+ (or any desktop with AppIndicator support)
- Python 3.10+
- Spotify (or any MPRIS2 player)
- Internet connection (for fetching lyrics)
