import Cocoa

struct PlayerState {
    let track: String
    let artist: String
    let position: Double
    let duration: Double
    let id: String
    let playing: Bool
    let source: String
}

struct PlayerConfig {
    let name: String
    let durationDivisor: Double
    let idProperty: String
}

enum PlayerReader {
    static let players: [PlayerConfig] = [
        PlayerConfig(name: "Spotify", durationDivisor: 1000, idProperty: "id"),
        PlayerConfig(name: "Music",   durationDivisor: 1,    idProperty: "persistent ID")
    ]

    private static func runAppleScript(_ script: String, timeout: Double = 2.0) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                return nil
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isAppRunning(_ name: String) -> Bool {
        runAppleScript("application \"\(name)\" is running") == "true"
    }

    static func state(for player: PlayerConfig) -> PlayerState? {
        let script = """
        if application "\(player.name)" is running then
            tell application "\(player.name)"
                if player state is playing or player state is paused then
                    set t to name of current track
                    set a to artist of current track
                    set p to player position
                    set d to duration of current track
                    set i to \(player.idProperty) of current track
                    set s to player state as string
                    return t & "||" & a & "||" & p & "||" & d & "||" & i & "||" & s
                else
                    return ""
                end if
            end tell
        else
            return ""
        end if
        """
        guard let out = runAppleScript(script), out.contains("||") else { return nil }
        let parts = out.components(separatedBy: "||")
        guard parts.count >= 6 else { return nil }
        guard let position = Double(parts[2].replacingOccurrences(of: ",", with: ".")),
              let rawDuration = Double(parts[3].replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return PlayerState(
            track: parts[0],
            artist: parts[1],
            position: position,
            duration: rawDuration / player.durationDivisor,
            id: "\(player.name):\(parts[4])",
            playing: parts[5] == "playing",
            source: player.name
        )
    }

    private static let mediaRemoteBundle: CFBundle? = {
        return CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework"))
    }()
    
    private typealias MRMediaRemoteGetNowPlayingApplicationPIDFunction = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void
    
    private static let MRMediaRemoteGetNowPlayingApplicationPID: MRMediaRemoteGetNowPlayingApplicationPIDFunction? = {
        guard let bundle = mediaRemoteBundle,
              let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPID" as CFString) else {
            return nil
        }
        return unsafeBitCast(pointer, to: MRMediaRemoteGetNowPlayingApplicationPIDFunction.self)
    }()
    
    private static let MRMediaRemoteGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction? = {
        guard let bundle = mediaRemoteBundle,
              let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) else {
            return nil
        }
        return unsafeBitCast(pointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
    }()

    private static func fetchMediaRemoteState() -> PlayerState? {
        guard let getNowPlayingApplicationPID = MRMediaRemoteGetNowPlayingApplicationPID,
              let getNowPlayingInfo = MRMediaRemoteGetNowPlayingInfo else {
            return nil
        }
        
        var pid: Int32 = 0
        let semaPID = DispatchSemaphore(value: 0)
        getNowPlayingApplicationPID(DispatchQueue.global()) { returnedPid in
            pid = returnedPid
            semaPID.signal()
        }
        _ = semaPID.wait(timeout: .now() + 0.5)
        
        guard pid > 0 else { return nil }
        
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              bundleID.lowercased().contains("tidal") else {
            return nil
        }
        
        var state: PlayerState? = nil
        let semaInfo = DispatchSemaphore(value: 0)
        getNowPlayingInfo(DispatchQueue.global()) { info in
            let dict = info as NSDictionary
            if let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
               let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String {
                let duration = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0.0
                var elapsed = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0.0
                let playbackRate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0
                let isPlaying = playbackRate > 0.0
                
                if isPlaying, let timestamp = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                    let timeSinceLastUpdate = Date().timeIntervalSince(timestamp)
                    elapsed += timeSinceLastUpdate
                }
                
                let contentID = dict["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String ?? ""
                let trackID = "TIDAL:\(contentID.isEmpty ? "\(title)-\(artist)" : contentID)"
                
                state = PlayerState(
                    track: title,
                    artist: artist,
                    position: elapsed,
                    duration: duration,
                    id: trackID,
                    playing: isPlaying,
                    source: "TIDAL"
                )
            }
            semaInfo.signal()
        }
        _ = semaInfo.wait(timeout: .now() + 0.5)
        
        return state
    }

    static func currentState() -> PlayerState? {
        let states = players.compactMap { state(for: $0) }
        if let playing = states.first(where: { $0.playing }) { return playing }
        
        if let tidalState = fetchMediaRemoteState() {
            if tidalState.playing {
                return tidalState
            }
            if states.isEmpty {
                return tidalState
            }
        }
        
        return states.first
    }
}
