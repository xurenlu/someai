//
//  ImageView.swift
//  someai
//
//  文生图 - prompt 输入、生成、预览、保存到输出目录
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ImageView: View {
    @Environment(GenerationHistoryStore.self) var historyStore
    @Environment(ViewStateStore.self) var viewStateStore

    private var prompt: Binding<String> {
        Binding(
            get: { viewStateStore.imagePrompt },
            set: { viewStateStore.imagePrompt = $0 }
        )
    }

    private var width: Binding<Double> {
        Binding(
            get: { viewStateStore.imageWidth },
            set: { viewStateStore.imageWidth = $0 }
        )
    }

    private var height: Binding<Double> {
        Binding(
            get: { viewStateStore.imageHeight },
            set: { viewStateStore.imageHeight = $0 }
        )
    }

    private var generatedImage: Binding<NSImage?> {
        Binding(
            get: {
                guard let data = viewStateStore.imageGeneratedData else { return nil }
                return NSImage(data: data)
            },
            set: { viewStateStore.imageGeneratedData = $0?.tiffRepresentation }
        )
    }

    private var isGenerating: Binding<Bool> {
        Binding(
            get: { viewStateStore.imageIsGenerating },
            set: { viewStateStore.imageIsGenerating = $0 }
        )
    }

    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("image.prompt_placeholder", text: prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Text("image.width")
                Slider(value: width, in: 256...1024, step: 64)
                Text("\(Int(width.wrappedValue))")
                    .frame(width: 40)
                Text("image.height")
                Slider(value: height, in: 256...1024, step: 64)
                Text("\(Int(height.wrappedValue))")
                    .frame(width: 40)
            }

            Button {
                generateImage()
            } label: {
                Label("image.generate", systemImage: "photo.badge.plus")
            }
            .disabled(prompt.wrappedValue.isEmpty || isGenerating.wrappedValue)

            if isGenerating.wrappedValue {
                ProgressView("image.generating")
            }

            if let err = lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let img = generatedImage.wrappedValue {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 400, maxHeight: 400)

                Button {
                    saveImage(img)
                } label: {
                    Label("image.save", systemImage: "square.and.arrow.down")
                }
            }
        }
        .padding()
        .navigationTitle(String(localized: "sidebar.image"))
    }

    private func generateImage() {
        guard !prompt.wrappedValue.isEmpty else { return }
        isGenerating.wrappedValue = true
        lastError = nil

        let w = Int(width.wrappedValue)
        let h = Int(height.wrappedValue)
        let payload = GenerationPayload(image: .init(prompt: prompt.wrappedValue, width: w, height: h))
        let record = GenerationRecord(kind: .image, status: .running, payload: payload)
        historyStore.append(record)

        let start = Date()
        Task {
            do {
                let data = try await EngineClient.generateImage(prompt: prompt.wrappedValue, width: w, height: h)
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)

                if let img = NSImage(data: data) {
                    let fileURL = historyStore.outputFileURL(recordId: record.id, kind: .image, ext: "png")
                    if let tiff = img.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: fileURL)
                    }

                    await MainActor.run {
                        viewStateStore.imageGeneratedData = data
                        historyStore.update(
                            id: record.id,
                            status: .success,
                            resultRef: .init(filePath: fileURL.path, mimeType: "image/png"),
                            durationMs: durationMs
                        )
                        isGenerating.wrappedValue = false
                    }
                } else {
                    await MainActor.run {
                        lastError = "Invalid image data"
                        historyStore.update(id: record.id, status: .failed, errorMessage: lastError)
                        isGenerating.wrappedValue = false
                    }
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    historyStore.update(id: record.id, status: .failed, errorMessage: error.localizedDescription)
                    isGenerating.wrappedValue = false
                }
            }
        }
    }

    private func saveImage(_ img: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "image_output.png"
        panel.directoryURL = EngineConfig.shared.outputDirectory
        panel.begin { response in
            if response == .OK, let url = panel.url, let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
}
