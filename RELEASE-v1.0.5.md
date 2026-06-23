# Lyrics Menu Bar — v1.0.5 Release Notes

We are excited to announce **v1.0.5** of Lyrics Menu Bar! This release introduces native support for **TIDAL**, along with major performance optimizations and lyric fetching reliability improvements.

---

## 🎵 What's New

### 🌊 Native TIDAL Desktop App Support
Lyrics Menu Bar now supports the official **TIDAL** macOS desktop application!
- **MediaRemote API Integration**: Unlike Spotify and Apple Music which use AppleScript, TIDAL support is powered by the native private macOS `MediaRemote` framework. It fetches track title, artist, playback speed (playing/paused), total duration, and exact elapsed time directly from the system's now-playing manager.
- **Auto-Prioritization**: The app automatically detects which player is active. If you are playing music on TIDAL, it will dynamically fetch and display lyrics for your current TIDAL track, switching back to Spotify or Apple Music when they resume.

---

## 🛠️ Performance & Reliability Improvements

### ⚡ Reduced CPU Overhead & Smarter Polling
- **Halved AppleScript Spawns**: AppleScript execution can be heavy. We reduced AppleScript execution frequency by 50% without sacrificing track-change responsiveness.
- **Unified Loop**: Consolidated the polling logic into a single, clean loop that manages active states efficiently.
- **Decoupled Fetching**: The lyric fetching queue is now fully isolated from the main player polling thread, preventing menu bar UI stutters when searching for lyrics.

### 🌐 Resilient Lyric Fetching
- **Transient Error Retries**: Implemented automatic retries for temporary network/API failures.
- **Extended Timeout**: Raised the `lrclib` API request timeout to 15 seconds to ensure lyrics are fetched successfully even under slow/unstable network connections.
- **Smarter Matching**: Refined search result filtering to prioritize the first valid search result containing actual lyrics.

---

## 📦 How to Install / Upgrade

1. Download the latest build or build it from source:
   ```bash
   ./build.sh
   ```
2. Open the generated `LyricsMenuBar.dmg` and drag the app to your `/Applications` directory.
3. Launch `Lyrics Menu Bar`. Make sure to grant the necessary permissions if prompted by macOS.
