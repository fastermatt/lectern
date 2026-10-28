import SwiftUI

/// Optional, persisted workflow guidance for navigation controls.
/// Accessibility labels and safety/status messaging remain independent of this preference.
struct NavigationHelp: ViewModifier {
    @AppStorage(NavigationHelpPreference.key) private var enabled = true
    let message: String

    func body(content: Content) -> some View {
        content.help(enabled ? message : "")
    }
}

enum NavigationHelpPreference {
    static let key = "navigationHelpEnabled"
    static let defaultValue = true
}

extension View {
    func navigationHelp(_ message: String) -> some View {
        modifier(NavigationHelp(message: message))
    }
}
