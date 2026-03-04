//
//  ViewStateStore.swift
//  someai
//
//  功能视图状态持久化 - 在切换标签页时保留各功能的状态
//

import SwiftUI

/// 各功能视图的状态存储
@Observable
final class ViewStateStore {
    static let shared = ViewStateStore()

    // MARK: - Chat State
    var chatInputText: String = ""
    var chatMessages: [ChatMessage] = []
    var chatSelectedModelId: String = "qwen2.5-1.5b-instruct"
    var chatIsGenerating: Bool = false

    // MARK: - Chat Message Model
    struct ChatMessage: Identifiable, Equatable {
        let id: String
        let role: String // "user" or "assistant"
        var text: String
        var loadTimeMs: Int? = nil // 模型加载耗时（毫秒）
        var responseTimeMs: Int? = nil // 响应生成耗时（毫秒）
        var timestamp: Date = Date()
        var canRegenerate: Bool = false // 是否可以重新生成

        init(id: String = UUID().uuidString, role: String, text: String, loadTimeMs: Int? = nil, responseTimeMs: Int? = nil, canRegenerate: Bool = false) {
            self.id = id
            self.role = role
            self.text = text
            self.loadTimeMs = loadTimeMs
            self.responseTimeMs = responseTimeMs
            self.canRegenerate = canRegenerate
        }

        static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
            lhs.id == rhs.id && lhs.text == rhs.text
        }
    }

    // MARK: - Image Generation State
    var imagePrompt: String = ""
    var imageWidth: Double = 512
    var imageHeight: Double = 512
    var imageGeneratedData: Data?
    var imageIsGenerating: Bool = false

    // MARK: - TTS State
    var ttsInputText: String = ""
    var ttsSelectedLanguage: String = "zh"
    var ttsSelectedSpeaker: String = "default"
    var ttsAudioData: Data?
    var ttsIsPlaying: Bool = false
    var ttsIsGenerating: Bool = false

    // MARK: - Voice Assistant State
    var voiceTranscript: String = ""
    var voiceResponseText: String = ""
    var voiceAudioURL: URL?
    var voiceIsProcessing: Bool = false
    var voiceSelectedLLMModel: String = ""
    var voiceSelectedTTSModel: String = ""
    var voiceSelectedSTTModel: String = ""

    // MARK: - STT State
    var sttSelectedAudioURL: URL?
    var sttTranscriptText: String = ""
    var sttIsProcessing: Bool = false
    var sttSelectedModelId: String = ""

    // MARK: - OCR State
    var ocrSelectedImagePath: String = ""
    var ocrResultText: String = ""
    var ocrIsProcessing: Bool = false

    private init() {}

    // MARK: - Reset Methods

    func resetChat() {
        chatInputText = ""
        chatMessages = []
        chatIsGenerating = false
    }

    func resetImage() {
        imagePrompt = ""
        imageWidth = 512
        imageHeight = 512
        imageGeneratedData = nil
        imageIsGenerating = false
    }

    func resetTTS() {
        ttsInputText = ""
        ttsAudioData = nil
        ttsIsPlaying = false
        ttsIsGenerating = false
    }

    func resetVoiceAssistant() {
        voiceTranscript = ""
        voiceResponseText = ""
        voiceAudioURL = nil
        voiceIsProcessing = false
    }

    func resetSTT() {
        sttSelectedAudioURL = nil
        sttTranscriptText = ""
        sttIsProcessing = false
    }

    func resetOCR() {
        ocrSelectedImagePath = ""
        ocrResultText = ""
        ocrIsProcessing = false
    }
}
