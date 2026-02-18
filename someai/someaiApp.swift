//
//  someaiApp.swift
//  someai
//
//  MacAIStudio - 本地 AI 工作站
//

import SwiftUI

@main
struct someaiApp: App {
    @State private var engineManager = EngineManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engineManager)
        }
    }
}
