import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isAvailable: Bool
    @Published private(set) var statusMessage: String?
    @Published var errorMessage: String?

    private let service = SMAppService.mainApp

    init() {
        isAvailable = Bundle.main.bundleURL.pathExtension == "app"
        isEnabled = false
        refreshStatus()
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        statusMessage = nil

        do {
            if enabled {
                try enableLoginItem()
            } else {
                try disableLoginItem()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refreshStatus()
    }

    private func refreshStatus() {
        guard isAvailable else {
            isEnabled = false
            statusMessage = nil
            return
        }

        switch service.status {
        case .enabled:
            isEnabled = true
            statusMessage = nil
        case .requiresApproval:
            isEnabled = true
            statusMessage = "Allow launch at login in System Settings."
        case .notRegistered:
            isEnabled = Self.legacyLaunchAgentExists
            statusMessage = isEnabled ? "Using legacy LaunchAgent. Toggle off and on to migrate." : nil
        case .notFound:
            isEnabled = Self.legacyLaunchAgentExists
            statusMessage = isEnabled ? "Using legacy LaunchAgent. Toggle off and on to migrate." : nil
        @unknown default:
            isEnabled = Self.legacyLaunchAgentExists
            statusMessage = nil
        }
    }

    private func enableLoginItem() throws {
        guard isAvailable else {
            throw LaunchAtLoginError.appBundleRequired
        }

        try removeLegacyLaunchAgent()

        if service.status != .enabled {
            try service.register()
        }
    }

    private func disableLoginItem() throws {
        if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }

        try removeLegacyLaunchAgent()
    }

    private func removeLegacyLaunchAgent() throws {
        guard Self.legacyLaunchAgentExists else { return }
        try FileManager.default.removeItem(at: Self.legacyLaunchAgentURL)
    }

    private static var legacyLaunchAgentExists: Bool {
        FileManager.default.fileExists(atPath: legacyLaunchAgentURL.path)
    }

    private static var legacyLaunchAgentURL: URL {
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
