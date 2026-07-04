# Liquid Glass — local reference & our adoption strategy

Source: [Liquid Glass — Technology Overviews](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
and [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
(fetched 2026-07-04). WWDC 2025 sessions: *Meet Liquid Glass* (219), *Get to
know the new design system* (356), *Build a SwiftUI app with the new design* (323),
*Build an AppKit app with the new design* (310).

## What it is

Apple's dynamic material (macOS 26 "Tahoe" era, WWDC 2025): translucent,
glass-like surfaces with fluid behavior, used for **controls and navigation —
never the content layer**. Standard SwiftUI/AppKit components adopt it
automatically when the app is built with the macOS 26 SDK.

## Design principles (apply regardless of SDK)

1. Content first — navigation/controls float above; keep the most important
   content in focus.
2. Use color judiciously — controls stay legible; let content show through.
3. Don't overuse glass — only critical functional elements; glass on the
   content layer distracts and degrades UX.
4. Standard components over custom chrome — remove custom backgrounds from
   toolbars/sidebars/bars/sheets; they interfere with system effects
   (scroll edge effects, etc).
5. Concentric geometry — capsules and continuous rounded rects that nest
   cleanly.
6. Section headers use title-style capitalization (no ALL CAPS); grouped
   form style (`FormStyle.grouped`).

## The SwiftUI API (macOS 26 SDK)

| API | Purpose |
|---|---|
| `View.glassEffect(_:in:)` | Apply glass to a custom view in a shape. Variants compose: `.regular`, `.clear`, `.tint(_)`, `.interactive()` — e.g. `.glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())` |
| `GlassEffectContainer` | Group multiple glass elements: performance + fluid morphing between shapes |
| `glassEffectID(_:)` | Identity for morph animations inside a container |
| `.buttonStyle(.glass)` / `.glassProminent` | Glass button styles |
| `View.safeAreaBar(edge:alignment:spacing:content:)` | Custom bars with scroll-edge effect |
| `.backgroundExtensionEffect()` | Extend content under sidebars/inspectors (mirrored + blurred) |

AppKit: `NSGlassEffectView`, `NSGlassEffectContainerView`, `NSButton.BezelStyle.glass`.
Auto-adopting components include `NavigationSplitView`, toolbars, `.listStyle(.sidebar)`,
sheets, popovers.

## Accessibility & performance

- **Reduced transparency / reduced motion**: standard components adapt
  automatically; custom glass must be tested manually with these enabled.
- Combine custom glass in one `GlassEffectContainer` where possible; profile.
- Legibility with all accessibility options on is a ship gate.

## SDK compatibility — the part that matters for us

- Apps built against **older SDKs keep the legacy appearance** on new OS
  versions (no surprise reskin).
- The glass APIs **do not exist in the macOS 15 SDK** — code referencing them
  only compiles with the macOS 26 SDK (Xcode 26 / Swift 6.2+ toolchain).
- (`UIDesignRequiresCompatibility` is the iOS-side opt-out during transition.)

## Our adoption strategy (macOS 15 target, CLT/Swift 6.1 today)

We target Sequoia 15+ (R13), built with CLT Swift 6.1 + macOS 15 SDK, so:

1. **Design-principle alignment now** (SDK-independent):
   - System materials only — no custom chrome: status bar uses `.bar`,
     sidebar uses `.listStyle(.sidebar)`, controls are standard.
   - Glass-shaped custom surfaces: capsules / continuous rounded rects for
     the capacity bar, status chips, and progress cards.
   - Content-first layout: the disc tree is the content; chrome floats.
2. **Compat shim** — `Sources/BluRayBurner/Views/GlassCompat.swift`:
   - `.adaptiveGlass(in:)` and `.adaptiveGlassProminentButton()` apply the
     real Liquid Glass APIs behind `#if compiler(>=6.2)` +
     `if #available(macOS 26, *)`, falling back to `.regularMaterial`
     backgrounds / `.borderedProminent` on macOS 15 or older toolchains.
   - On this machine the 26-branch compiles out entirely; it activates —
     **unverified until first built with the Xcode 26 toolchain** — when the
     toolchain/SDK arrives. First build with Xcode 26: compile, run, and eye
     the glass branch before shipping it.
3. **When we move to the macOS 26 SDK**:
   - Standard components (sidebar, toolbar, sheets) upgrade for free.
   - Audit: remove any custom background that fights system effects.
   - Consider `GlassEffectContainer` around the status bar + capacity bar
     cluster, `.buttonStyle(.glassProminent)` on Burn.
   - Re-test with Reduce Transparency and Reduce Motion enabled.

## Checklist for the eventual SDK bump

- [ ] Build with Xcode 26+ / Swift 6.2+ toolchain; fix compat-shim branch if API drifted
- [ ] Verify sidebar/toolbar/sheet auto-adoption looks right
- [ ] Swap shim fallbacks for real glass where it earns its keep (controls only)
- [ ] Group custom glass in `GlassEffectContainer`
- [ ] Test: Reduce Transparency, Reduce Motion, Increase Contrast
- [ ] Re-run the physical smoke row 11 (UI responsiveness during burns)
