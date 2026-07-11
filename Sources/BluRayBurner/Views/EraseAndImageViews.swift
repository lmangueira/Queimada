import SwiftUI
import UniformTypeIdentifiers
import BluRayBurnerCore

/// Erase rewritable media: quick or complete (U7).
struct EraseView: View {
    @Environment(AppModel.self) private var app
    @State private var mode: EraseMode = .quick

    var body: some View {
        VStack(spacing: 16) {
            switch app.eraseVM.state {
            case .idle:
                if app.eraseVM.canErase {
                    Image(systemName: "eraser.fill").font(.system(size: 44)).foregroundStyle(Theme.textSecondary)
                    Text("Erase the inserted disc").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Picker("Mode", selection: $mode) {
                        Text("Quick — make the disc appear blank").tag(EraseMode.quick)
                        Text("Complete — erase every byte (slower)").tag(EraseMode.complete)
                    }
                    .pickerStyle(.radioGroup)
                    .frame(maxWidth: 360)
                    Button("Erase Disc", role: .destructive) {
                        app.eraseVM.erase(mode: mode)
                    }
                    .buttonStyle(GradientButtonStyle(gradient: Theme.burnGradient, shadow: Color(hex: 0x84221C).opacity(0.4)))
                } else {
                    ContentUnavailableView(
                        "No rewritable disc",
                        systemImage: "eraser",
                        description: Text("Insert a CD-RW, DVD-RW/+RW, or BD-RE to erase it.")
                    )
                }

            case .erasing(let progress):
                ProgressView(value: progress.fractionComplete) { Text("Erasing…") }
                    .frame(maxWidth: 380)

            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("Disc erased").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Button("Done") { app.eraseVM.reset() }
                    .buttonStyle(GradientButtonStyle())
                    .keyboardShortcut(.defaultAction)

            case .failed(let error):
                Image(systemName: "xmark.octagon.fill").font(.system(size: 44)).foregroundStyle(.red)
                Text("Erase failed").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(String(describing: error)).foregroundStyle(Theme.textSecondary)
                Button("OK") { app.eraseVM.reset() }
                    .buttonStyle(GradientButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(20)
    }
}

/// Burn an existing .iso/.dmg/.img verbatim (U8). Reached from the welcome
/// flow with an image already selected; shows the image's details before
/// committing to the burn.
struct ImageBurnView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var imageVM = app.imageVM

        VStack(spacing: 16) {
            if case .idle = app.burnVM.state {
                if let image = app.imageVM.selectedImage {
                    imageInfoCard(image)
                    validationLabel
                    Toggle("Verify after burn", isOn: $imageVM.verifyAfterBurn)
                        .toggleStyle(QueimadaCheckboxStyle())
                    HStack {
                        Button("Choose Different Image…") { chooseImage() }
                            .buttonStyle(QuietButtonStyle())
                        Button {
                            guard let device = app.deviceMonitor.currentDevice,
                                  let url = app.imageVM.selectedImage else { return }
                            app.burnVM.startImageBurn(
                                imageURL: url,
                                device: device,
                                verifyAfterBurn: app.imageVM.verifyAfterBurn
                            )
                        } label: {
                            Label("Burn Image", systemImage: "flame")
                        }
                        .buttonStyle(GradientButtonStyle(gradient: Theme.burnGradient, shadow: Color(hex: 0x84221C).opacity(0.4)))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!app.imageVM.canBurn)
                    }
                } else {
                    // Only reachable via "Choose Different Image…" → Cancel.
                    Button("Choose Image…") { chooseImage() }
                        .buttonStyle(QuietButtonStyle())
                }
            } else {
                BurnProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    /// The useful facts about the image before burning it.
    private func imageInfoCard(_ image: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text(image.lastPathComponent)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Size").foregroundStyle(Theme.textSecondary)
                    Text(app.imageVM.imageSizeBytes.map(ByteFormat.string) ?? "—")
                        .monospacedDigit()
                }
                GridRow {
                    Text("Kind").foregroundStyle(Theme.textSecondary)
                    Text(kindDescription(image))
                }
                GridRow {
                    Text("Modified").foregroundStyle(Theme.textSecondary)
                    Text(modifiedDescription(image))
                }
                GridRow {
                    Text("Location").foregroundStyle(Theme.textSecondary)
                    Text(image.deletingLastPathComponent().path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300, alignment: .leading)
                }
                if let media = app.deviceMonitor.currentMedia, let size = app.imageVM.imageSizeBytes {
                    GridRow {
                        Text("Target disc").foregroundStyle(Theme.textSecondary)
                        Text("\(media.type.rawValue) — \(ByteFormat.string(max(media.capacityBytes - size, 0))) left after burn")
                            .monospacedDigit()
                    }
                }
            }
            .font(.callout)
        }
        .padding(24)
        .background(Theme.insetTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func kindDescription(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "iso": return "ISO 9660/UDF disc image (.iso)"
        case "img": return "Raw disc image (.img)"
        case "dmg": return "Apple disk image (.dmg)"
        default: return url.pathExtension.uppercased()
        }
    }

    private func modifiedDescription(_ url: URL) -> String {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return "—"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private var validationLabel: some View {
        switch app.imageVM.validation {
        case .ok:
            EmptyView()
        case .tooLarge(let overBy):
            Label("Image exceeds disc capacity by \(ByteFormat.string(overBy))", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .noMedia:
            Label("Insert a writable disc", systemImage: "opticaldiscdrive")
                .foregroundStyle(.orange)
        case .unsupportedType(let ext):
            Label("Unsupported file type: .\(ext)", systemImage: "xmark.circle")
                .foregroundStyle(.red)
        case .unreadable:
            Label("Could not read the image file", systemImage: "xmark.circle")
                .foregroundStyle(.red)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iso"), UTType(filenameExtension: "img"), UTType.diskImage]
            .compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            app.imageVM.select(imageAt: url)
        }
    }
}
