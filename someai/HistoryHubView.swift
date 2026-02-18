//
//  HistoryHubView.swift
//  someai
//
//  历史中心 - 跨工具时间线、筛选、重发、重样生成
//

import SwiftUI
import AppKit

struct HistoryHubView: View {
    @Environment(GenerationHistoryStore.self) var historyStore
    @State private var filterKind: GenerationKind? = nil
    @State private var filterStatus: GenerationStatus? = nil
    @State private var keyword = ""
    @State private var selectedRecord: GenerationRecord?
    @State private var retryingId: String?
    @State private var regeneratingId: String?

    private var filteredRecords: [GenerationRecord] {
        historyStore.filtered(kind: filterKind, status: filterStatus, keyword: keyword.isEmpty ? nil : keyword)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    String(localized: "history.empty_title"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(String(localized: "history.empty_desc"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedRecord) {
                    ForEach(filteredRecords) { record in
                        HistoryRecordRow(
                            record: record,
                            isRetrying: retryingId == record.id,
                            isRegenerating: regeneratingId == record.id,
                            onRetry: { performRetry(record) },
                            onRegenerate: { performRegenerate(record) },
                            onOpenResult: { openResult(record) },
                            onDelete: { historyStore.delete(id: record.id) }
                        )
                        .tag(record)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "history.title"))
        .sheet(item: $selectedRecord) { record in
            RecordDetailSheet(record: record, onDismiss: { selectedRecord = nil })
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("history.filter_kind", selection: $filterKind) {
                Text("history.filter_all").tag(nil as GenerationKind?)
                ForEach(GenerationKind.allCases) { k in
                    Label(String(localized: String.LocalizationValue("history.kind.\(k.rawValue)")), systemImage: k.icon)
                        .tag(k as GenerationKind?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Picker("history.filter_status", selection: $filterStatus) {
                Text("history.filter_all").tag(nil as GenerationStatus?)
                Text("history.status.success").tag(GenerationStatus.success as GenerationStatus?)
                Text("history.status.failed").tag(GenerationStatus.failed as GenerationStatus?)
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            TextField("history.search_placeholder", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150)
        }
        .padding()
    }

    private func performRetry(_ record: GenerationRecord) {
        guard record.canRetry else { return }
        retryingId = record.id
        Task {
            await executeFromPayload(record: record, isRetry: true)
            await MainActor.run { retryingId = nil }
        }
    }

    private func performRegenerate(_ record: GenerationRecord) {
        guard record.canRegenerate else { return }
        regeneratingId = record.id
        Task {
            await executeFromPayload(record: record, isRetry: false)
            await MainActor.run { regeneratingId = nil }
        }
    }

    private func executeFromPayload(record: GenerationRecord, isRetry: Bool) async {
        let payload = record.payload
        let newRecord: GenerationRecord
        if let chat = payload.chat {
            newRecord = GenerationRecord(
                kind: .chat,
                status: .running,
                payload: payload,
                derivedFromRecordId: isRetry ? nil : record.id
            )
            historyStore.append(newRecord)
            do {
                let text = try await EngineClient.generateChat(prompt: chat.prompt, temperature: chat.temperature, maxTokens: chat.maxTokens, modelId: chat.modelId)
                await MainActor.run {
                    historyStore.update(id: newRecord.id, status: .success, resultRef: .init(text: text))
                }
            } catch {
                await MainActor.run {
                    historyStore.update(id: newRecord.id, status: .failed, errorMessage: error.localizedDescription)
                }
            }
        } else if let tts = payload.tts {
            newRecord = GenerationRecord(
                kind: .tts,
                status: .running,
                payload: payload,
                derivedFromRecordId: isRetry ? nil : record.id
            )
            historyStore.append(newRecord)
            do {
                let data = try await EngineClient.generateTTS(text: tts.text, language: tts.language, speaker: tts.speaker)
                let fileURL = historyStore.outputFileURL(recordId: newRecord.id, kind: .tts, ext: "mp3")
                try? data.write(to: fileURL)
                await MainActor.run {
                    historyStore.update(
                        id: newRecord.id,
                        status: .success,
                        resultRef: .init(filePath: fileURL.path, mimeType: "audio/mpeg")
                    )
                }
            } catch {
                await MainActor.run {
                    historyStore.update(id: newRecord.id, status: .failed, errorMessage: error.localizedDescription)
                }
            }
        } else if let img = payload.image {
            newRecord = GenerationRecord(
                kind: .image,
                status: .running,
                payload: payload,
                derivedFromRecordId: isRetry ? nil : record.id
            )
            historyStore.append(newRecord)
            do {
                let data = try await EngineClient.generateImage(prompt: img.prompt, width: img.width, height: img.height)
                if let nsImg = NSImage(data: data),
                   let tiff = nsImg.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    let fileURL = historyStore.outputFileURL(recordId: newRecord.id, kind: .image, ext: "png")
                    try? pngData.write(to: fileURL)
                    await MainActor.run {
                        historyStore.update(
                            id: newRecord.id,
                            status: .success,
                            resultRef: .init(filePath: fileURL.path, mimeType: "image/png")
                        )
                    }
                } else {
                    await MainActor.run {
                        historyStore.update(id: newRecord.id, status: .failed, errorMessage: "Invalid image data")
                    }
                }
            } catch {
                await MainActor.run {
                    historyStore.update(id: newRecord.id, status: .failed, errorMessage: error.localizedDescription)
                }
            }
        } else if let ocr = payload.ocr {
            newRecord = GenerationRecord(
                kind: .ocr,
                status: .running,
                payload: payload,
                derivedFromRecordId: isRetry ? nil : record.id
            )
            historyStore.append(newRecord)
            do {
                let imageData = try Data(contentsOf: URL(fileURLWithPath: ocr.imagePath))
                let text = try await EngineClient.recognizeOCR(imageData: imageData)
                let fileURL = historyStore.outputFileURL(recordId: newRecord.id, kind: .ocr, ext: "txt")
                try? text.write(to: fileURL, atomically: true, encoding: .utf8)
                await MainActor.run {
                    historyStore.update(
                        id: newRecord.id,
                        status: .success,
                        resultRef: .init(text: text, filePath: fileURL.path, mimeType: "text/plain")
                    )
                }
            } catch {
                await MainActor.run {
                    historyStore.update(id: newRecord.id, status: .failed, errorMessage: error.localizedDescription)
                }
            }
        } else if let vc = payload.voiceChat {
            newRecord = GenerationRecord(
                kind: .voiceChat,
                status: .running,
                payload: payload,
                derivedFromRecordId: isRetry ? nil : record.id
            )
            historyStore.append(newRecord)
            do {
                let llmText = try await EngineClient.generateChat(prompt: vc.llmPrompt, temperature: vc.llmTemperature, maxTokens: vc.llmMaxTokens)
                let audioData = try await EngineClient.generateTTS(text: vc.ttsText.isEmpty ? llmText : vc.ttsText, language: vc.ttsLanguage, speaker: vc.ttsSpeaker)
                let fileURL = historyStore.outputFileURL(recordId: newRecord.id, kind: .voiceChat, ext: "mp3")
                try? audioData.write(to: fileURL)
                let updatedPayload = GenerationPayload(voiceChat: .init(
                    userText: vc.userText,
                    assistantText: llmText,
                    llmPrompt: vc.llmPrompt,
                    llmTemperature: vc.llmTemperature,
                    llmMaxTokens: vc.llmMaxTokens,
                    ttsText: llmText,
                    ttsLanguage: vc.ttsLanguage,
                    ttsSpeaker: vc.ttsSpeaker
                ))
                await MainActor.run {
                    historyStore.update(
                        id: newRecord.id,
                        status: .success,
                        resultRef: .init(filePath: fileURL.path, mimeType: "audio/mpeg"),
                        payload: updatedPayload
                    )
                }
            } catch {
                await MainActor.run {
                    historyStore.update(id: newRecord.id, status: .failed, errorMessage: error.localizedDescription)
                }
            }
        } else {
            return
        }
    }

    private func openResult(_ record: GenerationRecord) {
        guard let ref = record.resultRef else { return }
        if let path = ref.filePath, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else if ref.text != nil, record.kind == .ocr {
            NSWorkspace.shared.open(EngineConfig.shared.outputDirectory.appendingPathComponent("ocr", isDirectory: true))
        }
    }
}

struct HistoryRecordRow: View {
    let record: GenerationRecord
    let isRetrying: Bool
    let isRegenerating: Bool
    let onRetry: () -> Void
    let onRegenerate: () -> Void
    let onOpenResult: () -> Void
    let onDelete: () -> Void

    private var previewText: String {
        switch record.kind {
        case .chat: return record.payload.chat?.prompt.prefix(60).description ?? ""
        case .tts: return record.payload.tts?.text.prefix(60).description ?? ""
        case .image: return record.payload.image?.prompt.prefix(60).description ?? ""
        case .ocr: return record.resultRef?.text?.prefix(60).description ?? record.payload.ocr?.imagePath.components(separatedBy: "/").last ?? ""
        case .voiceChat: return record.payload.voiceChat?.userText.prefix(60).description ?? record.payload.voiceChat?.assistantText.prefix(60).description ?? ""
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.icon)
                .foregroundStyle(record.status == .success ? .green : record.status == .failed ? .red : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(previewText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    Text(record.kind.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(record.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if record.status == .failed, let err = record.errorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if record.canRetry {
                    Button {
                        onRetry()
                    } label: {
                        if isRetrying {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Label(String(localized: "history.retry"), systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRetrying)
                }
                if record.canRegenerate {
                    Button {
                        onRegenerate()
                    } label: {
                        if isRegenerating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Label(String(localized: "history.regenerate"), systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRegenerating)
                }
                if record.resultRef?.filePath != nil || record.resultRef?.text != nil {
                    Button {
                        onOpenResult()
                    } label: {
                        Label(String(localized: "history.open"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpenResult()
        }
    }
}

struct RecordDetailSheet: View {
    let record: GenerationRecord
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "history.detail_title"))
                    .font(.title2)
                Spacer()
                Button(String(localized: "model_manager.cancel")) {
                    onDismiss()
                }
            }

            Form {
                Section(String(localized: "history.detail_params")) {
                    if let chat = record.payload.chat {
                        LabeledContent("Prompt", value: chat.prompt)
                        LabeledContent("Temperature", value: "\(chat.temperature)")
                        LabeledContent("Max tokens", value: "\(chat.maxTokens)")
                    }
                    if let tts = record.payload.tts {
                        LabeledContent("Text", value: tts.text)
                        LabeledContent("Language", value: tts.language)
                        LabeledContent("Speaker", value: tts.speaker)
                    }
                    if let img = record.payload.image {
                        LabeledContent("Prompt", value: img.prompt)
                        LabeledContent("Size", value: "\(img.width)×\(img.height)")
                    }
                    if let ocr = record.payload.ocr {
                        LabeledContent("Image", value: ocr.imagePath.components(separatedBy: "/").last ?? ocr.imagePath)
                        if let text = record.resultRef?.text {
                            LabeledContent("Result", value: text)
                        }
                    }
                    if let vc = record.payload.voiceChat {
                        LabeledContent("User", value: vc.userText)
                        LabeledContent("Assistant", value: vc.assistantText)
                    }
                }

                Section(String(localized: "history.detail_meta")) {
                    LabeledContent("Status", value: record.status.rawValue)
                    LabeledContent("Created", value: record.createdAt.formatted())
                    if let dur = record.durationMs {
                        LabeledContent("Duration", value: "\(dur) ms")
                    }
                    if let err = record.errorMessage {
                        LabeledContent("Error", value: err)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

extension GenerationRecord {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension GenerationRecord: Hashable {}
