@testable import AppBundle
import Common
import Foundation
import Testing

struct RuntimeDirTest {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appending(component: "hyprspace-test-\(UUID().uuidString)").path
    }

    @Test func testCreatesPrivateDirectory() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        assertEquals(checkRuntimeDir(path, createIfMissing: false), .missing)
        assertEquals(checkRuntimeDir(path, createIfMissing: true), .ok)
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        assertEquals(permissions, 0o700)
        assertEquals(checkRuntimeDir(path, createIfMissing: false), .ok)
    }

    @Test func testRejectsDirectoryAccessibleByOthers() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        // The client only checks. It never changes the permissions
        assertEquals(checkRuntimeDir(path, createIfMissing: false), .unsafe("'\(path)' is accessible by other users"))
        // The server owns the directory, so it tightens the permissions
        assertEquals(checkRuntimeDir(path, createIfMissing: true), .ok)
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        assertEquals(permissions, 0o700)
    }

    @Test func testRejectsSymlinkAndRegularFile() throws {
        let target = tempPath()
        let link = tempPath()
        let file = tempPath()
        defer { [target, link, file].forEach { try? FileManager.default.removeItem(atPath: $0) } }
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        FileManager.default.createFile(atPath: file, contents: nil)

        assertEquals(checkRuntimeDir(link, createIfMissing: false), .unsafe("'\(link)' is not a directory"))
        assertEquals(checkRuntimeDir(link, createIfMissing: true), .unsafe("'\(link)' is not a directory"))
        assertEquals(checkRuntimeDir(file, createIfMissing: true), .unsafe("'\(file)' is not a directory"))
    }

    @Test func testSocketPathIsInsideTheRuntimeDir() {
        assertEquals(getSocketPath(appId: "dev.hyprspace"), getRuntimeDirPath(appId: "dev.hyprspace") + "/hyprspace.sock")
        #expect(getRuntimeDirPath(appId: "dev.hyprspace").hasPrefix("/tmp/dev.hyprspace-"))
        #expect(getSocketPath(appId: "dev.hyprspace.debug").utf8.count < 100) // The limit for Unix sockets is 104 bytes
    }
}
