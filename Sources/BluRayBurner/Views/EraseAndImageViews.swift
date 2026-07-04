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
                    Image(systemName: "eraser.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Erase the inserted disc").font(.headline)
                    Picker("Mode", selection: $mode) {
                        Text("Quick — make the disc appear blank").tag(EraseMode.quick)
                        Text("Complete — erase every byte (slower)").tag(EraseMode.complete)
                    }
                    .pickerStyle(.radioGroup)
                    .frame(maxWidth: 360)
                    Button("Erase Disc", role: .destructive) {
                        app.eraseVM.erase(mode: mode)
                    }
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
                Text("Disc erased").font(.headline)
                Button("Done") { app.eraseVM.reset() }.keyboardShortcut(.defaultAction)

            case .failed(let error):
                Image(systemName: "xmark.octagon.fill").font(.system(size: 44)).foregroundStyle(.red)
                Text("Erase failed").font(.headline)
                Text(String(describing: error)).foregroundStyle(.secondary)
                Button("OK") { app.eraseVM.reset() }.keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

/// Burn an existing .iso/.dmg/.img verbatim (U8).
struct ImageBurnView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var imageVM = app.imageVM

        VStack(spacing: 16) {
            if case .idle = app.burnVM.state {
                if let image = app.imageVM.selectedImage {
                    Image(systemName: "doc.badge.gearshape").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text(image.lastPathComponent).font(.headline)
                    if let size = app.imageVM.imageSizeBytes {
                        Text(ByteFormat.string(size)).foregroundStyle(.secondary)
                    }
                    validationLabel
                    Toggle("Verify after burn", isOn: $imageVM.verifyAfterBurn)
                    HStack {
                        Button("Choose Different Image…") { chooseImage() }
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
                        .keyboardShortcut(.defaultAction)
                        .disabled(!app.imageVM.canBurn)
                    }
                } else {
                    ContentUnavailableView(
                        "Burn a disc image",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Write an .iso, .dmg, or .img file to disc exactly as-is.")
                    )
                    Button("Choose Image…") { chooseImage() }
                }
            } else {
                BurnProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
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
