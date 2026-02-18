//
//  CreateHubView.swift
//  someai
//
//  创作中心 - 发起 Chat/TTS/VoiceChat/Image 生成
//

import SwiftUI

struct CreateHubView: View {
    @State private var selectedTool: CreateTool? = .chat

    enum CreateTool: String, CaseIterable, Identifiable {
        case chat
        case tts
        case voiceChat
        case image
        case ocr

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chat: return "sidebar.chat"
            case .tts: return "sidebar.tts"
            case .voiceChat: return "sidebar.voice_chat"
            case .image: return "sidebar.image"
            case .ocr: return "sidebar.ocr"
            }
        }

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

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTool) {
                ForEach(CreateTool.allCases) { tool in
                    NavigationLink(value: tool) {
                        Label(String(localized: String.LocalizationValue(tool.title)), systemImage: tool.icon)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedTool {
                case .chat:
                    ChatView()
                case .tts:
                    TTSView()
                case .voiceChat:
                    VoiceChatView()
                case .image:
                    ImageView()
                case .ocr:
                    OCRView()
                case .none:
                    ContentUnavailableView(
                        String(localized: "create.select_tool"),
                        systemImage: "square.grid.2x2",
                        description: Text(String(localized: "create.select_tool_desc"))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(String(localized: "create.title"))
    }
}
