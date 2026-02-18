//
//  GenerationModels.swift
//  someai
//
//  统一生成任务数据模型 - Chat/TTS/Image/VoiceChat
//

import Foundation

/// 生成类型
enum GenerationKind: String, Codable, CaseIterable, Identifiable {
    case chat
    case tts
    case voiceChat
    case image
    case ocr

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .tts: return "speaker.wave.2"
        case .voiceChat: return "mic.fill"
        case .image: return "photo"
        case .ocr: return "doc.text.viewfinder"
        }
    }
}

/// 生成状态
enum GenerationStatus: String, Codable {
    case pending
    case running
    case success
    case failed
}

/// 请求参数快照 - 支持重发与重样生成
struct GenerationPayload: Codable, Equatable {
    var chat: ChatPayload?
    var tts: TTSPayload?
    var image: ImagePayload?
    var voiceChat: VoiceChatPayload?
    var ocr: OcrPayload?

    init(chat: ChatPayload? = nil, tts: TTSPayload? = nil, image: ImagePayload? = nil, voiceChat: VoiceChatPayload? = nil, ocr: OcrPayload? = nil) {
        self.chat = chat
        self.tts = tts
        self.image = image
        self.voiceChat = voiceChat
        self.ocr = ocr
    }

    struct ChatPayload: Codable, Equatable {
        let prompt: String
        let temperature: Double
        let maxTokens: Int
        let modelId: String?
    }

    struct TTSPayload: Codable, Equatable {
        let text: String
        let language: String
        let speaker: String
    }

    struct ImagePayload: Codable, Equatable {
        let prompt: String
        let width: Int
        let height: Int
    }

    struct OcrPayload: Codable, Equatable {
        let imagePath: String
    }

    struct VoiceChatPayload: Codable, Equatable {
        let userText: String
        let assistantText: String
        let llmPrompt: String
        let llmTemperature: Double
        let llmMaxTokens: Int
        let ttsText: String
        let ttsLanguage: String
        let ttsSpeaker: String
    }
}

/// 结果引用 - 文本或本地文件路径
struct GenerationResultRef: Codable, Equatable {
    var text: String?
    var filePath: String?
    var mimeType: String?
}

/// 聊天会话摘要（用于历史列表）
struct ChatConversation: Identifiable {
    let id: String
    let title: String
    let lastMessageAt: Date
    let messageCount: Int
}

/// 单条生成记录
struct GenerationRecord: Identifiable, Codable, Equatable {
    let id: String
    let kind: GenerationKind
    var status: GenerationStatus
    var payload: GenerationPayload
    var resultRef: GenerationResultRef?
    var errorMessage: String?
    var durationMs: Int?
    var createdAt: Date
    var derivedFromRecordId: String?
    var engineVersion: String?
    /// 聊天会话 ID，用于分组；nil 表示旧数据或未关联
    var conversationId: String?

    init(
        id: String = UUID().uuidString,
        kind: GenerationKind,
        status: GenerationStatus = .pending,
        payload: GenerationPayload,
        resultRef: GenerationResultRef? = nil,
        errorMessage: String? = nil,
        durationMs: Int? = nil,
        createdAt: Date = Date(),
        derivedFromRecordId: String? = nil,
        engineVersion: String? = nil,
        conversationId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.payload = payload
        self.resultRef = resultRef
        self.errorMessage = errorMessage
        self.durationMs = durationMs
        self.createdAt = createdAt
        self.derivedFromRecordId = derivedFromRecordId
        self.engineVersion = engineVersion
        self.conversationId = conversationId
    }

    var canRetry: Bool { status == .failed }
    var canRegenerate: Bool { status == .success }
}
