//
//  VoiceChatView.swift
//  someai
//
//  语音聊天 - 录音 -> STT -> LLM -> TTS -> 播放，结果保存到输出目录
//

import SwiftUI
import AVFoundation
import AppKit

struct VoiceChatView: View {
    @Environment(EngineManager.self) var engineManager
    @Environment(GenerationHistoryStore.self) var historyStore
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var transcript = ""
    @State private var responseText = ""
    @State private var lastError: String?
    @State private var conversationLog: [(user: String, assistant: String)] = []
    @State private var audioEngine: AVAudioEngine?
    @State private var outputFile: AVAudioFile?
    @State private var recordingURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !conversationLog.isEmpty {
                List {
                    ForEach(Array(conversationLog.enumerated()), id: \.offset) { _, pair in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pair.user)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(pair.assistant)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if isProcessing {
                HStack {
                    ProgressView()
                    Text("voice_chat.processing")
                }
            }

            if let err = lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(isRecording ? .red : .blue)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                Text(isRecording ? "voice_chat.stop" : "voice_chat.record")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .padding()
        .navigationTitle(String(localized: "sidebar.voice_chat"))
        .onAppear { requestMicPermission() }
    }

    private func requestMicPermission() {
        #if os(iOS)
        AVAudioApplication.requestRecordPermission { _ in }
        #endif
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let outputDir = EngineConfig.shared.outputDirectory.appendingPathComponent("voice_chat", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let url = outputDir.appendingPathComponent("voice_\(UUID().uuidString).wav")
        recordingURL = url
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let bus = 0
            let format = input.inputFormat(forBus: bus)
            let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            input.installTap(onBus: bus, bufferSize: 512, format: format) { buffer, _ in
                try? file.write(from: buffer)
            }
            try engine.start()
            audioEngine = engine
            outputFile = file
            isRecording = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        outputFile = nil
        isRecording = false
        guard let url = recordingURL else { return }
        processVoiceInput(url: url)
    }

    private func processVoiceInput(url: URL) {
        isProcessing = true
        lastError = nil

        let payload = GenerationPayload(voiceChat: .init(
            userText: "",
            assistantText: "",
            llmPrompt: "",
            llmTemperature: 0.7,
            llmMaxTokens: 512,
            ttsText: "",
            ttsLanguage: "zh",
            ttsSpeaker: "default"
        ))
        let record = GenerationRecord(kind: .voiceChat, status: .running, payload: payload)
        historyStore.append(record)

        let start = Date()
        Task {
            do {
                let data = try Data(contentsOf: url)
                let text = try await EngineClient.transcribe(audioData: data)
                await MainActor.run { transcript = text }

                let llmText = try await EngineClient.generateChat(prompt: text, temperature: 0.7, maxTokens: 512)
                await MainActor.run { responseText = llmText }

                let audioData = try await EngineClient.generateTTS(text: llmText, language: "zh", speaker: "default")

                let fileURL = historyStore.outputFileURL(recordId: record.id, kind: .voiceChat, ext: "mp3")
                try? audioData.write(to: fileURL)

                let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                let updatedPayload = GenerationPayload(voiceChat: .init(
                    userText: text,
                    assistantText: llmText,
                    llmPrompt: text,
                    llmTemperature: 0.7,
                    llmMaxTokens: 512,
                    ttsText: llmText,
                    ttsLanguage: "zh",
                    ttsSpeaker: "default"
                ))

                await MainActor.run {
                    conversationLog.append((user: text, assistant: llmText))
                    historyStore.update(
                        id: record.id,
                        status: .success,
                        resultRef: .init(filePath: fileURL.path, mimeType: "audio/mpeg"),
                        durationMs: durationMs,
                        payload: updatedPayload
                    )
                    playAudio(data: audioData)
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    historyStore.update(id: record.id, status: .failed, errorMessage: error.localizedDescription)
                    isProcessing = false
                }
            }
        }
    }

    private func playAudio(data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.play()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
