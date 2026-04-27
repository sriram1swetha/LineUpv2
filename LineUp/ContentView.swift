import SwiftUI

struct ContentView: View {
    @EnvironmentObject var userSession: UserSession

    var body: some View {
        switch userSession.appState {
        case .guest:
            // Guest: show main menu, intro level available, registration gated
            NavigationStack { MainMenuView() }
        case .registering:
            RegistrationView()
        case .registered, .admin:
            NavigationStack { MainMenuView() }
        }
    }
}
