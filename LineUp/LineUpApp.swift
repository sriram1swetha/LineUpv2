import SwiftUI

@main
struct LineUpApp: App {
    let settings = GameSettings.shared
    let scoreStore = ScoreStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(scoreStore)
                .onAppear {
                    AudioManager.shared.startBackgroundMusic()
                }
        }
    }
}
