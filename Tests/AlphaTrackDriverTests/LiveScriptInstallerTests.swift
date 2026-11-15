import XCTest
@testable import AlphaTrackDriver

final class LiveScriptInstallerTests: XCTestCase {
    var tmp: URL!
    var source: URL!
    var remoteScripts: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("installer-\(UUID().uuidString)")
        source = tmp.appendingPathComponent("src/AlphaTrack")
        remoteScripts = tmp.appendingPathComponent("User Library/Remote Scripts")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("__pycache__"), withIntermediateDirectories: true)
        try "init".write(to: source.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
        try "script v1".write(to: source.appendingPathComponent("AlphaTrack.py"), atomically: true, encoding: .utf8)
        try "cache".write(to: source.appendingPathComponent("__pycache__/x.pyc"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testInstallThenUpToDateThenOutdated() throws {
        let installer = LiveScriptInstaller(source: source, remoteScriptsFolder: remoteScripts)
        XCTAssertEqual(installer.status(), .notInstalled)
        try installer.install()
        XCTAssertEqual(installer.status(), .installed)
        let files = try FileManager.default.contentsOfDirectory(atPath: installer.destination.path).sorted()
        XCTAssertEqual(files, ["AlphaTrack.py", "__init__.py"], "only .py files are copied")
        // A new build changes the script: destination is outdated until reinstalled.
        try "script v2".write(to: source.appendingPathComponent("AlphaTrack.py"), atomically: true, encoding: .utf8)
        XCTAssertEqual(installer.status(), .outdated)
        try installer.install()
        XCTAssertEqual(installer.status(), .installed)
        XCTAssertEqual(try String(contentsOf: installer.destination.appendingPathComponent("AlphaTrack.py")), "script v2")
    }

    func testDeveloperSymlinkIsDetectedAndReplaced() throws {
        let installer = LiveScriptInstaller(source: source, remoteScriptsFolder: remoteScripts)
        try FileManager.default.createDirectory(at: remoteScripts, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: installer.destination, withDestinationURL: source)
        guard case .symlink(let target) = installer.status() else { return XCTFail("expected symlink status") }
        XCTAssertEqual(target.path, source.path)
        try installer.install()
        XCTAssertEqual(installer.status(), .installed)
        let attrs = try FileManager.default.attributesOfItem(atPath: installer.destination.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeDirectory)
        try installer.uninstall()
        XCTAssertEqual(installer.status(), .notInstalled)
    }

    func testBundledSourceFindsCheckoutFromBuildProducts() throws {
        // The test bundle lives under .build/..., so walking up should reach the repo.
        let found = LiveScriptInstaller.bundledSource(bundle: Bundle(for: LiveScriptInstallerTests.self))
        XCTAssertNotNil(found)
        XCTAssertTrue(found!.path.hasSuffix("LiveRemoteScript/AlphaTrack"))
    }
}

final class LiveUserLibraryDetectionTests: XCTestCase {
    var prefs: URL!

    override func setUpWithError() throws {
        prefs = FileManager.default.temporaryDirectory.appendingPathComponent("ableton-prefs-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: prefs)
    }

    private func writeCfg(version: String, path: String?, name: String = "User Library") throws {
        let dir = prefs.appendingPathComponent("Live \(version)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = path.map { """
                <LibraryProject Id="0">
                    <ProjectLocation />
                    <ProjectName Value="\(name)" />
                    <ProjectPath Value="\($0)" />
                </LibraryProject>
        """ } ?? ""
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" Creator="Ableton Live \(version)">
            <ContentLibrary>
                <UserLibrary>
        \(project)
                </UserLibrary>
                <PreferredFactoryPacksInstallationPath Value="/somewhere/else" />
            </ContentLibrary>
        </Ableton>
        """
        try xml.write(to: dir.appendingPathComponent("Library.cfg"), atomically: true, encoding: .utf8)
    }

    func testReadsPathAndNameFromNewestVersion() throws {
        try writeCfg(version: "11.3.35", path: "/Volumes/Old/Ableton")
        try writeCfg(version: "12.4.16", path: "/Users/me/Music/Ableton")
        try writeCfg(version: "12.0.1", path: "/Users/me/Elsewhere", name: "My Library")
        let found = LiveScriptInstaller.detectUserLibrary(preferencesRoot: prefs)
        XCTAssertEqual(found?.liveVersion, "12.4.16")
        XCTAssertEqual(found?.userLibrary.path, "/Users/me/Music/Ableton/User Library")
        XCTAssertEqual(found?.remoteScriptsFolder.path, "/Users/me/Music/Ableton/User Library/Remote Scripts")
    }

    func testCustomLibraryNameAndFallbackToOlderVersion() throws {
        try writeCfg(version: "12.4.16", path: nil)                       // newest has no project entry
        try writeCfg(version: "12.1.0", path: "/Users/me/Elsewhere", name: "My Library")
        let found = LiveScriptInstaller.detectUserLibrary(preferencesRoot: prefs)
        XCTAssertEqual(found?.liveVersion, "12.1.0")
        XCTAssertEqual(found?.userLibrary.path, "/Users/me/Elsewhere/My Library")
    }

    func testNoPreferences() {
        XCTAssertNil(LiveScriptInstaller.detectUserLibrary(preferencesRoot: prefs))
    }

    func testVersionOrderingIsNumeric() {
        XCTAssertTrue(LiveScriptInstaller.versionKey("Live 9.7.7").lexicographicallyPrecedes(LiveScriptInstaller.versionKey("Live 12.0.0")))
    }
}
