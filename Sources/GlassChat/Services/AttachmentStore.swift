import AppKit
import UniformTypeIdentifiers

/// Copies attached files into Application Support and turns them into Chat Completions content parts.
enum AttachmentStore {
    /// Text files above this are sent as files, not pasted into the message.
    static let maxInlineText = 400_000

    static var folder: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "GlassChat/files", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(of attachment: Attachment) -> URL {
        folder.appending(path: attachment.storedName)
    }

    static func data(of attachment: Attachment) -> Data? {
        try? Data(contentsOf: url(of: attachment))
    }

    /// Copies a file the user picked or dropped.
    static func importFile(at source: URL) throws -> Attachment {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        return try store(data, name: source.lastPathComponent, type: UTType(filenameExtension: source.pathExtension))
    }

    /// Stores bytes from the pasteboard (a pasted screenshot has no file).
    static func importImage(_ image: NSImage, name: String = "Pasted Image.png") throws -> Attachment {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try store(png, name: name, type: .png)
    }

    private static func store(_ data: Data, name: String, type: UTType?) throws -> Attachment {
        let ext = (name as NSString).pathExtension
        let storedName = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        try data.write(to: folder.appending(path: storedName), options: .atomic)
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        return Attachment(name: name, mimeType: mime, kind: kind(of: type, data: data), size: data.count, storedName: storedName)
    }

    private static func kind(of type: UTType?, data: Data) -> Attachment.Kind {
        if let type {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json)
                || type.conforms(to: .xml) || type.conforms(to: .propertyList) { return .text }
        }
        // Unknown extension (a Dockerfile, .env, .toml): text when it reads as UTF-8.
        if data.count <= maxInlineText, String(data: data, encoding: .utf8) != nil, !data.contains(0) { return .text }
        return .file
    }

    /// The parts of one attachment in a user message.
    static func contentPart(for attachment: Attachment) -> JSONValue? {
        guard let data = data(of: attachment) else {
            return .object(["type": .string("text"), "text": .string("[Attachment \(attachment.name) is missing]")])
        }
        let base64 = data.base64EncodedString()
        switch attachment.kind {
        case .image:
            return .object([
                "type": .string("image_url"),
                "image_url": .object(["url": .string("data:\(attachment.mimeType);base64,\(base64)")]),
            ])
        case .audio:
            let format = (attachment.name as NSString).pathExtension.lowercased()
            return .object([
                "type": .string("input_audio"),
                "input_audio": .object(["data": .string(base64), "format": .string(format.isEmpty ? "wav" : format)]),
            ])
        case .text where data.count <= maxInlineText:
            let text = String(decoding: data, as: UTF8.self)
            return .object(["type": .string("text"), "text": .string("File `\(attachment.name)`:\n```\n\(text)\n```")])
        case .pdf, .text, .file:
            return .object([
                "type": .string("file"),
                "file": .object([
                    "filename": .string(attachment.name),
                    "file_data": .string("data:\(attachment.mimeType);base64,\(base64)"),
                ]),
            ])
        }
    }

    static func icon(for attachment: Attachment) -> NSImage {
        NSWorkspace.shared.icon(for: UTType(mimeType: attachment.mimeType) ?? .data)
    }
}
