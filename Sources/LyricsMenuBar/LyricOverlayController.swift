import Cocoa
import QuartzCore

private final class LyricOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class LyricOverlayController: NSObject {
    private enum Layout {
        static let panelSize = NSSize(width: 248, height: 144)
    }

    private enum DefaultsKey {
        static let originX = "overlay.origin.x"
        static let originY = "overlay.origin.y"
    }

    private let panel: LyricOverlayPanel
    private let overlayView: LyricOverlayView
    private var hasDisplayableContent = false
    private var isPositioning = false

    var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                if hasDisplayableContent {
                    show()
                }
            } else {
                panel.orderOut(nil)
            }
        }
    }

    var isClickThrough: Bool = false {
        didSet {
            panel.ignoresMouseEvents = isClickThrough
        }
    }

    var opacity: CGFloat = 0.86 {
        didSet {
            panel.alphaValue = opacity
        }
    }

    override init() {
        overlayView = LyricOverlayView(frame: NSRect(origin: .zero, size: Layout.panelSize))
        panel = LyricOverlayPanel(
            contentRect: overlayView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.contentView = overlayView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = isClickThrough
        panel.alphaValue = opacity
        panel.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reposition),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func showLoading(track: String, artist: String, source: String) {
        hasDisplayableContent = true
        overlayView.update(
            artist: artist,
            title: track,
            source: source,
            current: "Loading lyrics...",
            next: "",
            progress: 0,
            isPaused: false
        )
        show()
    }

    func showNoLyrics(track: String, artist: String, source: String) {
        hasDisplayableContent = true
        overlayView.update(
            artist: artist,
            title: track,
            source: source,
            current: "No lyrics found",
            next: "",
            progress: 0,
            isPaused: false
        )
        show()
    }

    func update(track: String, artist: String, source: String, current: String, next: String, progress: Double, isPaused: Bool) {
        hasDisplayableContent = true
        overlayView.update(
            artist: artist,
            title: track,
            source: source,
            current: current,
            next: next,
            progress: CGFloat(progress),
            isPaused: isPaused
        )
        show()
    }

    func hide() {
        hasDisplayableContent = false
        panel.orderOut(nil)
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.originX)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.originY)
        positionAtDefaultLocation()
    }

    @objc func reposition() {
        guard isEnabled else { return }
        if let savedOrigin = savedOrigin(), isOriginUsable(savedOrigin) {
            setPanelOrigin(savedOrigin)
        } else {
            positionAtDefaultLocation()
        }
    }

    private func show() {
        guard isEnabled else { return }
        if !panel.isVisible {
            reposition()
            panel.orderFrontRegardless()
        }
    }

    private func positionAtDefaultLocation() {
        let screen = screenForOverlay()
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 14
        setPanelOrigin(NSPoint(
            x: visibleFrame.maxX - panel.frame.width - margin,
            y: visibleFrame.minY + margin
        ))
    }

    private func setPanelOrigin(_ origin: NSPoint) {
        isPositioning = true
        panel.setFrameOrigin(clampedOrigin(origin))
        isPositioning = false
    }

    private func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: DefaultsKey.originX) != nil,
              defaults.object(forKey: DefaultsKey.originY) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: DefaultsKey.originX),
            y: defaults.double(forKey: DefaultsKey.originY)
        )
    }

    private func isOriginUsable(_ origin: NSPoint) -> Bool {
        let candidate = NSRect(origin: origin, size: panel.frame.size)
        return NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(candidate)
        }
    }

    private func screenForOverlay() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let candidate = NSRect(origin: origin, size: panel.frame.size)
        let visibleFrame = screen(for: candidate).visibleFrame
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - panel.frame.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - panel.frame.height)

        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), maxX),
            y: min(max(origin.y, visibleFrame.minY), maxY)
        )
    }

    private func screen(for rect: NSRect) -> NSScreen {
        let screensWithArea = NSScreen.screens.map { screen -> (screen: NSScreen, area: CGFloat) in
            let intersection = rect.intersection(screen.visibleFrame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (screen, area)
        }

        if let best = screensWithArea.max(by: { $0.area < $1.area }), best.area > 0 {
            return best.screen
        }

        let center = NSPoint(x: rect.midX, y: rect.midY)
        if let containing = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return containing
        }

        return NSScreen.main ?? NSScreen.screens.first!
    }
}

