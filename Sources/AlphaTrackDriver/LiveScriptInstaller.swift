import Foundation

/// Installs the Ableton Live control-surface script (the `AlphaTrack` folder of Python
/// files) into Live's User Library, where Live lists it as a Control Surface.
public struct LiveScriptInstaller {
    public enum Status: Equatable, CustomStringConvertible {
        case notInstalled
        case installed
        case outdated
        /// A developer symlink points at a checkout instead of a copy.
        case symlink(URL)

        public var description: String {
            switch self {
            case .notInstalled: return "not installed"
            case .installed: return "installed, up to date"
            case .outdated: return "installed, outdated"
            case .symlink(let u): return "symlink to \(u.path)"
            }
        }
    }

    public static let scriptFolderName = "AlphaTrack"

    /// Live's default User Library location.
    public static var defaultRemoteScriptsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Ableton/User Library/Remote Scripts")
    }

    public let source: URL
    public let remoteScriptsFolder: URL
    public var destination: URL { remoteScriptsFolder.appendingPathComponent(LiveScriptInstaller.scriptFolderName) }

    public init(source: URL, remoteScriptsFolder: URL = LiveScriptInstaller.defaultRemoteScriptsFolder) {
        self.source = source
        self.remoteScriptsFolder = remoteScriptsFolder
    }

    /// The script folder shipped with this build: inside the app bundle's Resources, or,
    /// when running from a SwiftPM build, the `LiveRemoteScript/AlphaTrack` folder of the
    /// checkout found by walking up from the executable.
    public static func bundledSource(bundle: Bundle = .main) -> URL? {
        let relative = "LiveRemoteScript/\(scriptFolderName)"
        if let res = bundle.resourceURL?.appendingPathComponent(relative), isScriptFolder(res) {
            return res
        }
        var dir = bundle.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent(relative)
            if isScriptFolder(candidate) { return candidate }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    static func isScriptFolder(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("__init__.py").path)
    }

    /// The Python files that make up the script (no caches, no tests).
    public static func scriptFiles(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".py") }
            .sorted()
    }

    public func status() -> Status {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: destination.path),
           attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            let target = (try? fm.destinationOfSymbolicLink(atPath: destination.path)).map { URL(fileURLWithPath: $0) }
            return .symlink(target ?? destination)
        }
        guard fm.fileExists(atPath: destination.path) else { return .notInstalled }
        guard let files = try? LiveScriptInstaller.scriptFiles(in: source), !files.isEmpty else { return .outdated }
        for name in files {
            let a = fm.contents(atPath: source.appendingPathComponent(name).path)
            let b = fm.contents(atPath: destination.appendingPathComponent(name).path)
            if a == nil || a != b { return .outdated }
        }
        return .installed
    }

    /// Copy the script into place, replacing whatever is there (including a symlink).
    public func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: remoteScriptsFolder, withIntermediateDirectories: true)
        let staging = remoteScriptsFolder.appendingPathComponent(".\(LiveScriptInstaller.scriptFolderName)-staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for name in try LiveScriptInstaller.scriptFiles(in: source) {
            try fm.copyItem(at: source.appendingPathComponent(name), to: staging.appendingPathComponent(name))
        }
        if fm.fileExists(atPath: destination.path) || (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: staging, to: destination)
    }

    public func uninstall() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) || (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            try fm.removeItem(at: destination)
        }
    }
}
