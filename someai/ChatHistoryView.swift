//
//  ChatHistoryView.swift
//  someai
//
//  聊天历史记录 - 按会话展示
//

import SwiftUI

struct ChatHistoryView: View {
    @Environment(GenerationHistoryStore.self) var historyStore
    @State private var selectedConversation: ChatConversation?

    private var conversations: [ChatConversation] {
        historyStore.chatConversations()
    }

    var body: some View {
        Group {
            if conversations.isEmpty {
                ContentUnavailableView(
                    String(localized: "chat_history.empty_title"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(String(localized: "chat_history.empty_desc"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedConversation) {
                    ForEach(conversations) { conv in
                        ChatHistoryRow(conversation: conv)
                            .tag(conv)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "chat_hub.history"))
        .sheet(item: $selectedConversation) { conv in
            ConversationDetailSheet(
                conversationId: conv.id,
                onDismiss: { selectedConversation = nil }
            )
            .environment(historyStore)
        }
    }
}

private struct ChatHistoryRow: View {
    let conversation: ChatConversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title.isEmpty ? String(localized: "chat_history.untitled") : conversation.title)
                .lineLimit(2)
                .font(.body)
            HStack(spacing: 8) {
                Text(conversation.lastMessageAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(conversation.lastMessageAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(conversation.messageCount) \(String(localized: "chat_history.messages"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ConversationDetailSheet: View {
    let conversationId: String
    @Environment(GenerationHistoryStore.self) var historyStore
    var onDismiss: () -> Void

    private var messages: [GenerationRecord] {
        historyStore.messages(forConversationId: conversationId)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(messages) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        if let prompt = record.payload.chat?.prompt {
                            HStack(alignment: .top) {
                                Image(systemName: "person.circle")
                                    .foregroundStyle(.secondary)
                                Text(prompt)
                                    .textSelection(.enabled)
                            }
                        }
                        if let text = record.resultRef?.text {
                            HStack(alignment: .top) {
                                Image(systemName: "cpu")
                                    .foregroundStyle(.secondary)
                                Text(text)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
            .navigationTitle(String(localized: "chat_hub.history"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "model_manager.cancel")) {
                        onDismiss()
                    }
                }
            }
        }
    }
}

extension ChatConversation: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: ChatConversation, rhs: ChatConversation) -> Bool {
        lhs.id == rhs.id
    }
}
