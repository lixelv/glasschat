#if DEBUG
import Foundation

extension SelfTests {
    static func multipart() {
        var form = MultipartForm(boundary: "B")
        form.add("model", "whisper-1")
        form.add(file: "file", filename: "speech.wav", mimeType: "audio/wav", data: Data("RIFF".utf8))
        let text = String(decoding: form.body, as: UTF8.self)
        expect(form.contentType == "multipart/form-data; boundary=B", "content type")
        expect(text.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"), "field part")
        expect(text.contains("--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n"), "file part")
        expect(text.hasSuffix("--B--\r\n"), "closing boundary")
    }
}
#endif
