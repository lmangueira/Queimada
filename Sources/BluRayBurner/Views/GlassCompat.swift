import SwiftUI

// Liquid Glass compatibility layer — see docs/design/liquid-glass.md.
//
// The real Liquid Glass APIs (View.glassEffect, .buttonStyle(.glassProminent))
// exist only in the macOS 26 SDK (Xcode 26 / Swift 6.2+ toolchain). We build
// against the macOS 15 SDK today, so:
//   - with this toolchain: the fallbacks below compile in (system materials,
//     prominent bordered buttons) — the Liquid-Glass-aligned look for Sequoia;
//   - with a 6.2+ toolchain AND macOS 26 at runtime: the genuine glass APIs
//     take over, no call-site changes needed.
// NOTE: the 26-branch cannot be compile-verified on this machine — check it
// on the first Xcode 26 build (checklist in docs/design/liquid-glass.md).

extension View {
    /// Glass surface for small floating chrome (chips, bars, cards).
    /// Real Liquid Glass on macOS 26 builds; system material below.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }

    /// Prominent action button (Burn): glass-prominent on macOS 26 builds,
    /// bordered-prominent below.
    @ViewBuilder
    func adaptiveGlassProminentButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }

    /// Standard (non-prominent) glass button for secondary floating actions.
    @ViewBuilder
    func adaptiveGlassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
        #else
        self.buttonStyle(.bordered)
        #endif
    }
}
