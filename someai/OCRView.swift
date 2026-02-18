//
//  OCRView.swift
//  someai
//
//  图片 OCR - 选择图片、识别文字、复制/保存
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct OCRView: View {
    @Environment(GenerationHistoryStore.self) var historyStore
    @State private var selectedImage: NSImage?
    @State private var selectedImagePath: String?
    @State private var resultText: String = ""
    @State private var isRecognizing = false
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    pickImage()
                } label: {
                    Label("ocr.select_image", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(isRecognizing)

                if selectedImage != nil {
                    Button {
                        selectedImage = nil
                        selectedImagePath = nil
                        resultText = ""
                        lastError = nil
                    } label: {
                        Label("ocr.clear", systemImage: "xmark.circle")
                    }
                    .disabled(isRecognizing)
                }
            }

            if let img = selectedImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 400, maxHeight: 280)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                Text("ocr.placeholder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }

            Button {
                recognizeImage()
            } label: {
                Label("ocr.recognize", systemImage: "doc.text.viewfinder")
            }
            .disabled(selectedImage == nil || isRecognizing)

            if isRecognizing {
                ProgressView("ocr.recognizing")
            }

            if let err = lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !resultText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ocr.result")
                        .font(.headline)
                    TextEditor(text: .constant(resultText))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120, maxHeight: 300)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Button {
                            copyToClipboard()
                        } label: {
                            Label("ocr.copy", systemImage: "doc.on.doc")
                        }
                        Button {
                            saveToFile()
                        } label: {
                            Label("ocr.save", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle(String(localized: "sidebar.ocr"))
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp, .tiff]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let img = NSImage(contentsOf: url) {
                    selectedImage = img
                    selectedImagePath = url.path
                }
            }
        }
    }

    private func recognizeImage() {
        guard let img = selectedImage, let path = selectedImagePath else { return }
        isRecognizing = true
        lastError = nil
        resultText = ""

        let payload = GenerationPayload(ocr: .init(imagePath: path))
        let record = GenerationRecord(kind: .ocr, status: .running, payload: payload)
        historyStore.append(record)

        let start = Date()
        Task {
            do {
                guard let tiff = img.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    await MainActor.run {
                        lastError = "Invalid image"
                        historyStore.update(id: record.id, status: .failed, errorMessage: lastError)
                        isRecognizing = false
                    }
                    return
                }

                let text = try await EngineClient.recognizeOCR(imageData: pngData)
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)

                let fileURL = historyStore.outputFileURL(recordId: record.id, kind: .ocr, ext: "txt")
                try? text.write(to: fileURL, atomically: true, encoding: .utf8)

                await MainActor.run {
                    resultText = text
                    historyStore.update(
                        id: record.id,
                        status: .success,
                        resultRef: .init(text: text, filePath: fileURL.path, mimeType: "text/plain"),
                        durationMs: durationMs
                    )
                    isRecognizing = false
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    historyStore.update(id: record.id, status: .failed, errorMessage: lastError)
                    isRecognizing = false
                }
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText]
        panel.nameFieldStringValue = "ocr_result.txt"
        panel.directoryURL = EngineConfig.shared.outputDirectory
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? resultText.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
