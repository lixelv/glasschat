import Foundation

/// A multipart/form-data body (fields and files), for the audio endpoints.
struct MultipartForm {
    private let boundary: String
    private var parts = Data()

    init(boundary: String = "GlassChat-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    var body: Data { parts + Data("--\(boundary)--\r\n".utf8) }

    mutating func add(_ name: String, _ value: String) {
        parts += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)
    }

    mutating func add(file name: String, filename: String, mimeType: String, data: Data) {
        parts += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
        parts += data
        parts += Data("\r\n".utf8)
    }
}
