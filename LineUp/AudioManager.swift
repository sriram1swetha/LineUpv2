import Foundation
import Combine
import AVFoundation

final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    private var player: AVAudioPlayer?
    private var didStart = false

    private init() {}

    func startBackgroundMusic() {
        guard !didStart else { return }
        didStart = true

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            guard let url = Bundle.main.url(forResource: "Rainy_Library_Corner", withExtension: "mp3") else {
                print("Background music file not found in bundle.")
                return
            }

            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0.7
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("Failed to start background music: \\(error.localizedDescription)")
        }
    }

    func stopBackgroundMusic() {
        player?.stop()
        didStart = false
    }
}
