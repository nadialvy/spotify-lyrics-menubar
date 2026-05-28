import Cocoa

final class MenuBarController {
    private let placeholder = "♪ Lyrics"
    private let maxChars = 28
    private let pollInterval: TimeInterval = 0.25
    private let lyricLeadTime: Double = 0.28

    private enum DisplayMode: String {
        case overlay
        case menuBar
    }

    private enum DefaultsKey {
        static let displayMode = "display.mode"
        static let overlayClickThrough = "overlay.clickThrough"
        static let overlayOpacity = "overlay.opacity"
    }

    private let statusItem: NSStatusItem
    private let settingsMenu = NSMenu()
    private let nowPlayingItem: NSMenuItem
    private let displayModeItem: NSMenuItem
    private let overlayClickThroughItem: NSMenuItem
    private var overlayOpacityItems: [NSMenuItem] = []
    private let overlayController = LyricOverlayController()

    private var displayMode: DisplayMode = .overlay
    private var currentTrackID: String?
    private var lyrics: [LyricLine] = []
    private var statusText = "♪ Lyrics"

    private var pollTimer: Timer?
    private var isPolling = false
    private let pollQueue = DispatchQueue(label: "lyrics.poll", qos: .userInitiated)
    private let fetchQueue = DispatchQueue(label: "lyrics.fetch", qos: .utility)

