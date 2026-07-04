# Blu-Ray Burner

A lean, native macOS (Sequoia 15+) app that burns **data discs** to CD, DVD,
and Blu-ray: drag files in, hit write, get a disc that reads on macOS,
Windows, and Linux. No bloatware — Apple's DiscRecording framework is the
entire burning engine.

Plan: `docs/plans/2026-07-03-001-feat-blu-ray-data-burner-plan.md`

## Status

- ✅ Core app implemented (compile-and-burn, verify, cancel, erase, image burn)
- ✅ 38 CI tests green (`swift test`) — no hardware needed
- ⏳ **U1 sandbox spike awaiting a physical burn run** — decides Mac App Store
  viability. See `Spike/README.md`. Until then, the direct (non-sandboxed)
  build is the shipping path.
- ⏳ Physical media matrix: `docs/testing/physical-burn-runbook.md`

## Build & run

Requires macOS 15 + Command Line Tools (full Xcode optional — it opens
`Package.swift` natively).

```bash
swift test                                   # CI test suite (mock-backed)
./Packaging/scripts/make-app.sh app-direct   # assemble dist/Blu-Ray Burner.app
open "dist/Blu-Ray Burner.app"

BRB_MOCK=1 "dist/Blu-Ray Burner.app/Contents/MacOS/BluRayBurner"  # UI demo without hardware
```

## Layout

| Path | Role (plan mapping) |
|---|---|
| `Sources/BluRayBurnerCore/` | Framework-free models, view-models, service protocol, mock (KTD1 seam; plan's `Model/`, `ViewModels/`, `Services/` protocol side) |
| `Sources/BluRayBurner/` | SwiftUI app + `DiscRecordingService` (the only DiscRecording-touching code) |
| `Sources/SandboxBurnSpike/` | U1 throwaway diagnostic app |
| `Tests/BluRayBurnerCoreTests/` | Swift Testing suite (38 tests) |
| `Packaging/` | Info.plists, entitlements (MAS/Direct/Spike±USB), `make-app.sh` |
| `docs/` | Plan, release docs, physical-burn runbook |

**Toolchain deviation from plan:** the plan named `BluRayBurner.xcodeproj`;
this machine has no Xcode (CLT only), so the project is a Swift Package plus a
bundle-assembly script — same outcomes (buildable app, CI tests, signed
bundles), and Xcode users can open `Package.swift` directly.

## Architecture notes

- **KTD1 seam:** everything testable depends on the `DiscBurningService`
  protocol; `MockDiscBurningService` backs tests/demo, `DiscRecordingService`
  backs reality. No `DR*` type escapes the app target.
- **KTD2:** UDF always; ISO 9660 + Joliet added on CD via an explicit
  filesystem-inclusion mask.
- **KTD5:** MVP burns finalized discs only; multisession is deferred
  (post-MVP follow-up in the plan).
- **Verify-after-burn** defaults ON; a verification mismatch is always a
  failure (AE2).
