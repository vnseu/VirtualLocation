//
//  SettingsView.swift
//  高级设置 — 精度、速度、朝向等参数调节
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var locationVM: LocationViewModel
    @AppStorage("autoRefresh") private var autoRefresh = false
    @AppStorage("refreshInterval") private var refreshInterval = 1.0

    var body: some View {
        NavigationView {
            Form {
                // === 坐标精度 ===
                Section {
                    HStack {
                        Text("水平精度")
                        Spacer()
                        Text("\(String(format: "%.0f", locationVM.horizontalAccuracy)) m")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $locationVM.horizontalAccuracy, in: 1...100, step: 1) {
                        Text("水平精度")
                    } onEditingChanged: { _ in
                        if locationVM.isActive { locationVM.activate() }
                    }

                    HStack {
                        Text("垂直精度")
                        Spacer()
                        Text("\(String(format: "%.0f", locationVM.verticalAccuracy)) m")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $locationVM.verticalAccuracy, in: 1...100, step: 1) {
                        Text("垂直精度")
                    } onEditingChanged: { _ in
                        if locationVM.isActive { locationVM.activate() }
                    }
                } header: {
                    Label("精度设置", systemImage: "scope")
                }

                // === 海拔 ===
                Section {
                    HStack {
                        Text("海拔高度")
                        Spacer()
                        Text("\(String(format: "%.1f", locationVM.altitude)) m")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $locationVM.altitude, in: -500...9000, step: 0.5) {
                        Text("海拔")
                    } onEditingChanged: { _ in
                        if locationVM.isActive { locationVM.activate() }
                    }
                } header: {
                    Label("海拔", systemImage: "mountain.2.fill")
                }

                // === 运动模拟 ===
                Section {
                    HStack {
                        Text("移动速度")
                        Spacer()
                        Text("\(String(format: "%.1f", locationVM.speed)) m/s")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $locationVM.speed, in: 0...100, step: 0.5) {
                        Text("速度")
                    } onEditingChanged: { _ in
                        if locationVM.isActive { locationVM.activate() }
                    }

                    HStack {
                        Text("朝向")
                        Spacer()
                        Text("\(String(format: "%.0f", locationVM.course))°")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $locationVM.course, in: 0...360, step: 1) {
                        Text("朝向")
                    } onEditingChanged: { _ in
                        if locationVM.isActive { locationVM.activate() }
                    }
                } header: {
                    Label("运动模拟", systemImage: "figure.walk")
                }

                // === 注入模式 ===
                Section {
                    Toggle("自动刷新位置", isOn: $autoRefresh)
                    if autoRefresh {
                        HStack {
                            Text("刷新间隔")
                            Spacer()
                            Text("\(String(format: "%.1f", refreshInterval)) 秒")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $refreshInterval, in: 0.5...10, step: 0.5)
                    }
                } header: {
                    Label("注入模式", systemImage: "arrow.triangle.merge")
                } footer: {
                    Text("自动刷新会按间隔重复注入假定位给目标 App")
                }

                // === 信息 ===
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("平台")
                        Spacer()
                        Text("TrollStore")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("最低支持")
                        Spacer()
                        Text("iOS 14.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("关于", systemImage: "info.circle")
                }

                // === 手动坐标输入 ===
                Section {
                    NavigationLink {
                        ManualCoordinateView(locationVM: locationVM)
                    } label: {
                        Label("手动输入坐标", systemImage: "keyboard")
                    }

                    NavigationLink {
                        CoordinateConverterView(locationVM: locationVM)
                    } label: {
                        Label("坐标转换工具", systemImage: "arrow.triangle.swap")
                    }
                } header: {
                    Label("工具", systemImage: "wrench.and.screwdriver.fill")
                }
            }
            .navigationTitle("设置")
        }
    }
}

// MARK: - Manual Coordinate Input

struct ManualCoordinateView: View {
    @ObservedObject var locationVM: LocationViewModel
    @State private var latDeg = ""
    @State private var latMin = ""
    @State private var latSec = ""
    @State private var lonDeg = ""
    @State private var lonMin = ""
    @State private var lonSec = ""
    @State private var useDMS = false

