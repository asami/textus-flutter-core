import AVFoundation
import Foundation

/// Plays the exact validated saved WAV; no microphone or speech permission.
final class IosAudioPlayback: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private let completion: (Result<Void, Error>) -> Void
    private var finished = false

    init(bytes: Data, completion: @escaping (Result<Void, Error>) -> Void) throws {
        try CanonicalPcmWaveAudio.validate(bytes)
        self.completion = completion
        super.init()
        let player = try AVAudioPlayer(data: bytes)
        self.player = player
        player.delegate = self
        guard player.prepareToPlay(), player.play() else {
            cleanup()
            throw NativeAudioFailure("playbackFailed", "The saved audio player did not start")
        }
    }

    func cleanup() {
        finished = true
        player?.delegate = nil
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        publish(flag ? .success(()) : .failure(
            NativeAudioFailure("playbackFailed", "Saved audio playback did not finish successfully")
        ))
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        publish(.failure(error ?? NativeAudioFailure("playbackFailed", "Saved audio could not be decoded")))
    }

    private func publish(_ result: Result<Void, Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.finished else { return }
            self.finished = true
            self.completion(result)
        }
    }
}
