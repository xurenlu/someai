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
        HSplitView {
            List(selection: $selectedItem) {
                ForEach(ChatHubItem.allCases) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .frame(width: 20)
                        Text(String(localized: String.LocalizationValue(item.title)))
                    }
                    .tag(item)
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140, idealWidth: 160, maxWidth: 200)

            // 同时保留两个视图在层级中，切换时只隐藏不销毁，以保持「新建聊天」的对话内容
            ZStack(alignment: .topLeading) {
                ChatView()
                    .opacity(selectedItem == .newChat || selectedItem == .none ? 1 : 0)
                    .allowsHitTesting(selectedItem == .newChat || selectedItem == .none)

                ChatHistoryView()
                    .opacity(selectedItem == .history ? 1 : 0)
                    .allowsHitTesting(selectedItem == .history)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(String(localized: "sidebar.chat_hub"))
    }
}
