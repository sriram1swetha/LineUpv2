import Foundation
import Combine
import AVFoundation

/// Plays a small playlist of background tracks back-to-back, looping the
/// playlist forever. Exposes play / pause / stop / skip controls and a
/// published `isPlaying` flag for UI binding.
final class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()

    // MARK: - Playlist

    /// File names (without extension). Add or rename freely — anything not
    /// found in the bundle is silently skipped at start-up.
    private let playlistFileNames: [String] = [
        "Rainy_Library_Corner",
        "Notes_from_the_Balcony"
    ]

    private struct Track {
        let name: String
        let url: URL
    }

    private var tracks: [Track] = []
    private var currentIndex: Int = 0
    private var player: AVAudioPlayer?
    private var didConfigureSession = false

    // MARK: - Public state

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTrackName: String = ""

    // MARK: - Init

    private override init() {
        super.init()
        loadTracks()
    }

    private func loadTracks() {
        tracks = playlistFileNames.compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
                print("AudioManager: \(name).mp3 not found in bundle (skipped).")
                return nil
            }
            return Track(name: name, url: url)
        }
    }

    private func ensureSessionConfigured() {
        guard !didConfigureSession else { return }
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            didConfigureSession = true
        } catch {
            print("AudioManager: failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Controls

    /// Called once at app launch. Starts the playlist if it isn't already
    /// running. Safe to call repeatedly.
    func startBackgroundMusic() {
        guard !isPlaying else { return }
        guard !tracks.isEmpty else {
            print("AudioManager: no tracks loaded.")
            return
        }
        ensureSessionConfigured()
        // If there's already a paused player, just resume.
        if let p = player, p.duration > 0 {
            p.play()
            isPlaying = true
            return
        }
        playCurrent()
    }

    /// Resume from a paused state, or start fresh if nothing is loaded.
    func play() {
        if player == nil {
            startBackgroundMusic()
            return
        }
        ensureSessionConfigured()
        player?.play()
        isPlaying = true
    }

    /// Pause the current track. The track stays loaded so `play()` resumes
    /// from the same position.
    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Stop and unload the current track. Next `play()` starts from the top
    /// of the current track.
    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
    }

    /// Skip to the next track in the playlist (wraps to the start).
    func next() {
        guard !tracks.isEmpty else { return }
        currentIndex = (currentIndex + 1) % tracks.count
        playCurrent()
    }

    /// Skip to the previous track (wraps to the end).
    func previous() {
        guard !tracks.isEmpty else { return }
        currentIndex = (currentIndex - 1 + tracks.count) % tracks.count
        playCurrent()
    }

    // MARK: - Internal

    private func playCurrent() {
        guard tracks.indices.contains(currentIndex) else { return }
        let track = tracks[currentIndex]
        ensureSessionConfigured()
        do {
            let p = try AVAudioPlayer(contentsOf: track.url)
            p.delegate = self
            p.numberOfLoops = 0      // single play; we advance manually
            p.volume = 0.7
            p.prepareToPlay()
            p.play()
            player = p
            currentTrackName = displayName(for: track.name)
            isPlaying = true
        } catch {
            print("AudioManager: failed to play \(track.name): \(error.localizedDescription)")
            isPlaying = false
        }
    }

    private func displayName(for fileName: String) -> String {
        fileName.replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Auto-advance to the next track and loop the playlist.
        guard !tracks.isEmpty else {
            isPlaying = false
            return
        }
        currentIndex = (currentIndex + 1) % tracks.count
        playCurrent()
    }
}
