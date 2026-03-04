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
    @Environment(ViewStateStore.self) var viewStateStore

    private var inputText: Binding<String> {
        Binding(
            get: { viewStateStore.ttsInputText },
            set: { viewStateStore.ttsInputText = $0 }
        )
    }

    private var selectedLanguage: Binding<String> {
        Binding(
            get: { viewStateStore.ttsSelectedLanguage },
            set: { viewStateStore.ttsSelectedLanguage = $0 }
        )
    }

    private var selectedSpeaker: Binding<String> {
        Binding(
            get: { viewStateStore.ttsSelectedSpeaker },
            set: { viewStateStore.ttsSelectedSpeaker = $0 }
        )
    }

    private var isPlaying: Binding<Bool> {
        Binding(
            get: { viewStateStore.ttsIsPlaying },
            set: { viewStateStore.ttsIsPlaying = $0 }
        )
    }

    private var audioData: Binding<Data?> {
        Binding(
            get: { viewStateStore.ttsAudioData },
            set: { viewStateStore.ttsAudioData = $0 }
        )
    }

    private var isGenerating: Binding<Bool> {
        Binding(
            get: { viewStateStore.ttsIsGenerating },
            set: { viewStateStore.ttsIsGenerating = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("tts.input_placeholder", text: inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)

            HStack {
                Picker("tts.language", selection: selectedLanguage) {
                    Text("tts.lang_zh").tag("zh")
                    Text("tts.lang_en").tag("en")
                }
                .pickerStyle(.menu)

                Picker("tts.speaker", selection: selectedSpeaker) {
                    Text("tts.speaker_default").tag("default")
                    Text("Vivian").tag("Vivian")
                    Text("Serena").tag("Serena")
                    Text("Uncle_Fu").tag("Uncle_Fu")
                    Text("Dylan").tag("Dylan")
                    Text("Eric").tag("Eric")
                    Text("Ryan").tag("Ryan")
                    Text("Aiden").tag("Aiden")
                    Text("Ono_Anna").tag("Ono_Anna")
                    Text("Sohee").tag("Sohee")
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                Button {
                    generateAndPlay()
                } label: {
                    Label("tts.play", systemImage: isPlaying.wrappedValue ? "stop.fill" : "play.fill")
                }
                .disabled(inputText.wrappedValue.isEmpty || isGenerating.wrappedValue)

                Button {
                    saveAudio()
                } label: {
                    Label("tts.save", systemImage: "square.and.arrow.down")
                }
                .disabled(audioData.wrappedValue == nil)
            }

            if isGenerating.wrappedValue {
                ProgressView("tts.generating")
            }
        }
        .padding()
        .navigationTitle(String(localized: "sidebar.tts"))
    }

    private func generateAndPlay() {
        guard !inputText.wrappedValue.isEmpty else { return }
        isGenerating.wrappedValue = true

        let payload = GenerationPayload(tts: .init(text: inputText.wrappedValue, language: selectedLanguage.wrappedValue, speaker: selectedSpeaker.wrappedValue))
        let record = GenerationRecord(kind: .tts, status: .running, payload: payload)
        historyStore.append(record)

        let start = Date()
        Task {
            do {
                let data = try await EngineClient.generateTTS(text: inputText.wrappedValue, language: selectedLanguage.wrappedValue, speaker: selectedSpeaker.wrappedValue)
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)

                let fileURL = historyStore.outputFileURL(recordId: record.id, kind: .tts, ext: "mp3")
                try? data.write(to: fileURL)

                await MainActor.run {
                    viewStateStore.ttsAudioData = data
                    historyStore.update(
                        id: record.id,
                        status: .success,
                        resultRef: .init(filePath: fileURL.path, mimeType: "audio/mpeg"),
                        durationMs: durationMs
                    )
                    isGenerating.wrappedValue = false
                    playAudio(data: data)
                }
            } catch {
                await MainActor.run {
                    historyStore.update(id: record.id, status: .failed, errorMessage: error.localizedDescription)
                    isGenerating.wrappedValue = false
                }
            }
        }
    }

    private func playAudio(data: Data) {
        do {
            let p = try AVAudioPlayer(data: data)
            p.play()
            viewStateStore.ttsIsPlaying = true
            let duration = p.duration
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                viewStateStore.ttsIsPlaying = false
            }
        } catch {
            print("[TTSView] play error: \(error)")
        }
    }

    private func saveAudio() {
        guard let data = audioData.wrappedValue else { return }
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
