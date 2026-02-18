//
//  DesignSystem.swift
//  someai
//
//  统一设计系统 - spacing / radius / typography / 状态组件
//

import SwiftUI

// MARK: - Design Tokens

enum DesignTokens {
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24
    static let spacingXL: CGFloat = 32

    static let radiusS: CGFloat = 4
    static let radiusM: CGFloat = 8
    static let radiusL: CGFloat = 12

    static let animationFast: Double = 0.15
    static let animationNormal: Double = 0.25
}

// MARK: - 统一状态组件

struct ErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: DesignTokens.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
            Spacer()
            if let onRetry {
                Button(String(localized: "history.retry")) {
                    onRetry()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DesignTokens.spacingM)
        .background(Color.red.opacity(0.1))
        .cornerRadius(DesignTokens.radiusM)
    }
}

struct LoadingState: View {
    let message: String?

    init(_ message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: DesignTokens.spacingM) {
            ProgressView()
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.spacingL)
    }
}

struct EmptyState: View {
    let title: String
    let systemImage: String
    let description: String?

    init(title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: description.map { Text($0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