extension LyricOverlayController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard !isPositioning, panel.isVisible else { return }
        let origin = panel.frame.origin
        let clamped = clampedOrigin(origin)
        if abs(origin.x - clamped.x) > 0.5 || abs(origin.y - clamped.y) > 0.5 {
            setPanelOrigin(clamped)
        }
        UserDefaults.standard.set(Double(panel.frame.origin.x), forKey: DefaultsKey.originX)
        UserDefaults.standard.set(Double(panel.frame.origin.y), forKey: DefaultsKey.originY)
    }
}

private final class LyricOverlayView: NSView {
    private enum Metrics {
        static let panelWidth: CGFloat = 248
        static let horizontalPadding: CGFloat = 14
        static let currentSingleLineHeight: CGFloat = 22
        static let currentDoubleLineHeight: CGFloat = 42
    }

    private let artistLabel = DraggableTextField(labelWithString: "")
    private let titleLabel = DraggableTextField(labelWithString: "")
    private let currentLabel = DraggableTextField(labelWithString: "")
    private let nextLabel = DraggableTextField(labelWithString: "")
    private let sourceLabel = DraggableTextField(labelWithString: "")
    private let progressView = LyricProgressView(frame: .zero)
    private var currentHeightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var mouseDownCanMoveWindow: Bool { true }

    func update(artist: String, title: String, source: String, current: String, next: String, progress: CGFloat, isPaused: Bool) {
        artistLabel.stringValue = artist.isEmpty ? "Unknown Artist" : artist
        titleLabel.stringValue = title
        let currentText = current.isEmpty ? "Instrumental" : current
        let availableWidth = textWidth()
        let currentDisplay = fittedMultilineText(
            currentText,
            font: currentLabel.font ?? .systemFont(ofSize: 17, weight: .semibold),
            maxWidth: availableWidth,
            maxLines: 2
        )

        currentLabel.stringValue = currentDisplay.value
        nextLabel.stringValue = fittedSingleLineText(
            next,
            font: nextLabel.font ?? .systemFont(ofSize: 12, weight: .regular),
            maxWidth: availableWidth
        )
        sourceLabel.stringValue = isPaused ? "Paused • Source: \(source)" : "Source: \(source)"
        progressView.progress = progress

        currentHeightConstraint?.constant = currentDisplay.lineCount > 1
            ? Metrics.currentDoubleLineHeight
            : Metrics.currentSingleLineHeight
        needsLayout = true
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.34).cgColor
        layer?.borderWidth = 1.25

        artistLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        artistLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        artistLabel.allowsDefaultTighteningForTruncation = true

        titleLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.46)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.allowsDefaultTighteningForTruncation = true

        currentLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        currentLabel.textColor = .white
        currentLabel.lineBreakMode = .byWordWrapping
        currentLabel.maximumNumberOfLines = 2
        currentLabel.allowsDefaultTighteningForTruncation = true
        currentLabel.usesSingleLineMode = false
        currentLabel.cell?.wraps = true
        currentLabel.cell?.isScrollable = false
        currentLabel.cell?.usesSingleLineMode = false
        currentLabel.cell?.lineBreakMode = .byWordWrapping

        nextLabel.font = .systemFont(ofSize: 12, weight: .regular)
        nextLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        nextLabel.lineBreakMode = .byTruncatingTail
        nextLabel.maximumNumberOfLines = 1
        nextLabel.allowsDefaultTighteningForTruncation = true

        sourceLabel.font = .systemFont(ofSize: 10, weight: .medium)
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.maximumNumberOfLines = 1
        sourceLabel.allowsDefaultTighteningForTruncation = true

        for view in [artistLabel, titleLabel, currentLabel, nextLabel, sourceLabel, progressView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        for label in [artistLabel, titleLabel, currentLabel, nextLabel, sourceLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        for label in [currentLabel, nextLabel] {
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        let currentHeight = currentLabel.heightAnchor.constraint(equalToConstant: Metrics.currentSingleLineHeight)
        currentHeightConstraint = currentHeight

        NSLayoutConstraint.activate([
            artistLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            artistLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            artistLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            artistLabel.heightAnchor.constraint(equalToConstant: 13),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            titleLabel.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 1),
            titleLabel.heightAnchor.constraint(equalToConstant: 12),

            currentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            currentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            currentLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            currentHeight,

            nextLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            nextLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            nextLabel.topAnchor.constraint(equalTo: currentLabel.bottomAnchor, constant: 5),
            nextLabel.heightAnchor.constraint(equalToConstant: 16),

            nextLabel.bottomAnchor.constraint(lessThanOrEqualTo: sourceLabel.topAnchor, constant: -4),

            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            sourceLabel.bottomAnchor.constraint(equalTo: progressView.topAnchor, constant: -5),
            sourceLabel.heightAnchor.constraint(equalToConstant: 12),

            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            progressView.heightAnchor.constraint(equalToConstant: 3)
        ])
    }

    private func textWidth() -> CGFloat {
        let viewWidth = bounds.width > 0 ? bounds.width : Metrics.panelWidth
        return max(viewWidth - (Metrics.horizontalPadding * 2), 1)
    }

    private func fittedMultilineText(_ text: String, font: NSFont, maxWidth: CGFloat, maxLines: Int) -> (value: String, lineCount: Int) {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return ("", 1) }

        let lines = fittedLines(normalized, font: font, maxWidth: maxWidth, maxLines: maxLines)
        return (lines.joined(separator: "\n"), lines.count)
    }

    private func fittedSingleLineText(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return "" }
        return truncatedSingleLine(normalized, font: font, maxWidth: maxWidth)
    }

    private func fittedLines(_ text: String, font: NSFont, maxWidth: CGFloat, maxLines: Int) -> [String] {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var lines: [String] = []
        var currentLine = ""
        var index = 0

        while index < words.count {
            let word = words[index]

            if currentLine.isEmpty {
                if measuredWidth(word, font: font) <= maxWidth {
                    currentLine = word
                    index += 1
                    continue
                }

                if lines.count == maxLines - 1 {
                    lines.append(truncatedSingleLine(word, font: font, maxWidth: maxWidth))
                    return lines
                }

                let split = splitWord(word, font: font, maxWidth: maxWidth)
                lines.append(split.prefix)
                if split.remainder.isEmpty {
                    index += 1
                } else {
                    words[index] = split.remainder
                }
                continue
            }

            let candidate = "\(currentLine) \(word)"
            if measuredWidth(candidate, font: font) <= maxWidth {
                currentLine = candidate
                index += 1
                continue
            }

            if lines.count == maxLines - 1 {
                let remaining = words[index...].joined(separator: " ")
                lines.append(truncatedSingleLine("\(currentLine) \(remaining)", font: font, maxWidth: maxWidth))
                return lines
            }

            lines.append(currentLine)
            currentLine = ""
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [""] : Array(lines.prefix(maxLines))
    }

    private func splitWord(_ word: String, font: NSFont, maxWidth: CGFloat) -> (prefix: String, remainder: String) {
        let characters = Array(word)
        var low = 1
        var high = characters.count
        var best = 1

        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(characters.prefix(mid))
            if measuredWidth(candidate, font: font) <= maxWidth {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return (
            String(characters.prefix(best)),
            String(characters.dropFirst(best))
        )
    }

    private func truncatedSingleLine(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        guard measuredWidth(text, font: font) > maxWidth else { return text }

        let characters = Array(text)
        var low = 0
        var high = characters.count
        var best = "…"

        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(characters.prefix(mid)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            if measuredWidth(candidate, font: font) <= maxWidth {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }

    private func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

private final class DraggableTextField: NSTextField {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class LyricProgressView: NSView {
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private var rawProgress: CGFloat = 0

    var progress: CGFloat {
        get { rawProgress }
        set {
            let nextProgress = min(max(newValue, 0), 1)
            let shouldAnimate = nextProgress >= rawProgress && bounds.width > 0
            rawProgress = nextProgress
            updateFill(animated: shouldAnimate)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2
        updateFill(animated: false)
    }

    private func setup() {
        wantsLayer = true
        trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        fillLayer.backgroundColor = NSColor.white.withAlphaComponent(0.74).cgColor
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
    }

    private func updateFill(animated: Bool) {
        guard bounds.width > 0 else { return }

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.22 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))

        fillLayer.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width * rawProgress,
            height: bounds.height
        )
        fillLayer.cornerRadius = bounds.height / 2

        CATransaction.commit()
    }
}
