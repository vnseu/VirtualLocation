//
//  VirtualLocationApp.swift
//  VirtualLocation - TrollStore 虚拟定位配置器
//

import SwiftUI

@main
struct VirtualLocationApp: App {
    @StateObject private var presetManager = LocationPresetManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(presetManager)
        }
    }
}
