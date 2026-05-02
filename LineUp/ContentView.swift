import SwiftUI

struct ContentView: View {
    @EnvironmentObject var userSession: UserSession
    @StateObject private var navigator = Navigator()

    var body: some View {
        switch userSession.appState {
        case .guest:
            NavigationStack { MainMenuView() }
                .environmentObject(navigator)
        case .registering:
            RegistrationView()
        case .registered, .admin:
            NavigationStack { MainMenuView() }
                .id(navigator.resetCount)
                .environmentObject(navigator)
        }
    }
}
