import SwiftUI
import shared

// CANON GAP: retained launch identity #2D73BA/#330A3C != bible Colour-&-branding launch tokens;
// binding per parent spec §5.3 identity-retention; OQ-02 reconciliation deferred.
struct ContentView: View {
    var body: some View {
        // FR-06: minimal placeholder — no editor, chrome, pill, menu, or toolbar (those are M2/M3).
        // The SharedPlaceholder.shared.greeting() call is the XCFramework link-proof (FR-06).
        Text(SharedPlaceholder.shared.greeting())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
    }
}
