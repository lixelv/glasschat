#if DEBUG
import AVFoundation

extension SelfTests {
    static func bargeIn() {
        expect(!BargeIn.isMeaningful(heard: "подожди стоп", voiced: 0.3, spoken: ""), "too little voice")
        expect(!BargeIn.isMeaningful(heard: "да", voiced: 0.8, spoken: ""), "one short word")
        expect(!BargeIn.isMeaningful(heard: "Thank you", voiced: 1, spoken: ""), "a noise phrase")
        expect(!BargeIn.isMeaningful(heard: "восемь градусов облачность", voiced: 1, spoken: "В Таллине восемь градусов, облачность"),
               "the assistant's own words (echo)")
        expect(BargeIn.isMeaningful(heard: "подожди, лучше про Париж", voiced: 0.9, spoken: "В Таллине восемь градусов"), "a real interruption")
        expect(BargeIn.isMeaningful(heard: "стоп", voiced: 0.6, spoken: ""), "one clear word")
        expect(!BargeIn.isMeaningful(heard: "да и", voiced: 1, spoken: "Да, и в Москве"), "short words of the assistant's (echo)")
        expect(BargeIn.isMeaningful(heard: "ну да", voiced: 1, spoken: "В Москве тепло"), "short words of the user's own")

        // Only the words after a pause in the live text are judged and sent; their voice is counted from there.
        var utterance = BargeIn.Utterance()
        var now = utterance.update("восемь градусов облачность", voiced: 1.0, at: 3)
        expect(now.text == "восемь градусов облачность" && now.voiced == 1.0, "the first words are the utterance")
        now = utterance.update("восемь градусов облачность подожди стоп", voiced: 1.6, at: 6)
        expect(now.text == "подожди стоп", "after a pause only the new words")
        expect(abs(now.voiced - 0.6) < 1e-9, "after a pause only the new voice")
        expect(utterance.start == 6, "the utterance starts at its first words")
        now = utterance.update("восемь градусов облачность подожди стоп сейчас", voiced: 2.0, at: 6.4)
        expect(now.text == "подожди стоп сейчас" && utterance.start == 6, "words without a pause go on the utterance")
        now = utterance.update("Восемь градусов. Подожди стоп сейчас же", voiced: 2.2, at: 6.8)
        expect(now.text == "Восемь градусов. Подожди стоп сейчас же", "earlier words rewritten: the whole text")

        // Whisper hears only the interrupting phrase: the recording is cut at its start.
        let url = FileManager.default.temporaryDirectory.appending(path: "glasschat-trim-test-\(UUID().uuidString).wav")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        if let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true),
           let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000) {
            buffer.frameLength = 48_000
            for i in 0..<48_000 { buffer.int16ChannelData![0][i] = i < 16_000 ? 0 : 1000 }
            try? file.write(from: buffer)
        }
        let cut = VoiceRecorder.trimmed(Recording(url: url, duration: 3, voiced: 2), from: 1)
        let rest = try? AVAudioFile(forReading: cut.url)
        let firstSample: Float? = rest.flatMap { file in
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1).flatMap { one in
                (try? file.read(into: one, frameCount: 1)).map { one.floatChannelData![0][0] }
            }
        }
        expect(rest?.length == 32_000 && firstSample.map { abs($0 - 1000 / 32768) < 0.001 } == true, "the recording is cut at the phrase")
        expect(!FileManager.default.fileExists(atPath: url.path), "the whole recording is removed")
        try? FileManager.default.removeItem(at: cut.url)
    }
}
#endif