    init() {
        UserDefaults.standard.register(defaults: [
            DefaultsKey.displayMode: DisplayMode.overlay.rawValue,
            DefaultsKey.overlayClickThrough: false,
            DefaultsKey.overlayOpacity: 0.86
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        displayModeItem = NSMenuItem(title: "Use Floating Box", action: #selector(toggleDisplayMode), keyEquivalent: "")
        overlayClickThroughItem = NSMenuItem(title: "Click-Through Overlay", action: #selector(toggleClickThrough), keyEquivalent: "")

        nowPlayingItem = NSMenuItem(title: "Now Playing: -", action: nil, keyEquivalent: "")
        nowPlayingItem.isEnabled = false
        settingsMenu.addItem(nowPlayingItem)
        settingsMenu.addItem(.separator())

        displayModeItem.target = self
        settingsMenu.addItem(displayModeItem)

        overlayClickThroughItem.target = self
        settingsMenu.addItem(overlayClickThroughItem)

        let opacityMenu = NSMenu()
        for percent in [70, 86, 100] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(setOverlayOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
            opacityMenu.addItem(item)
            overlayOpacityItems.append(item)
        }

        let opacityItem = NSMenuItem(title: "Overlay Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        settingsMenu.addItem(opacityItem)

        let resetPosition = NSMenuItem(title: "Reset Overlay Position", action: #selector(resetOverlayPosition), keyEquivalent: "")
        resetPosition.target = self
        settingsMenu.addItem(resetPosition)
        settingsMenu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Lyrics", action: #selector(forceRefresh), keyEquivalent: "")
        refresh.target = self
        settingsMenu.addItem(refresh)

        settingsMenu.addItem(.separator())
        settingsMenu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = settingsMenu
        statusItem.button?.toolTip = "Lyrics settings"

        loadOverlaySettings()
        applyDisplayMode()

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        DispatchQueue.main.async { [weak self] in self?.poll() }
    }

    @objc private func forceRefresh() {
        currentTrackID = nil
        lyrics = []
        setStatusText(placeholder)
    }

    @objc private func toggleDisplayMode() {
        displayMode = displayMode == .overlay ? .menuBar : .overlay
        UserDefaults.standard.set(displayMode.rawValue, forKey: DefaultsKey.displayMode)
        applyDisplayMode()
    }

    @objc private func toggleClickThrough() {
        overlayController.isClickThrough.toggle()
        UserDefaults.standard.set(overlayController.isClickThrough, forKey: DefaultsKey.overlayClickThrough)
        updateOverlayMenuState()
    }

    @objc private func setOverlayOpacity(_ sender: NSMenuItem) {
        let opacity = CGFloat(sender.tag) / 100
        overlayController.opacity = opacity
        UserDefaults.standard.set(Double(opacity), forKey: DefaultsKey.overlayOpacity)
        updateOverlayMenuState()
    }

    @objc private func resetOverlayPosition() {
        overlayController.resetPosition()
    }

    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        pollQueue.async { [weak self] in
            let state = PlayerReader.currentState()
            DispatchQueue.main.async {
                self?.isPolling = false
                self?.handle(state: state)
            }
        }
    }

    private func handle(state: PlayerState?) {
        guard let state = state else {
            overlayController.hide()
            if currentTrackID != nil {
                currentTrackID = nil
                lyrics = []
                setStatusText(placeholder)
                nowPlayingItem.title = "Now Playing: -"
            }
            return
        }

        if state.id != currentTrackID {
            currentTrackID = state.id
            lyrics = []
            statusText = placeholder
            nowPlayingItem.title = "♪ \(state.track) — \(state.artist)"
            setStatusText("Loading lyrics...")
            if displayMode == .overlay {
                overlayController.showLoading(track: state.track, artist: state.artist, source: state.source)
            }
            startFetch(track: state.track, artist: state.artist, duration: state.duration, trackID: state.id, source: state.source)
            return
        }

        guard !lyrics.isEmpty else { return }

        let adjustedPosition = state.position + lyricLeadTime
        let snapshot = lyricSnapshot(position: adjustedPosition, duration: state.duration)

        if displayMode == .overlay {
            overlayController.update(
                track: state.track,
                artist: state.artist,
                source: state.source,
                current: snapshot.current,
                next: snapshot.next,
                progress: snapshot.progress,
                isPaused: !state.playing
            )
        } else {
            overlayController.hide()
        }

        guard state.playing else { return }

        let statusLine = snapshot.current == "Instrumental" ? placeholder : snapshot.current
        setStatusText(statusLine)
    }

    private func startFetch(track: String, artist: String, duration: Double, trackID: String, source: String) {
        fetchQueue.async { [weak self] in
            let (lines, _) = LyricsFetcher.fetch(track: track, artist: artist, duration: duration)
            DispatchQueue.main.async {
                guard let self = self, self.currentTrackID == trackID else { return }
                self.lyrics = lines
                if lines.isEmpty {
                    self.setStatusText("♪ (no lyrics found)")
                    if self.displayMode == .overlay {
                        self.overlayController.showNoLyrics(track: track, artist: artist, source: source)
                    }
                }
            }
        }
    }

    private func lyricSnapshot(position: Double, duration: Double) -> (current: String, next: String, progress: Double) {
        guard !lyrics.isEmpty else {
            return ("", "", 0)
        }

        guard let currentIndex = lyrics.lastIndex(where: { $0.time <= position }) else {
            let first = lyrics[0]
            let progress = first.time > 0 ? position / first.time : 0
            return ("Instrumental", first.text, clamped(progress))
        }

        let current = lyrics[currentIndex].text
        let nextLine = lyrics.dropFirst(currentIndex + 1).first
        let next = nextLine?.text ?? ""
        let start = lyrics[currentIndex].time
        let end = nextLine?.time ?? duration
        let progress = end > start ? (position - start) / (end - start) : 1

        return (current, next, clamped(progress))
    }

    private func clipped(_ text: String) -> String {
        guard text.count > maxChars else { return text }
        return String(text.prefix(maxChars - 1)) + "…"
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func loadOverlaySettings() {
        let defaults = UserDefaults.standard

        if let rawDisplayMode = defaults.string(forKey: DefaultsKey.displayMode),
           let storedDisplayMode = DisplayMode(rawValue: rawDisplayMode) {
            displayMode = storedDisplayMode
        }

        overlayController.isClickThrough = defaults.bool(forKey: DefaultsKey.overlayClickThrough)
        overlayController.opacity = CGFloat(defaults.double(forKey: DefaultsKey.overlayOpacity))
    }

    private func applyDisplayMode() {
        switch displayMode {
        case .overlay:
            statusItem.length = NSStatusItem.squareLength
            statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lyrics")
            statusItem.button?.imagePosition = .imageOnly
            statusItem.button?.title = ""
            overlayController.isEnabled = true
        case .menuBar:
            overlayController.hide()
            statusItem.length = NSStatusItem.variableLength
            statusItem.button?.image = nil
            statusItem.button?.imagePosition = .noImage
            statusItem.button?.title = clipped(statusText)
        }

        statusItem.button?.toolTip = statusText
        updateOverlayMenuState()
    }

    private func setStatusText(_ text: String) {
        statusText = text
        statusItem.button?.toolTip = text
        if displayMode == .menuBar {
            statusItem.button?.title = clipped(text)
        }
    }

    private func updateOverlayMenuState() {
        displayModeItem.state = displayMode == .overlay ? .on : .off
        overlayClickThroughItem.state = overlayController.isClickThrough ? .on : .off

        let currentPercent = Int(round(overlayController.opacity * 100))
        for item in overlayOpacityItems {
            item.state = item.tag == currentPercent ? .on : .off
        }
    }
}
