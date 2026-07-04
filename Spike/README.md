# U1 — Sandbox Burn Spike: go/no-go for the Mac App Store

**Status: PREPARED — awaiting the physical burn run.** The spike app is built,
sandboxed, and ready; the burn itself needs an attached burner and a blank disc.

## The question this spike answers

Can a **sandboxed** app (required for Mac App Store distribution) burn a data
disc with DiscRecording when the source files were granted by the user via
**drag-and-drop** (the shipping app's acquisition path, R2/U5) — given that the
burn engine runs **out-of-process** and reads the files at burn time?

There is no optical-burning sandbox entitlement; no shipping MAS burner app is
known. This is genuinely unproven — hence the spike (plan KTD4).

**GO requires the drag-and-drop path to pass.** An open-panel-only pass is not
sufficient.

## How to run it

```bash
# Variant A: sandbox, no USB entitlement
./Packaging/scripts/make-app.sh spike && open dist/SandboxBurnSpike.app

# Variant B (run only if A fails with a device-access error):
./Packaging/scripts/make-app.sh spike-usb && open dist/SandboxBurnSpike.app
```

1. Connect the Blu-ray (or DVD) burner; insert a **blank** disc (any writable
   media — this test is about file access, not media type).
2. **Drag a folder containing a few files** from Finder into the drop zone
   (tests drag-and-drop + recursive child access), and optionally add another
   file via "Add via Open Panel…" (tests the Powerbox path for comparison).
3. Press **Burn Test Disc**. This performs a REAL burn with verify on.
4. Read the log pane (also written to `~/Documents/spike-findings.log`
   inside the app container).

## Interpreting results

| Observation | Verdict |
|---|---|
| Burn completes + verify passes with dropped folder | **GO** — record entitlement set below; sandboxed-from-the-start architecture confirmed |
| Burn fails with file-permission/read errors on dropped files | **NO-GO signal** — retry variant B; if it also fails, MAS is unreachable: ship direct-only (KTD4 fallback) |
| Burn fails with media/laser errors | Inconclusive — retry with fresh media |
| Drop works, open-panel works, but folder children unreadable | Partial — the shipping app must enumerate files (not hand folders to the engine); rerun after noting |

## Findings (fill in after the run)

- Date / machine / macOS version:
- Drive model:
- Media used:
- Variant A (no USB entitlement) result:
- Variant B (with USB entitlement) result — only if A failed:
- Drag-and-drop path: PASS / FAIL (error text: )
- Open-panel path: PASS / FAIL
- Folder children read by engine: PASS / FAIL
- **Decision: GO / NO-GO for Mac App Store**
- Entitlement set required:
