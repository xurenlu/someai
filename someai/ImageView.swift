//
//  ImageView.swift
//  someai
//
//  文生图 - prompt 输入、生成、预览、保存
//

import SwiftUI
import UniformTypeIdentifiers

struct ImageView: View {
    @State private var prompt = ""
    @State private var width: Double = 512
    @State private var height: Double = 512
    @State private var generatedImage: NSImage?
    @State private var isGenerating = false
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("image.prompt_placeholder", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Text("image.width")
                Slider(value: $width, in: 256...1024, step: 64)
                Text("\(Int(width))")
                    .frame(width: 40)
                Text("image.height")
                Slider(value: $height, in: 256...1024, step: 64)
                Text("\(Int(height))")
                    .frame(width: 40)
            }

            Button {
                generateImage()
            } label: {
                Label("image.generate", systemImage: "photo.badge.plus")
            }
            .disabled(prompt.isEmpty || isGenerating)

            if isGenerating {
                ProgressView("image.generating")
            }

            if let err = lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let img = generatedImage {
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
        guard !prompt.isEmpty else { return }
        isGenerating = true
        lastError = nil
        Task {
            do {
                let url = EngineClient.baseURL.appendingPathComponent("image").appendingPathComponent("generate")
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = ImageGenerateRequest(prompt: prompt, width: Int(width), height: Int(height))
                req.httpBody = try JSONEncoder().encode(body)
                let (data, _) = try await URLSession.shared.data(for: req)
                if let img = NSImage(data: data) {
                    await MainActor.run {
                        generatedImage = img
                        isGenerating = false
                    }
                } else {
                    await MainActor.run {
                        lastError = "Invalid image data"
                        isGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func saveImage(_ img: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "image_output.png"
        panel.begin { response in
            if response == .OK, let url = panel.url, let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
}

struct ImageGenerateRequest: Codable {
    let prompt: String
    let width: Int
    let height: Int
}
