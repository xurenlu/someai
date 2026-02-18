//
//  ChatHubView.swift
//  someai
//
//  聊天中心 - 历史记录 / 新建聊天
//

import SwiftUI

struct ChatHubView: View {
    @State private var selectedItem: ChatHubItem? = .newChat

    enum ChatHubItem: String, CaseIterable, Identifiable {
        case history
        case newChat

        var id: String { rawValue }

        var title: String {
            switch self {
            case .history: return "chat_hub.history"
            case .newChat: return "chat_hub.new_chat"
            }
        }

        var icon: String {
            switch self {
            case .history: return "clock.arrow.circlepath"
            case .newChat: return "plus.bubble"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                ForEach(ChatHubItem.allCases) { item in
                    NavigationLink(value: item) {
                        Label(String(localized: String.LocalizationValue(item.title)), systemImage: item.icon)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedItem {
                case .history:
                    ChatHistoryView()
                case .newChat:
                    ChatView()
                case .none:
                    ChatView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(String(localized: "sidebar.chat_hub"))
    }
}
