//
//  someaiApp.swift
//  someai
//
//  MacAIStudio - 本地 AI 工作站
//

import SwiftUI
import AppKit

@main
struct someaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var engineManager = EngineManager.shared
    @State private var historyStore = GenerationHistoryStore.shared
    @State private var viewStateStore = ViewStateStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engineManager)
                .environment(historyStore)
                .environment(viewStateStore)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        EngineManager.shared.stopEngine()
    }
}
