//
//  TTSView.swift
//  someai
//
//  TTS 页面 - 文本输入、语言选择、speaker、播放、保存到输出目录
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

struct TTSView: View {
    @Environment(GenerationHistoryStore.self) var historyStore
    @State private var inputText = ""
    @State private var selectedLanguage = "zh"
    @State private var selectedSpeaker = "default"
    @State private var isPlaying = false
    @State private var audioData: Data?
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("tts.input_placeholder", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)

            HStack {
                Picker("tts.language", selection: $selectedLanguage) {
                    Text("tts.lang_zh").tag("zh")
                    Text("tts.lang_en").tag("en")
                }
                .pickerStyle(.menu)

                Picker("tts.speaker", selection: $selectedSpeaker) {
                    Text("tts.speaker_default").tag("default")
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                Button {
                    generateAndPlay()
                } label: {
                    Label("tts.play", systemImage: isPlaying ? "stop.fill" : "play.fill")
                }
                .disabled(inputText.isEmpty || isGenerating)

                Button {
                    saveAudio()
                } label: {
                    Label("tts.save", systemImage: "square.and.arrow.down")
                }
                .disabled(audioData == nil)
            }

            if isGenerating {
                ProgressView("tts.generating")
            }
        }
        .padding()
        .navigationTitle(String(localized: "sidebar.tts"))
    }

    private func generateAndPlay() {
        guard !inputText.isEmpty else { return }
        isGenerating = true

        let payload = GenerationPayload(tts: .init(text: inputText, language: selectedLanguage, speaker: selectedSpeaker))
        let record = GenerationRecord(kind: .tts, status: .running, payload: payload)
        historyStore.append(record)

        let start = Date()
        Task {
            do {
                let data = try await EngineClient.generateTTS(text: inputText, language: selectedLanguage, speaker: selectedSpeaker)
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)

                let fileURL = historyStore.outputFileURL(recordId: record.id, kind: .tts, ext: "mp3")
                try? data.write(to: fileURL)

                await MainActor.run {
                    audioData = data
                    historyStore.update(
                        id: record.id,
                        status: .success,
                        resultRef: .init(filePath: fileURL.path, mimeType: "audio/mpeg"),
                        durationMs: durationMs
                    )
                    isGenerating = false
                    playAudio(data: data)
                }
            } catch {
                await MainActor.run {
                    historyStore.update(id: record.id, status: .failed, errorMessage: error.localizedDescription)
                    isGenerating = false
                }
            }
        }
    }

    private func playAudio(data: Data) {
        do {
            let p = try AVAudioPlayer(data: data)
            p.play()
            isPlaying = true
            let duration = p.duration
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                isPlaying = false
            }
        } catch {
            print("[TTSView] play error: \(error)")
        }
    }

    private func saveAudio() {
        guard let data = audioData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.audio]
        panel.nameFieldStringValue = "tts_output.mp3"
        panel.directoryURL = EngineConfig.shared.outputDirectory
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}
