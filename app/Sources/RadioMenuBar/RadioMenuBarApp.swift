import AppKit
import AVFoundation
import MediaPlayer
import SwiftUI

struct Station: Codable, Identifiable, Hashable {
    let name: String
    let url: URL

    var id: String { url.absoluteString }
}

enum PlaybackState: String {
    case stopped = "Stopped"
    case loading = "Loading"
    case playing = "Playing"
    case paused = "Paused"
    case failed = "Failed"
}

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var stations: [Station] = []
    @Published private(set) var currentStation: Station?
    @Published private(set) var state: PlaybackState = .stopped
    @Published private(set) var volume: Float
    @Published var errorMessage: String?
    @Published var configMessage: String?
    @Published var showStationName: Bool

    private static let lastStationURLKey = "LastStationURL"
    private static let volumeKey = "Volume"
    fileprivate static let showStationNameKey = "ShowStationName"

    private var player: AVPlayer?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var configURL: URL?

    var isPlaying: Bool { state == .playing || state == .loading }

    init() {
        volume = UserDefaults.standard.object(forKey: Self.volumeKey) as? Float ?? 0.8
        showStationName = UserDefaults.standard.object(forKey: Self.showStationNameKey) as? Bool ?? true
        reloadStations(selectLastStation: true)
        configureRemoteCommands()
    }

    func play(_ station: Station) {
        stop()
        errorMessage = nil
        state = .loading
        currentStation = station
        UserDefaults.standard.set(station.url.absoluteString, forKey: Self.lastStationURLKey)

        let item = AVPlayerItem(url: station.url)
        player = AVPlayer(playerItem: item)
        player?.volume = volume
        observe(playerItem: item)
        updateNowPlayingInfo(for: station, playbackRate: 0)
        player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
        playerItemStatusObservation = nil
        timeControlStatusObservation = nil
        state = .stopped
        updateNowPlayingInfo(for: currentStation, playbackRate: 0)
    }

    func setVolume(_ newVolume: Float) {
        volume = min(max(newVolume, 0), 1)
        player?.volume = volume
        UserDefaults.standard.set(volume, forKey: Self.volumeKey)
    }

    func reloadStations(selectLastStation: Bool = false) {
        let previousStation = currentStation
        let result = Self.loadStations()
        stations = result.stations
        configURL = result.configURL
        configMessage = "Reloaded \(stations.count) stations"

        if selectLastStation {
            let lastURL = UserDefaults.standard.string(forKey: Self.lastStationURLKey)
            currentStation = stations.first { $0.url.absoluteString == lastURL } ?? stations.first
        } else if let previousStation {
            currentStation = stations.first { $0.url == previousStation.url } ?? stations.first
        } else {
            currentStation = stations.first
        }
    }

    func openStationsConfig() {
        guard let configURL else { return }

        let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        guard FileManager.default.fileExists(atPath: textEditURL.path) else {
            NSWorkspace.shared.open(configURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [configURL],
            withApplicationAt: textEditURL,
            configuration: configuration
        ) { [weak self] _, error in
            Task { @MainActor in
                self?.configMessage = error == nil ? "Opened stations config" : error?.localizedDescription
            }
        }
    }

    private func observe(playerItem: AVPlayerItem) {
        playerItemStatusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }

                switch item.status {
                case .readyToPlay:
                    self.errorMessage = nil
                case .failed:
                    self.state = .failed
                    self.errorMessage = item.error?.localizedDescription ?? "The stream failed to load."
                    self.updateNowPlayingInfo(for: self.currentStation, playbackRate: 0)
                case .unknown:
                    self.state = .loading
                @unknown default:
                    self.state = .failed
                    self.errorMessage = "The stream entered an unknown playback state."
                    self.updateNowPlayingInfo(for: self.currentStation, playbackRate: 0)
                }
            }
        }

        timeControlStatusObservation = player?.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.state != .failed else { return }

                switch player.timeControlStatus {
                case .playing:
                    self.state = .playing
                    self.updateNowPlayingInfo(for: self.currentStation, playbackRate: 1)
                case .paused:
                    self.state = self.player == nil ? .stopped : .paused
                    self.updateNowPlayingInfo(for: self.currentStation, playbackRate: 0)
                case .waitingToPlayAtSpecifiedRate:
                    self.state = .loading
                    self.updateNowPlayingInfo(for: self.currentStation, playbackRate: 0)
                @unknown default:
                    self.state = .loading
                    self.updateNowPlayingInfo(for: self.currentStation, playbackRate: 0)
                }
            }
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, let station = self.currentStation else { return }
                self.play(station)
            }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
            return .success
        }
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
            return .success
        }
    }

    private func updateNowPlayingInfo(for station: Station?, playbackRate: Double) {
        guard let station else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: "RadioMenuBar",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate
        ]
    }

    private static func loadStations() -> (stations: [Station], configURL: URL?) {
        let appSupportURL = applicationSupportConfigURL()
        ensureEditableConfig(at: appSupportURL)

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let configURLs = [
            appSupportURL,
            workingDirectory.appendingPathComponent("stations.json"),
            workingDirectory.appendingPathComponent("app/stations.json"),
            Bundle.main.resourceURL?.appendingPathComponent("stations.json")
        ]
        .compactMap { $0 }

        for configURL in configURLs where FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                return (try JSONDecoder().decode([Station].self, from: data), configURL)
            } catch {
                break
            }
        }

        return ([
            Station(
                name: "Triple M Melbourne 105.1",
                url: URL(string: "https://sa47.scastream.com.au/live/3mmm_128.stream/playlist.m3u8?dist=listnr-web")!
            )
        ], nil)
    }

    private static func applicationSupportConfigURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("RadioMenuBar", isDirectory: true)
            .appendingPathComponent("stations.json")
    }

    private static func ensureEditableConfig(at configURL: URL) {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }

        let sourceURLs = [
            Bundle.main.resourceURL?.appendingPathComponent("stations.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("app/stations.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("stations.json")
        ]
        .compactMap { $0 }

        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if let sourceURL = sourceURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                try FileManager.default.copyItem(at: sourceURL, to: configURL)
            }
        } catch {
            // Falling back to bundled/dev config is fine if Application Support cannot be written.
        }
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isAvailable: Bool
    @Published var errorMessage: String?

    private let label = "app.radiomenubar.RadioMenuBar"

    init() {
        isAvailable = Bundle.main.bundleURL.pathExtension == "app"
        isEnabled = FileManager.default.fileExists(atPath: Self.launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil

        do {
            if enabled {
                try installLaunchAgent()
            } else {
                try removeLaunchAgent()
            }
            isEnabled = enabled
        } catch {
            errorMessage = error.localizedDescription
            isEnabled = FileManager.default.fileExists(atPath: Self.launchAgentURL.path)
        }
    }

    private func installLaunchAgent() throws {
        guard isAvailable, let executableURL = Bundle.main.executableURL else {
            throw LaunchAtLoginError.appBundleRequired
        }

        try FileManager.default.createDirectory(
            at: Self.launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executableURL.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """

        try plist.write(to: Self.launchAgentURL, atomically: true, encoding: .utf8)
    }

    private func removeLaunchAgent() throws {
        if FileManager.default.fileExists(atPath: Self.launchAgentURL.path) {
            try FileManager.default.removeItem(at: Self.launchAgentURL)
        }
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/app.radiomenubar.RadioMenuBar.plist")
    }
}

enum LaunchAtLoginError: LocalizedError {
    case appBundleRequired

    var errorDescription: String? {
        "Build and launch RadioMenuBar.app before enabling launch at login."
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct RadioMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = PlayerController()
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                if let station = player.currentStation {
                    Text(station.name)
                        .font(.headline)
                    Text(player.state.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let errorMessage = player.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 12) {
                        Button {
                            player.play(station)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .disabled(player.isPlaying)

                        Button {
                            player.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .disabled(!player.isPlaying)

                        Spacer(minLength: 4)

                        Image(systemName: "speaker.fill")
                            .frame(width: 22)
                        Slider(
                            value: Binding(
                                get: { Double(player.volume) },
                                set: { player.setVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .frame(width: 115)
                    }

                    Divider()
                }

                ForEach(Array(player.stations.enumerated()), id: \.element.id) { index, station in
                    Button {
                        player.play(station)
                    } label: {
                        HStack(spacing: 10) {
                            if station == player.currentStation {
                                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "checkmark")
                                    .frame(width: 22)
                            } else {
                                Color.clear
                                    .frame(width: 22)
                            }
                            Text(station.name)
                            Spacer()
                            Text("⌘\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .contentShape(Rectangle())
                }

                Divider()

                Button {
                    player.showStationName.toggle()
                    UserDefaults.standard.set(player.showStationName, forKey: PlayerController.showStationNameKey)
                } label: {
                    HStack(spacing: 10) {
                        if player.showStationName {
                            Image(systemName: "checkmark")
                                .frame(width: 22)
                        } else {
                            Color.clear
                                .frame(width: 22)
                        }
                        Text("Display Radio Station")
                        Spacer()
                    }
                }
                .contentShape(Rectangle())

                Button {
                    launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
                } label: {
                    HStack(spacing: 10) {
                        if launchAtLogin.isEnabled {
                            Image(systemName: "checkmark")
                                .frame(width: 22)
                        } else {
                            Color.clear
                                .frame(width: 22)
                        }
                        Text("Launch at Login")
                        Spacer()
                    }
                }
                .disabled(!launchAtLogin.isAvailable)
                .contentShape(Rectangle())

                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !launchAtLogin.isAvailable {
                    Text("Available in the built app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button {
                    player.reloadStations()
                } label: {
                    HStack(spacing: 10) {
                        Color.clear
                            .frame(width: 22)
                        Text("Reload Stations")
                        Spacer()
                        Text("⌘R")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .keyboardShortcut("r")
                .contentShape(Rectangle())

                Button {
                    player.openStationsConfig()
                } label: {
                    HStack(spacing: 10) {
                        Color.clear
                            .frame(width: 22)
                        Text("Open Stations Config")
                        Spacer()
                    }
                }
                .contentShape(Rectangle())

                if let configMessage = player.configMessage {
                    Text(configMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack(spacing: 10) {
                        Text("Quit")
                        Spacer()
                        Text("⌘Q")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 22)
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .frame(width: 320, alignment: .leading)
            .padding(14)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: player.isPlaying ? "radio.fill" : "radio")
                    .renderingMode(.template)
                if let station = player.currentStation, player.showStationName {
                    Text(station.name)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
