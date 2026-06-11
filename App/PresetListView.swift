//
//  PresetListView.swift
//  预设列表界面
//

import SwiftUI

struct PresetListView: View {
    @ObservedObject var presetManager: LocationPresetManager
    @ObservedObject var locationVM: LocationViewModel
    @State private var showingAddSheet = false
    @State private var editingPreset: LocationPreset?
    @State private var searchText = ""

    var filteredPresets: [LocationPreset] {
        if searchText.isEmpty {
            return presetManager.presets
        }
        return presetManager.presets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredPresets) { preset in
                    PresetRow(preset: preset,
                              isActive: isPresetActive(preset)) {
                        applyPreset(preset)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            presetManager.removePreset(id: preset.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }

                        Button {
                            editingPreset = preset
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
                .onDelete { indexSet in
                    // Map filtered indices back to real indices
                    let ids = indexSet.map { filteredPresets[$0].id }
                    for id in ids {
                        presetManager.removePreset(id: id)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索预设...")
            .navigationTitle("位置预设")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                PresetEditView(preset: LocationPreset(
                    name: "新位置",
                    latitude: locationVM.latitude,
                    longitude: locationVM.longitude
                )) { newPreset in
                    presetManager.addPreset(newPreset)
                }
            }
            .sheet(item: $editingPreset) { preset in
                PresetEditView(preset: preset) { updated in
                    presetManager.updatePreset(updated)
                }
            }
        }
    }

    private func isPresetActive(_ preset: LocationPreset) -> Bool {
        locationVM.isActive &&
        abs(locationVM.latitude - preset.latitude) < 0.0001 &&
        abs(locationVM.longitude - preset.longitude) < 0.0001
    }

    private func applyPreset(_ preset: LocationPreset) {
        locationVM.latitude = preset.latitude
        locationVM.longitude = preset.longitude
        locationVM.altitude = preset.altitude
        locationVM.activate()
    }
}

// MARK: - Preset Row

struct PresetRow: View {
    let preset: LocationPreset
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .font(.title3)
                    .foregroundColor(isActive ? .green : .blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    Text(String(format: "%.4f, %.4f  alt:%.0fm",
                                preset.latitude, preset.longitude, preset.altitude))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Preset Edit View

struct PresetEditView: View {
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var altitude: String
    @State private var selectedIcon: String

    let presetId: UUID
    let onSave: (LocationPreset) -> Void

    init(preset: LocationPreset, onSave: @escaping (LocationPreset) -> Void) {
        self.presetId = preset.id
        self.onSave = onSave
        _name = State(initialValue: preset.name)
        _latitude = State(initialValue: String(preset.latitude))
        _longitude = State(initialValue: String(preset.longitude))
        _altitude = State(initialValue: String(preset.altitude))
        _selectedIcon = State(initialValue: preset.icon)
    }

    let iconOptions = [
        "mappin.and.ellipse", "building.2.fill", "building.columns.fill",
        "building.fill", "house.fill", "antenna.radiowaves.left.and.right",
        "leaf.fill", "water.waves", "sun.max.fill", "star.fill",
        "heart.fill", "flag.fill", "location.fill", "airplane",
        "car.fill", "tram.fill"
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("名称") {
                    TextField("位置名称", text: $name)
                }

                Section("坐标") {
                    HStack {
                        Text("纬度")
                            .foregroundColor(.secondary)
                        TextField("31.2304", text: $latitude)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("经度")
                            .foregroundColor(.secondary)
                        TextField("121.4737", text: $longitude)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("海拔")
                            .foregroundColor(.secondary)
                        TextField("10.0", text: $altitude)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundColor(selectedIcon == icon ? .blue : .gray)
                                .padding(8)
                                .background(
                                    selectedIcon == icon ?
                                    Color.blue.opacity(0.15) : Color.clear
                                )
                                .cornerRadius(8)
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                }
            }
            .navigationTitle(presetId == UUID() ? "添加预设" : "编辑预设")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let lat = Double(latitude),
                              let lon = Double(longitude),
                              let alt = Double(altitude) else { return }
                        let preset = LocationPreset(
                            id: presetId,
                            name: name,
                            latitude: lat,
                            longitude: lon,
                            altitude: alt,
                            icon: selectedIcon
                        )
                        onSave(preset)
                        dismiss()
                    }
                }
            }
        }
    }
}
