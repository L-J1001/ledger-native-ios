import SwiftUI

@main
@MainActor
struct LedgerApp: App {
    @StateObject private var store = LedgerStore()
    /// 外观三态：light / dark / system（默认跟随系统）。和安卓、PWA 用同一个键名与同一套文案。
    @AppStorage("theme_mode") private var themeMode: String = "system"

    private var preferredScheme: ColorScheme? {
        switch themeMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(preferredScheme)
        }
    }
}
