//
//  ContentView.swift
//  主界面 — 地图选点 + 预设管理 + 一键激活
//

import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var presetManager: LocationPresetManager
    @StateObject private var locationVM = LocationViewModel()

    @State private var selectedTab = 0
    @State private var showingPresetSheet = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            // === Tab 1: 地图选点 ===
            MapPickerView(locationVM: locationVM)
                .tabItem {
                    Label("地图选点", systemImage: "map.fill")
                }
                .tag(0)

            // === Tab 2: 预设列表 ===
            PresetListView(presetManager: presetManager,
                           locationVM: locationVM)
                .tabItem {
                    Label("预设", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            // === Tab 3: 设置 ===
            SettingsView(locationVM: locationVM)
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .safeAreaInset(edge: .bottom) {
            // 底部激活栏
            VStack(spacing: 8) {
                if locationVM.isActive {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                        Text("当前: \(String(format: "%.6f", locationVM.latitude)), \(String(format: "%.6f", locationVM.longitude))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                Button(action: toggleLocation) {
                    HStack {
                        Image(systemName: locationVM.isActive ? "location.slash.fill" : "location.fill")
                        Text(locationVM.isActive ? "停用虚拟定位" : "激活虚拟定位")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(locationVM.isActive ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func toggleLocation() {
        if locationVM.isActive {
            locationVM.deactivate()
            alertMessage = "虚拟定位已停用"
        } else {
            locationVM.activate()
            alertMessage = "虚拟定位已激活！\n目标 App 将看到设定的位置"
        }
        showAlert = true
    }
}
