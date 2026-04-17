import Foundation
import Combine

/// Lightweight navigation coordinator.
///
/// The whole `NavigationStack` is keyed by `resetCount` (see ContentView).
/// Calling `goHome()` bumps the counter, which causes SwiftUI to rebuild the
/// stack from the root — popping all pushed views back to MainMenuView in one
/// step without having to convert every NavigationLink to a value-based one.
final class Navigator: ObservableObject {
    @Published var resetCount: Int = 0

    func goHome() {
        resetCount &+= 1
    }
}
