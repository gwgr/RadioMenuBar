import XCTest
@testable import RadioMenuBar

final class StationLoaderTests: XCTestCase {
    func testLoadsValidConfig() throws {
        let fixture = try LoaderFixture()
        defer { fixture.cleanUp() }

        try fixture.writeCurrentConfig("""
        [
          { "name": "Station One", "url": "https://example.com/one.m3u8" }
        ]
        """)

        let result = fixture.loader().loadStations()

        XCTAssertEqual(result.stations, [
            Station(name: "Station One", url: URL(string: "https://example.com/one.m3u8")!)
        ])
        XCTAssertNil(result.warningMessage)
    }

    func testFallsBackAfterMalformedFirstConfig() throws {
        let fixture = try LoaderFixture()
        defer { fixture.cleanUp() }

        try fixture.writeApplicationSupportConfig("{")
        try fixture.writeCurrentConfig("""
        [
          { "name": "Fallback Station", "url": "https://example.com/fallback.m3u8" }
        ]
        """)

        let result = fixture.loader().loadStations()

        XCTAssertEqual(result.stations.map(\.name), ["Fallback Station"])
        XCTAssertTrue(result.warningMessage?.contains("Could not load") == true)
    }

    func testUsesDefaultStationWhenNoConfigExists() throws {
        let fixture = try LoaderFixture()
        defer { fixture.cleanUp() }

        let result = fixture.loader().loadStations()

        XCTAssertEqual(result.stations.map(\.name), ["Default Station"])
        XCTAssertNil(result.configURL)
        XCTAssertNil(result.warningMessage)
    }

    func testWarnsAndSkipsDuplicateURLs() throws {
        let fixture = try LoaderFixture()
        defer { fixture.cleanUp() }

        try fixture.writeCurrentConfig("""
        [
          { "name": "Station One", "url": "https://example.com/stream.m3u8" },
          { "name": "Duplicate Station", "url": "https://example.com/stream.m3u8" }
        ]
        """)

        let result = fixture.loader().loadStations()

        XCTAssertEqual(result.stations.map(\.name), ["Station One"])
        XCTAssertTrue(result.warningMessage?.contains("duplicate URL") == true)
    }

    func testWarnsAndSkipsEmptyNames() throws {
        let fixture = try LoaderFixture()
        defer { fixture.cleanUp() }

        try fixture.writeCurrentConfig("""
        [
          { "name": "   ", "url": "https://example.com/blank-name.m3u8" },
          { "name": "Valid Station", "url": "https://example.com/valid.m3u8" }
        ]
        """)

        let result = fixture.loader().loadStations()

        XCTAssertEqual(result.stations.map(\.name), ["Valid Station"])
        XCTAssertTrue(result.warningMessage?.contains("empty name") == true)
    }

    func testWarnsAndSkipsUnsupportedSchemes() throws {
        let fixture = try LoaderFixture()
        defer { fixture.cleanUp() }

        try fixture.writeCurrentConfig("""
        [
          { "name": "Local File", "url": "file:///tmp/local.m3u8" },
          { "name": "Valid Station", "url": "https://example.com/valid.m3u8" }
        ]
        """)

        let result = fixture.loader().loadStations()

        XCTAssertEqual(result.stations.map(\.name), ["Valid Station"])
        XCTAssertTrue(result.warningMessage?.contains("unsupported URL scheme") == true)
    }

    func testEmptyStationListFallsBackWithWarning() throws {
        let fixture = try LoaderFixture()
        defer { fixture.cleanUp() }

        try fixture.writeCurrentConfig("[]")

        let result = fixture.loader().loadStations()

        XCTAssertEqual(result.stations.map(\.name), ["Default Station"])
        XCTAssertTrue(result.warningMessage?.contains("Station list is empty") == true)
        XCTAssertTrue(result.warningMessage?.contains("Using default station.") == true)
    }
}

private struct LoaderFixture {
    let rootURL: URL
    let currentDirectoryURL: URL
    let applicationSupportDirectoryURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RadioMenuBarTests-\(UUID().uuidString)", isDirectory: true)
        currentDirectoryURL = rootURL.appendingPathComponent("cwd", isDirectory: true)
        applicationSupportDirectoryURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)

        try FileManager.default.createDirectory(
            at: currentDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: applicationSupportDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func loader() -> StationLoader {
        StationLoader(
            currentDirectoryURL: currentDirectoryURL,
            resourceURL: nil,
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            defaultStations: [
                Station(name: "Default Station", url: URL(string: "https://example.com/default.m3u8")!)
            ]
        )
    }

    func writeCurrentConfig(_ contents: String) throws {
        try contents.write(
            to: currentDirectoryURL.appendingPathComponent("stations.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeApplicationSupportConfig(_ contents: String) throws {
        let configURL = applicationSupportDirectoryURL
            .appendingPathComponent("RadioMenuBar", isDirectory: true)
            .appendingPathComponent("stations.json")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
