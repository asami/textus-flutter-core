import AVFoundation
import Foundation

/// One owned CAF capture; automatic duration completion retains samples for stop.
final class IosAudioRecording: NSObject, AVAudioRecorderDelegate {
    let capturedAt: Date
    private let url: URL
    private var recorder: AVAudioRecorder?
    private var failure: Error?
    private let onFailure: (Error) -> Void

    init(maxDurationSeconds: Int, onFailure: @escaping (Error) -> Void) throws {
        capturedAt = Date()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        self.onFailure = onFailure
        super.init()
        do {
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            self.recorder = recorder
            recorder.delegate = self
            guard recorder.prepareToRecord(),
                  recorder.record(forDuration: TimeInterval(maxDurationSeconds)) else {
                throw NativeAudioFailure("recordingFailed", "The microphone recorder did not start")
            }
        } catch {
            try? cleanup()
            throw error
        }
    }

    func stop() throws -> Data {
        recorder?.stop()
        if let failure = failure { throw failure }
        do {
            return try PcmAudioFileReader.readCanonicalWave(from: url)
        } catch let error as PcmAudioFileReader.Failure {
            throw NativeAudioFailure(error.code, error.message)
        }
    }

    func cleanup() throws {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return } // Keep the actual buffer after an automatic duration stop.
        report(NativeAudioFailure("recordingFailed", "Recording did not finish successfully"))
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        report(error ?? NativeAudioFailure("recordingFailed", "The recorder reported an encoding error"))
    }

    private func report(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.recorder != nil else { return }
            self.failure = error
            self.onFailure(error)
        }
    }
}