    var body: some View {
        Form {
            Section {
                Toggle("度分秒格式", isOn: $useDMS)
            }

            if useDMS {
                Section("纬度 (N+)") {
                    HStack {
                        TextField("度", text: $latDeg).keyboardType(.numberPad)
                        Text("°")
                        TextField("分", text: $latMin).keyboardType(.numberPad)
                        Text("'")
                        TextField("秒", text: $latSec).keyboardType(.decimalPad)
                        Text("\"")
                    }
                }
                Section("经度 (E+)") {
                    HStack {
                        TextField("度", text: $lonDeg).keyboardType(.numberPad)
                        Text("°")
                        TextField("分", text: $lonMin).keyboardType(.numberPad)
                        Text("'")
                        TextField("秒", text: $lonSec).keyboardType(.decimalPad)
                        Text("\"")
                    }
                }
            } else {
                Section("纬度") {
                    TextField("31.2304", text: Binding(
                        get: { String(locationVM.latitude) },
                        set: { locationVM.latitude = Double($0) ?? locationVM.latitude }
                    ))
                    .keyboardType(.decimalPad)
                }
                Section("经度") {
                    TextField("121.4737", text: Binding(
                        get: { String(locationVM.longitude) },
                        set: { locationVM.longitude = Double($0) ?? locationVM.longitude }
                    ))
                    .keyboardType(.decimalPad)
                }
            }

            Section {
                Button("应用") {
                    if useDMS {
                        if let lat = dmsToDecimal(deg: latDeg, min: latMin, sec: latSec),
                           let lon = dmsToDecimal(deg: lonDeg, min: lonMin, sec: lonSec) {
                            locationVM.latitude = lat
                            locationVM.longitude = lon
                        }
                    }
                }
            }
        }
        .navigationTitle("手动输入坐标")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dmsToDecimal(deg: String, min: String, sec: String) -> Double? {
        guard let d = Double(deg), let m = Double(min), let s = Double(sec) else { return nil }
        return d + m / 60.0 + s / 3600.0
    }
}

// MARK: - Coordinate Converter

struct CoordinateConverterView: View {
    @ObservedObject var locationVM: LocationViewModel

    @State private var inputWGS84 = ""
    @State private var inputGCJ02 = ""
    @State private var inputBD09 = ""

    var body: some View {
        Form {
            Section("WGS-84 (GPS原始)") {
                TextField("lat,lon", text: $inputWGS84)
                Button("转为 GCJ-02 (火星坐标)") {
                    if let (lat, lon) = parseCoord(inputWGS84) {
                        let (gLat, gLon) = wgs84ToGcj02(lat: lat, lon: lon)
                        locationVM.latitude = gLat
                        locationVM.longitude = gLon
                    }
                }
            }
            Section("GCJ-02 (火星/高德)") {
                TextField("lat,lon", text: $inputGCJ02)
                Button("转为 WGS-84") {
                    if let (lat, lon) = parseCoord(inputGCJ02) {
                        let (wLat, wLon) = gcj02ToWgs84(lat: lat, lon: lon)
                        locationVM.latitude = wLat
                        locationVM.longitude = wLon
                    }
                }
            }
            Section("BD-09 (百度)") {
                TextField("lat,lon", text: $inputBD09)
                Button("转为 GCJ-02") {
                    if let (lat, lon) = parseCoord(inputBD09) {
                        let (gLat, gLon) = bd09ToGcj02(lat: lat, lon: lon)
                        locationVM.latitude = gLat
                        locationVM.longitude = gLon
                    }
                }
            }
        }
        .navigationTitle("坐标转换")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func parseCoord(_ s: String) -> (Double, Double)? {
        let parts = s.components(separatedBy: CharacterSet(charactersIn: ",; \t"))
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }

    // WGS-84 → GCJ-02
    private func wgs84ToGcj02(lat: Double, lon: Double) -> (Double, Double) {
        let a = 6378245.0
        let ee = 0.00669342162296594323
        var dLat = transformLat(lon - 105.0, lat - 35.0)
        var dLon = transformLon(lon - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * Double.pi)
        return (lat + dLat, lon + dLon)
    }

    private func gcj02ToWgs84(lat: Double, lon: Double) -> (Double, Double) {
        let (gLat, gLon) = wgs84ToGcj02(lat: lat, lon: lon)
        return (lat * 2 - gLat, lon * 2 - gLon)
    }

    private func bd09ToGcj02(lat: Double, lon: Double) -> (Double, Double) {
        let x = lon - 0.0065
        let y = lat - 0.006
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * Double.pi * 3000.0 / 180.0)
        let theta = atan2(y, x) - 0.000003 * cos(x * Double.pi * 3000.0 / 180.0)
        return (z * sin(theta), z * cos(theta))
    }

    private func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * Double.pi) + 320.0 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return ret
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(locationVM: LocationViewModel())
    }
}
