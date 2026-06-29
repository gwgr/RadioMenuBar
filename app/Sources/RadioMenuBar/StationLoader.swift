import Foundation

struct StationLoadResult {
    let stations: [Station]
    let configURL: URL?
    let warningMessage: String?
}

struct StationLoader {
    var fileManager: FileManager = .default
    var currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var resourceURL: URL? = Bundle.main.resourceURL
    var applicationSupportDirectoryURL: URL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
    var defaultStations: [Station] = StationLoader.defaultStations

    func loadStations() -> StationLoadResult {
        let appSupportURL = applicationSupportConfigURL()
        ensureEditableConfig(at: appSupportURL)

        let configURLs = [
            appSupportURL,
            currentDirectoryURL.appendingPathComponent("stations.json"),
            currentDirectoryURL.appendingPathComponent("app/stations.json"),
            resourceURL?.appendingPathComponent("stations.json")
        ]
        .compactMap { $0 }

        var warnings: [String] = []
        var editableConfigURL: URL?

        for configURL in configURLs where fileManager.fileExists(atPath: configURL.path) {
            if editableConfigURL == nil {
                editableConfigURL = configURL
            }

            do {
                let data = try Data(contentsOf: configURL)
                let stations = try JSONDecoder().decode([Station].self, from: data)
                let validation = validate(stations)

                if !validation.warnings.isEmpty {
                    warnings.append("\(displayPath(for: configURL)): \(validation.warnings.joined(separator: "; "))")
                }

                if !validation.validStations.isEmpty {
                    return StationLoadResult(
                        stations: validation.validStations,
                        configURL: editableConfigURL ?? configURL,
                        warningMessage: warningMessage(from: warnings)
                    )
                }
            } catch {
                warnings.append("Could not load \(displayPath(for: configURL)): \(error.localizedDescription)")
            }
        }

        if !warnings.isEmpty {
            warnings.append("Using default station.")
        }

        return StationLoadResult(
            stations: defaultStations,
            configURL: editableConfigURL,
            warningMessage: warningMessage(from: warnings)
        )
    }

    private func validate(_ stations: [Station]) -> (validStations: [Station], warnings: [String]) {
        guard !stations.isEmpty else {
            return ([], ["Station list is empty"])
        }

        var warnings: [String] = []
        var validStations: [Station] = []
        var seenURLs = Set<String>()

        for station in stations {
            let trimmedName = station.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let urlString = station.url.absoluteString
            let scheme = station.url.scheme?.lowercased()

            if trimmedName.isEmpty {
                warnings.append("Ignored station with empty name")
                continue
            }

            if scheme != "http" && scheme != "https" {
                warnings.append("Ignored \(station.name) with unsupported URL scheme")
                continue
            }

            if seenURLs.contains(urlString) {
                warnings.append("Ignored duplicate URL for \(station.name)")
                continue
            }

            seenURLs.insert(urlString)
            validStations.append(station)
        }

        if validStations.isEmpty {
            warnings.append("No valid stations found")
        }

        return (validStations, warnings)
    }

    private func applicationSupportConfigURL() -> URL {
        applicationSupportDirectoryURL
            .appendingPathComponent("RadioMenuBar", isDirectory: true)
            .appendingPathComponent("stations.json")
    }

    private func ensureEditableConfig(at configURL: URL) {
        guard !fileManager.fileExists(atPath: configURL.path) else { return }

        let sourceURLs = [
            resourceURL?.appendingPathComponent("stations.json"),
            currentDirectoryURL.appendingPathComponent("app/stations.json"),
            currentDirectoryURL.appendingPathComponent("stations.json")
        ]
        .compactMap { $0 }

        do {
            try fileManager.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if let sourceURL = sourceURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) {
                try fileManager.copyItem(at: sourceURL, to: configURL)
            }
        } catch {
            // Falling back to bundled/dev config is fine if Application Support cannot be written.
        }
    }

    private func displayPath(for url: URL) -> String {
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        let path = url.path

        if path == homePath {
            return "~"
        }

        if path.hasPrefix(homePath + "/") {
            return "~/" + path.dropFirst(homePath.count + 1)
        }

        return path
    }

    private func warningMessage(from warnings: [String]) -> String? {
        guard !warnings.isEmpty else { return nil }
        return warnings.joined(separator: " ")
    }

    static var defaultStations: [Station] {
        [
            Station(
                name: "Triple M Melbourne 105.1",
                url: URL(string: "https://sa47.scastream.com.au/live/3mmm_128.stream/playlist.m3u8?dist=listnr-web")!
            )
        ]
    }
}
