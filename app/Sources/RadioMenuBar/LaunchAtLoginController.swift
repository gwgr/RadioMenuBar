import Foundation
import SwiftUI

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
