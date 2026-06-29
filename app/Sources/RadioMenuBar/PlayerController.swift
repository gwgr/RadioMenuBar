import AppKit
import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI

enum PlaybackState: String {
    case stopped = "Stopped"
    case loading = "Loading"
    case playing = "Playing"
    case paused = "Paused"
    case failed = "Failed"
}

struct StationLoadResult {
    let stations: [Station]
    let configURL: URL?
    let warningMessage: String?
}

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var stations: [Station] = []
    @Published private(set) var currentStation: Station?
    @Published private(set) var state: PlaybackState = .stopped
    @Published private(set) var volume: Float
    @Published var errorMessage: String?
    @Published var configMessage: String?
    @Published var configErrorMessage: String?
    @Published var showStationName: Bool

    private static let lastStationURLKey = "LastStationURL"
    private static let volumeKey = "Volume"
    private static let showStationNameKey = "ShowStationName"

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

    func toggleShowStationName() {
        showStationName.toggle()
        UserDefaults.standard.set(showStationName, forKey: Self.showStationNameKey)
    }

    func reloadStations(selectLastStation: Bool = false) {
        let previousStation = currentStation
        let result = Self.loadStations()
        stations = result.stations
        configURL = result.configURL
        configMessage = "Reloaded \(stations.count) stations"
        configErrorMessage = result.warningMessage

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

    private static func loadStations() -> StationLoadResult {
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

        var warningMessage: String?
        var editableConfigURL: URL?

        for configURL in configURLs where FileManager.default.fileExists(atPath: configURL.path) {
            if editableConfigURL == nil {
                editableConfigURL = configURL
            }

            do {
                let data = try Data(contentsOf: configURL)
                let stations = try JSONDecoder().decode([Station].self, from: data)
                return StationLoadResult(
                    stations: stations,
                    configURL: editableConfigURL ?? configURL,
                    warningMessage: warningMessage
                )
            } catch {
                warningMessage = warningMessage ?? "Could not load \(displayPath(for: configURL)): \(error.localizedDescription)"
            }
        }

        return StationLoadResult(
            stations: defaultStations,
            configURL: editableConfigURL,
            warningMessage: warningMessage.map { "\($0). Using default station." }
        )
    }

    private static var defaultStations: [Station] {
        [
            Station(
                name: "Triple M Melbourne 105.1",
                url: URL(string: "https://sa47.scastream.com.au/live/3mmm_128.stream/playlist.m3u8?dist=listnr-web")!
            )
        ]
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

    private static func displayPath(for url: URL) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path

        if path == homePath {
            return "~"
        }

        if path.hasPrefix(homePath + "/") {
            return "~/" + path.dropFirst(homePath.count + 1)
        }

        return path
    }
}
