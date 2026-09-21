import SwiftUI

/// App-wide backdrop: a flat `--background` fill.
///
/// This used to be a near-black canvas with two large blurred color glows, which
/// is what Liquid Glass surfaces need in order to read as translucent. The web
/// client has no such canvas — `body` is `bg-background`, full stop, and depth
/// comes from a card's 1px ring rather than from light passing through it. The
/// glows are gone for the same reason the glass is: on a flat, bordered surface
/// system they read as decoration with nothing to refract.
///
/// Kept as a view (rather than deleted and replaced with a modifier at ~50 call
/// sites) so every screen still declares its backdrop in one obvious place, and
/// so a future workspace-background feature — the web has one, gated behind
/// `data-workspace-bg` — has somewhere to live.
struct CodegBackground: View {
    var body: some View {
        WebTheme.background
            .ignoresSafeArea()
    }
}

#Preview {
    CodegBackground()
}
