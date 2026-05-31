#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Lyrics MenuBar for Linux..."
echo ""

# Check for required system packages
MISSING=()

if ! python3 -c "import gi" 2>/dev/null; then
    MISSING+=("python3-gi")
fi

if ! python3 -c "import dbus" 2>/dev/null; then
    MISSING+=("python3-dbus")
fi

if ! python3 -c "import gi; gi.require_version('AppIndicator3', '0.1'); from gi.repository import AppIndicator3" 2>/dev/null; then
    MISSING+=("gir1.2-appindicator3-0.1")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "==> Missing system packages: ${MISSING[*]}"
    echo "==> Installing with apt..."
    sudo apt install -y "${MISSING[@]}"
    echo ""
fi

# Install Python dependencies
echo "==> Installing Python dependencies..."
pip3 install --user -r requirements.txt
echo ""

# Create desktop entry for autostart (optional)
DESKTOP_DIR="$HOME/.config/autostart"
mkdir -p "$DESKTOP_DIR"

SCRIPT_DIR="$(realpath "$(dirname "$0")")"

cat > "$DESKTOP_DIR/lyrics-menubar.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Lyrics MenuBar
Comment=Shows time-synced lyrics in the top panel
Exec=python3 $SCRIPT_DIR/main.py
Icon=audio-x-generic
Terminal=false
Categories=Audio;Music;
X-GNOME-Autostart-enabled=true
EOF

echo "==> Installation complete!"
echo ""
echo "  To run now:        python3 $SCRIPT_DIR/main.py"
echo "  Autostart:         Enabled (will start on login)"
echo "  Disable autostart: rm ~/.config/autostart/lyrics-menubar.desktop"
echo ""
echo "  Make sure Spotify (or another MPRIS2 player) is running!"
