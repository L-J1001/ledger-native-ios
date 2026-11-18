import SwiftUI

@main
@MainActor
struct LedgerApp: App {
    @StateObject private var store = LedgerStore()
    @StateObject private var reminder = RenewalReminder()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(reminder)
        }
    }
}
