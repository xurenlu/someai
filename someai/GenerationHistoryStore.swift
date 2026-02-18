//
//  GenerationHistoryStore.swift
//  someai
//
//  本机 JSON 持久化历史仓库 - 分片存储 + 索引
//

import Foundation

@Observable
@MainActor
final class GenerationHistoryStore {
    static let shared = GenerationHistoryStore()

    private(set) var records: [GenerationRecord] = []
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "im.some.someai.history", qos: .userInitiated)

    private var historyDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("someai", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexFile: URL {
        historyDir.appendingPathComponent("index.json", isDirectory: false)
    }

    private init() {
        if let data = try? Data(contentsOf: indexFile),
           let decoded = try? decoder.decode([GenerationRecord].self, from: data) {
            records = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Public API

    func append(_ record: GenerationRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func update(id: String, status: GenerationStatus, resultRef: GenerationResultRef? = nil, errorMessage: String? = nil, durationMs: Int? = nil, payload: GenerationPayload? = nil, conversationId: String? = nil) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].status = status
        if let ref = resultRef { records[idx].resultRef = ref }
        if let err = errorMessage { records[idx].errorMessage = err }
        if let dur = durationMs { records[idx].durationMs = dur }
        if let p = payload { records[idx].payload = p }
        if let cid = conversationId { records[idx].conversationId = cid }
        persist()
    }

    /// 为多条记录设置会话 ID（归档时批量关联）
    func setConversationId(_ conversationId: String, forRecordIds ids: [String]) {
        for id in ids {
            guard let idx = records.firstIndex(where: { $0.id == id }) else { continue }
            records[idx].conversationId = conversationId
        }
        persist()
    }

    /// 聊天会话列表（按最后消息时间倒序）
    func chatConversations() -> [ChatConversation] {
        let chatRecords = records.filter { $0.kind == .chat }
        let grouped = Dictionary(grouping: chatRecords) { r -> String in
            r.conversationId ?? "legacy-\(r.id)"
        }
        return grouped.map { (cid, recs) in
            let sorted = recs.sorted { $0.createdAt < $1.createdAt }
            let first = sorted.first
            let title = first.flatMap { r in
                r.payload.chat?.prompt ?? r.resultRef?.text
            } ?? ""
            return ChatConversation(
                id: cid.hasPrefix("legacy-") ? (first?.id ?? cid) : cid,
                title: String(title.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines),
                lastMessageAt: sorted.last?.createdAt ?? Date(),
                messageCount: sorted.count * 2
            )
        }
        .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// 指定会话的消息记录（按时间正序）
    func messages(forConversationId conversationId: String) -> [GenerationRecord] {
        records
            .filter { $0.kind == .chat && ($0.conversationId == conversationId || $0.id == conversationId) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func delete(id: String) {
        records.removeAll { $0.id == id }
        persist()
    }

    func record(byId id: String) -> GenerationRecord? {
        records.first { $0.id == id }
    }

    /// 返回用于保存生成结果的本地文件 URL（TTS/Image），使用设置中的输出目录
    func outputFileURL(recordId: String, kind: GenerationKind, ext: String) -> URL {
        let baseDir = EngineConfig.shared.outputDirectory
        let subdir = baseDir.appendingPathComponent(kind.rawValue, isDirectory: true)
        try? fileManager.createDirectory(at: subdir, withIntermediateDirectories: true)
        return subdir.appendingPathComponent("\(recordId).\(ext)", isDirectory: false)
    }

    func filtered(kind: GenerationKind? = nil, status: GenerationStatus? = nil, keyword: String? = nil) -> [GenerationRecord] {
        var result = records
        if let k = kind {
            result = result.filter { $0.kind == k }
        }
        if let s = status {
            result = result.filter { $0.status == s }
        }
        if let kw = keyword, !kw.isEmpty {
            let lower = kw.lowercased()
            result = result.filter { record in
                switch record.kind {
                case .chat:
                    return record.payload.chat?.prompt.lowercased().contains(lower) ?? false
                case .tts:
                    return record.payload.tts?.text.lowercased().contains(lower) ?? false
                case .image:
                    return record.payload.image?.prompt.lowercased().contains(lower) ?? false
                case .ocr:
                    return record.payload.ocr?.imagePath.lowercased().contains(lower) ?? false
                        || (record.resultRef?.text?.lowercased().contains(lower) ?? false)
                case .voiceChat:
                    let vc = record.payload.voiceChat
                    return vc?.userText.lowercased().contains(lower) ?? false
                        || vc?.assistantText.lowercased().contains(lower) ?? false
                }
            }
        }
        return result
    }

    // MARK: - Persistence

    private func persist() {
        let data = records
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let encoded = try self.encoder.encode(data)
                try encoded.write(to: self.indexFile)
            } catch {
                print("[GenerationHistoryStore] persist error: \(error)")
            }
        }
    }

}
