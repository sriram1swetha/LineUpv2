import SwiftUI

struct ContentView: View {
    @StateObject private var navigator = Navigator()

    var body: some View {
        NavigationStack {
            MainMenuView()
        }
        // Re-keying the NavigationStack on `resetCount` change pops every
        // pushed view back to MainMenuView. This is how the "Go Home" button
        // in GameView returns the user to the root in one tap.
        .id(navigator.resetCount)
        .environmentObject(navigator)
    }
}
