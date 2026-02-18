//
//  TTSView.swift
//  someai
//
//  TTS 页面 - 文本输入、语言选择、speaker、播放、保存
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct TTSView: View {
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
        Task {
            do {
                let url = EngineClient.baseURL.appendingPathComponent("tts").appendingPathComponent("generate")
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = TTSGenerateRequest(text: inputText, language: selectedLanguage, speaker: selectedSpeaker)
                req.httpBody = try JSONEncoder().encode(body)
                let (data, _) = try await URLSession.shared.data(for: req)
                await MainActor.run {
                    audioData = data
                    isGenerating = false
                    playAudio(data: data)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    print("[TTSView] generate error: \(error)")
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
        panel.nameFieldStringValue = "tts_output.wav"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}

struct TTSGenerateRequest: Codable {
    let text: String
    let language: String
    let speaker: String
}
