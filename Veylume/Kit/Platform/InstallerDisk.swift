import AppKit
import CryptoKit

/// One launch-time pass, outside the UI thread. Only our exact, read-only DMG
/// installer is eligible; never force-eject, delete the download or scan disks.
enum InstallerDisk {
    static func ejectMatchingImage(app: URL) {
        guard isInstalled(app) else { return }
        guard let images = mountedDiskImages() else { return }
        for volume in matchingVolumes(app: app, images: images) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }
    }
    static func isInstalled(_ app: URL, roots: [URL] = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]) -> Bool {
        roots.contains { $0.standardizedFileURL == app.deletingLastPathComponent().standardizedFileURL }
    }
    static func matchingVolumes(app: URL, images: [URL], volumesRoot: URL = URL(fileURLWithPath: "/Volumes"),
                                readOnly: (URL) -> Bool = { (try? $0.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true }) -> [URL] {
        let info = app.appendingPathComponent("Contents/Info.plist")
        guard let metadata = try? Data(contentsOf: info), metadata.count <= 65536,
              let dictionary = try? PropertyListSerialization.propertyList(from: metadata, format: nil) as? [String: Any],
              let identifier = dictionary["CFBundleIdentifier"] as? String, !identifier.isEmpty,
              let executable = dictionary["CFBundleExecutable"] as? String, !executable.isEmpty,
              !executable.contains("/"), executable != ".", executable != "..",
              let digest = digest(app.appendingPathComponent("Contents/MacOS/" + executable)) else { return [] }
        let allowed: Set<String> = ["Veylume.app", "Applications", "Read me.txt", ".background.png", ".VolumeIcon.icns", ".DS_Store", ".fseventsd", ".Trashes", ".Spotlight-V100", ".TemporaryItems"]
        return images.filter { volume in
            guard volume.deletingLastPathComponent().standardizedFileURL == volumesRoot.standardizedFileURL,
                  !app.standardizedFileURL.path.hasPrefix(volume.standardizedFileURL.path + "/"), readOnly(volume),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: volume.path),
                  Set(names).isSubset(of: allowed), names.contains("Read me.txt"),
                  (try? FileManager.default.destinationOfSymbolicLink(atPath: volume.appendingPathComponent("Applications").path)) == "/Applications" else { return false }
            let candidate = volume.appendingPathComponent("Veylume.app")
            guard (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  (try? Data(contentsOf: candidate.appendingPathComponent("Contents/Info.plist"))) == metadata else { return false }
            return Self.digest(candidate.appendingPathComponent("Contents/MacOS/" + executable)) == digest
        }
    }
    private static func digest(_ url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var hash = SHA256()
        do {
            while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
            return Data(hash.finalize())
        } catch { return nil }
    }
    private static func mountedDiskImages() -> [URL]? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); process.arguments = ["info", "-plist"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { if process.isRunning { process.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 1024 * 1024,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return nil }
        return images.flatMap { image -> [URL] in
            guard let path = image["image-path"] as? String, URL(fileURLWithPath: path).pathExtension.lowercased() == "dmg",
                  let entities = image["system-entities"] as? [[String: Any]] else { return [] }
            return entities.compactMap { ($0["mount-point"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        }
    }
}
