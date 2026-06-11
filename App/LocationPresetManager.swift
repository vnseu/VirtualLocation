//
//  LocationPresetManager.swift
//  预设位置管理 — 常用地点一键切换
//

import Foundation
import Combine

struct LocationPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var icon: String  // SF Symbol name

    init(id: UUID = UUID(),
         name: String,
         latitude: Double,
         longitude: Double,
         altitude: Double = 10.0,
         icon: String = "mappin.and.ellipse") {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.icon = icon
    }
}

class LocationPresetManager: ObservableObject {
    @Published var presets: [LocationPreset] = []

    private let presetsKey = "com.virtuallocation.presets"
    private let defaults = UserDefaults.standard

    init() {
        loadPresets()
        if presets.isEmpty {
            createDefaultPresets()
        }
    }

    // MARK: - CRUD

    func addPreset(_ preset: LocationPreset) {
        presets.append(preset)
        savePresets()
    }

    func removePreset(at indexSet: IndexSet) {
        presets.remove(atOffsets: indexSet)
        savePresets()
    }

    func removePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }

    func updatePreset(_ preset: LocationPreset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
            savePresets()
        }
    }

    // MARK: - Persistence

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: presetsKey)
    }

    private func loadPresets() {
        guard let data = defaults.data(forKey: presetsKey),
              let saved = try? JSONDecoder().decode([LocationPreset].self, from: data)
        else { return }
        presets = saved
    }

    // MARK: - Defaults

    private func createDefaultPresets() {
        presets = [
            LocationPreset(name: "🏠 上海·外滩",
                           latitude: 31.2304, longitude: 121.4737, icon: "building.2.fill"),
            LocationPreset(name: "🏛 北京·天安门",
                           latitude: 39.9087, longitude: 116.3975, icon: "building.columns.fill"),
            LocationPreset(name: "🗼 深圳·腾讯大厦",
                           latitude: 22.5408, longitude: 113.9345, icon: "building.fill"),
            LocationPreset(name: "🏯 广州·广州塔",
                           latitude: 23.1065, longitude: 113.3245, icon: "antenna.radiowaves.left.and.right"),
            LocationPreset(name: "🏔 成都·太古里",
                           latitude: 30.6538, longitude: 104.0833, icon: "house.fill"),
            LocationPreset(name: "🌉 杭州·西湖",
                           latitude: 30.2439, longitude: 120.1463, icon: "leaf.fill"),
            LocationPreset(name: "🌊 厦门·鼓浪屿",
                           latitude: 24.4479, longitude: 118.0685, icon: "water.waves"),
            LocationPreset(name: "🏖 三亚·亚龙湾",
                           latitude: 18.2236, longitude: 109.6352, icon: "sun.max.fill"),
        ]
        savePresets()
    }
}
