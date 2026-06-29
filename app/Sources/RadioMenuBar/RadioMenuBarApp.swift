import AppKit
import SwiftUI

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
                    let shortcut = index < 9 ? KeyEquivalent(Character("\(index + 1)")) : nil

                    Button {
                        player.play(station)
                    } label: {
                        SelectableMenuRow(
                            title: station.name,
                            isSelected: station == player.currentStation,
                            selectedSystemImage: player.isPlaying ? "speaker.wave.2.fill" : "checkmark",
                            shortcutHint: index < 9 ? "⌘\(index + 1)" : nil
                        )
                    }
                    .optionalKeyboardShortcut(shortcut)
                }

                Divider()

                Button {
                    player.toggleShowStationName()
                } label: {
                    SelectableMenuRow(
                        title: "Display Radio Station",
                        isSelected: player.showStationName
                    )
                }

                Button {
                    launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
                } label: {
                    SelectableMenuRow(
                        title: "Launch at Login",
                        isSelected: launchAtLogin.isEnabled
                    )
                }
                .disabled(!launchAtLogin.isAvailable)

                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let statusMessage = launchAtLogin.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !launchAtLogin.isAvailable {
                    Text("Available in the built app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button {
                    player.reloadStations()
                } label: {
                    CommandMenuRow(title: "Reload Stations", shortcutHint: "⌘⇧,")
                }
                .keyboardShortcut(KeyEquivalent(","), modifiers: [.command, .shift])

                Button {
                    player.openStationsConfig()
                } label: {
                    CommandMenuRow(title: "Open Stations Config", shortcutHint: "⌘,")
                }
                .keyboardShortcut(KeyEquivalent(","))

                if let configMessage = player.configMessage {
                    Text(configMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let configErrorMessage = player.configErrorMessage {
                    Text(configErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    CommandMenuRow(title: "Quit", shortcutHint: "⌘Q")
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .frame(width: 320, alignment: .leading)
            .padding(14)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: player.isPlaying ? "radio.fill" : "radio")
                if let station = player.currentStation, player.showStationName {
                    Text(station.name)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
