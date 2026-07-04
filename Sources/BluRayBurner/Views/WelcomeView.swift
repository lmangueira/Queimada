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

        VStack(spacing: 20) {
            VStack(spacing: 14) {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                Text("Drag files, folders, or a disc image here")
                    .font(.title3.weight(.medium))
                Text("Files and folders are burned to a cross-platform data disc.\nA single .iso / .img / .dmg can be written as a disc, or added as a file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
                dropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: 2, dash: [7])
            ))
            .contentShape(Rectangle())
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                handleDrop(providers)
            }

            Button {
                app.screen = .erase
            } label: {
                Label("Erase a rewritable disc…", systemImage: "eraser")
            }
            .adaptiveGlassButton()
        }
        .padding(.bottom, 6)
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
