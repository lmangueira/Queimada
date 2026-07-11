import SwiftUI
import BluRayBurnerCore

/// Live burn progress with phase, percentage, cancel, and terminal results (U6).
struct BurnProgressView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 16) {
            switch app.burnVM.state {
            case .idle:
                EmptyView()

            case .burning:
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 44))
                    .symbolEffect(.pulse)
                Text(phaseLabel).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                ProgressView(value: app.burnVM.overallProgress)
                    .tint(Theme.accent)
                    .frame(maxWidth: 380)
                Text("\(Int(app.burnVM.overallProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Button("Cancel Burn", role: .destructive) {
                    app.burnVM.cancel()
                }
                .buttonStyle(ClayButtonStyle())

            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(.green)
                Text("Disc burned successfully").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("The disc was finalized\(verifiedSuffix) and is readable on macOS, Windows, and Linux.")
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Done") { app.burnVM.reset() }
                    .buttonStyle(GradientButtonStyle())
                    .keyboardShortcut(.defaultAction)

            case .failed(let error):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 44)).foregroundStyle(.red)
                Text(failureTitle(error)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(failureDetail(error))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("OK") { app.burnVM.reset() }
                    .buttonStyle(GradientButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .background(Theme.insetTint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(20)
    }

    private var verifiedSuffix: String {
        app.compileVM.verifyAfterBurn ? " and verified" : ""
    }

    private var phaseLabel: String {
        switch app.burnVM.currentPhase {
        case .preparing, nil: return "Preparing…"
        case .writing: return "Writing disc…"
        case .verifying: return "Verifying disc…"
        case .finishing: return "Finishing…"
        }
    }

    private func failureTitle(_ error: DiscOperationError) -> String {
        switch error {
        case .verificationFailed: return "Verification failed"
        case .cancelled: return "Burn cancelled"
        case .writeFailed: return "Burn failed"
        case .sourceUnreadable: return "Source file unreadable"
        case .mediaUnavailable: return "No usable disc"
        case .eraseFailed: return "Erase failed"
        }
    }

    private func failureDetail(_ error: DiscOperationError) -> String {
        switch error {
        case .verificationFailed(let reason):
            return "The disc did not match the source data — do not trust it for archival. (\(reason))"
        case .cancelled:
            return "The disc may be unusable. Use a new blank disc for the next burn."
        case .writeFailed(let reason):
            return reason
        case .sourceUnreadable(let path):
            return "Could not read \(path) during the burn."
        case .mediaUnavailable(let reason):
            return reason
        case .eraseFailed(let reason):
            return reason
        }
    }
}
