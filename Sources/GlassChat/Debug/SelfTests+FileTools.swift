#if DEBUG
import Foundation

extension SelfTests {
    static func fileTools() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "glasschat-selftest-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        func fails(_ body: () throws -> String) -> String? {
            do { _ = try body(); return nil } catch { return error.localizedDescription }
        }
        let file = dir.appending(path: "a b/notes.txt")

        expect((try? FileTools.write(file, content: "one\ntwo\nthree")) != nil, "write creates folders")
        expect((try? FileTools.read(file, offset: nil, limit: nil)) == "     1\tone\n     2\ttwo\n     3\tthree", "numbered lines")
        expect((try? FileTools.read(file, offset: 2, limit: 1)) == "     2\ttwo", "offset and limit")

        let long = dir.appending(path: "long.txt")
        _ = try? FileTools.write(long, content: String(repeating: "x", count: 2500))
        expect((try? FileTools.read(long, offset: nil, limit: nil))?.count == 7 + 2000 + 1, "long line cut at 2000 with …")

        let binary = dir.appending(path: "b.bin")
        try? Data([0x41, 0x00, 0x42]).write(to: binary)
        expect(fails { try FileTools.read(binary, offset: nil, limit: nil) }?.contains("binary") == true, "binary file refused")

        try? FileManager.default.createDirectory(at: dir.appending(path: "sub"), withIntermediateDirectories: true)
        let listing = (try? FileTools.read(dir, offset: nil, limit: nil)) ?? ""
        expect(listing == "a b/\nb.bin\nlong.txt\nsub/", "directory listing, folders with /")

        expect((try? FileTools.edit(file, old: "two", new: "2", replaceAll: false)) == "Replaced 1 occurrence.", "one edit")
        expect((try? String(contentsOf: file, encoding: .utf8)) == "one\n2\nthree", "edited text")
        expect(fails { try FileTools.edit(file, old: "zzz", new: "y", replaceAll: false) } != nil, "no match is an error")
        _ = try? FileTools.write(file, content: "a a")
        expect(fails { try FileTools.edit(file, old: "a", new: "b", replaceAll: false) }?.contains("2") == true, "several matches need replace_all")
        expect((try? FileTools.edit(file, old: "a", new: "b", replaceAll: true)) == "Replaced 2 occurrences.", "replace_all")
        expect(fails { try FileTools.edit(file, old: "b", new: "b", replaceAll: true) } != nil, "same text is an error")

        let cwd = URL(filePath: "/tmp/work")
        expect(FileTools.resolvePath("~/x.txt", cwd: cwd).path == FileManager.default.homeDirectoryForCurrentUser.appending(path: "x.txt").path, "~ is home")
        expect(FileTools.resolvePath("rel/y.txt", cwd: cwd).path == "/tmp/work/rel/y.txt", "relative to the chat's folder")
        expect(FileTools.resolvePath("/a b/c", cwd: cwd).path == "/a b/c", "absolute with spaces")
    }
}
#endif
