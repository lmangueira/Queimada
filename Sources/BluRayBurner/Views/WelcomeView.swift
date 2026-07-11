import SwiftUI
import UniformTypeIdentifiers
import BluRayBurnerCore

/// Opening screen: one drop area + the erase option. Drops route the flow —
/// a single disc image asks "write contents or add as file?"; anything else
/// goes straight to the data-disc compile screen.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var appModel = app

        VStack(spacing: 14) {
            VStack(spacing: 10) {
                if let mark = Theme.brandMark {
                    mark
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 148)
                } else {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(dropTargeted ? Theme.accent : Theme.textSecondary)
                }
                Text("Drag files, folders, or a disc image here")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Files and folders are burned to a cross-platform data disc. A single .iso / .img / .dmg can be written as a disc, or added as a file.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 470)

                Button("Erase a rewritable disc…") {
                    app.screen = .erase
                }
                .buttonStyle(ClayButtonStyle())
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.insetTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(
                dropTargeted ? Theme.accent : Theme.accent.opacity(0.35),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 7])
            ))
            .contentShape(Rectangle())
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                handleDrop(providers)
            }

            DriveStatusPill()
                .frame(height: 32)
        }
        .padding(20)
        .confirmationDialog(
            "“\(app.pendingImageURL?.lastPathComponent ?? "")” is a disc image",
            isPresented: Binding(
                get: { appModel.pendingImageURL != nil },
                set: { if !$0 { appModel.pendingImageURL = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Write Image Contents to Disc") { app.chooseWriteImage() }
            Button("Add as a File on a Data Disc") { app.chooseAddImageAsFile() }
            Button("Cancel", role: .cancel) { appModel.pendingImageURL = nil }
        } message: {
            Text("Write the image’s contents so the disc IS the image — or add the image file itself to a data disc (e.g. archiving several ISOs on one Blu-ray).")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        // Route once ALL dropped URLs resolved — the single-image question
        // must see the complete drop, not the first arrival.
        group.notify(queue: .main) {
            app.handleWelcomeDrop(urls: urls)
        }
        return accepted
    }
}
