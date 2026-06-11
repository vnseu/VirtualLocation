//
//  LocationViewModel.swift
//  位置状态管理 — 坐标、激活状态、配置持久化
//

import Foundation
import CoreLocation
import Combine

class LocationViewModel: ObservableObject {
    @Published var latitude: Double = 31.2304   // 默认上海
    @Published var longitude: Double = 121.4737
    @Published var altitude: Double = 10.0
    @Published var horizontalAccuracy: Double = 5.0
    @Published var verticalAccuracy: Double = 5.0
    @Published var speed: Double = 0.0
    @Published var course: Double = 0.0
    @Published var isActive: Bool = false

    private let configWriter = ConfigWriter()

    init() {
        loadSavedConfig()
    }

    // MARK: - 激活/停用

    func activate() {
        isActive = true
        writeConfig()
    }

    func deactivate() {
        isActive = false
        writeConfig()
    }

    func setCoordinate(lat: Double, lon: Double) {
        latitude = lat
        longitude = lon
        if isActive {
            writeConfig()  // 即时生效
        }
    }

    // MARK: - Config Persistence

    private func writeConfig() {
        let config: [String: Any] = [
            "enabled": isActive,
            "latitude": latitude,
            "longitude": longitude,
            "altitude": altitude,
            "horizontalAccuracy": horizontalAccuracy,
            "verticalAccuracy": verticalAccuracy,
            "speed": speed,
            "course": course,
            "timestamp": Date().timeIntervalSince1970,
        ]
        configWriter.write(config: config)
    }

    private func loadSavedConfig() {
        guard let config = configWriter.read() else { return }
        latitude = config["latitude"] as? Double ?? 31.2304
        longitude = config["longitude"] as? Double ?? 121.4737
        altitude = config["altitude"] as? Double ?? 10.0
        horizontalAccuracy = config["horizontalAccuracy"] as? Double ?? 5.0
        verticalAccuracy = config["verticalAccuracy"] as? Double ?? 5.0
        speed = config["speed"] as? Double ?? 0.0
        course = config["course"] as? Double ?? 0.0
        isActive = config["enabled"] as? Bool ?? false
    }
}
