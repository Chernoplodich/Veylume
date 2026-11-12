import Testing
import Foundation
@testable import VeylumeKit

struct InstallerDiskTests {
    @Test func onlyAnExactReadOnlyInstallerIsEligibleForEjection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeylumeInstaller-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appendingPathComponent("Applications"), volumes = root.appendingPathComponent("Volumes")
        let app = apps.appendingPathComponent("Veylume.app"), volume = volumes.appendingPathComponent("Veylume")
        for bundle in [app, volume.appendingPathComponent("Veylume.app")] {
            try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.Veylume", "CFBundleExecutable": "Veylume", "CFBundleVersion": "15"], format: .xml, options: 0)
            try info.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            try Data([1, 2, 3]).write(to: bundle.appendingPathComponent("Contents/MacOS/Veylume"))
        }
        try Data().write(to: volume.appendingPathComponent("Read me.txt"))
        try FileManager.default.createSymbolicLink(atPath: volume.appendingPathComponent("Applications").path, withDestinationPath: "/Applications")
        #expect(InstallerDisk.isInstalled(app, roots: [apps]))
        #expect(!InstallerDisk.isInstalled(volume.appendingPathComponent("Veylume.app"), roots: [apps]))
        #expect(InstallerDisk.matchingVolumes(app: app, images: [volume], volumesRoot: volumes, readOnly: { _ in true }) == [volume])
        #expect(InstallerDisk.matchingVolumes(app: app, images: [volume], volumesRoot: volumes, readOnly: { _ in false }).isEmpty)
        #expect(InstallerDisk.matchingVolumes(app: app, images: [volume], readOnly: { _ in true }).isEmpty)
        #expect(InstallerDisk.matchingVolumes(app: volume.appendingPathComponent("Veylume.app"), images: [volume], volumesRoot: volumes, readOnly: { _ in true }).isEmpty)
        try Data([1, 2, 4]).write(to: volume.appendingPathComponent("Veylume.app/Contents/MacOS/Veylume"))
        #expect(InstallerDisk.matchingVolumes(app: app, images: [volume], volumesRoot: volumes, readOnly: { _ in true }).isEmpty)
        try Data([1, 2, 3]).write(to: volume.appendingPathComponent("Veylume.app/Contents/MacOS/Veylume"))
        try Data().write(to: volume.appendingPathComponent("Unrelated document.txt"))
        #expect(InstallerDisk.matchingVolumes(app: app, images: [volume], volumesRoot: volumes, readOnly: { _ in true }).isEmpty)
    }
}
