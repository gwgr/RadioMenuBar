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
        let result = StationLoader().loadStations()
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
}
