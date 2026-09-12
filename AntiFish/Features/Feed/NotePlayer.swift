import AVFoundation
import Observation

@MainActor
@Observable
final class NotePlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private(set) var isPlaying = false
    private(set) var currentURL: URL?
    private(set) var progress: Double = 0

    func toggle(url: URL) {
        if isPlaying, currentURL == url {
            player?.pause()
            isPlaying = false
            stopTicking()
            return
        }
        if currentURL != url {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            currentURL = url
            progress = 0
        }
        player?.play()
        isPlaying = player?.isPlaying ?? false
        if isPlaying { startTicking() }
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(1, fraction)) * player.duration
        progress = max(0, min(1, fraction))
    }

    func stop() {
        player?.stop()
        isPlaying = false
        stopTicking()
    }

    var duration: Double { player?.duration ?? 0 }
    var elapsed: Double { player?.currentTime ?? 0 }

    private func startTicking() {
        stopTicking()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.progress = player.currentTime / player.duration
            }
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = 1
            self.stopTicking()
        }
    }
}
