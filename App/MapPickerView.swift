//
//  MapPickerView.swift
//  地图交互选点 — MKMapView 包装 + 长按/拖拽选点
//

import SwiftUI
import MapKit

struct MapPickerView: View {
    @ObservedObject var locationVM: LocationViewModel

    @State private var region: MKCoordinateRegion
    @State private var annotationItem: MapAnnotationItem?

    init(locationVM: LocationViewModel) {
        self.locationVM = locationVM
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: locationVM.latitude,
                longitude: locationVM.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 地图
            Map(coordinateRegion: $region,
                interactionModes: .all,
                showsUserLocation: false,
                annotationItems: annotationItems) { item in
                MapMarker(coordinate: item.coordinate, tint: .red)
            }
            .onChange(of: region.center.latitude) { _ in
                updateFromRegion()
            }
            .onChange(of: region.center.longitude) { _ in
                updateFromRegion()
            }

            // 中心十字准星
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.red)
                        .shadow(radius: 2)
                    Spacer()
                }
                Spacer()
            }

            // 搜索按钮
            VStack {
                HStack {
                    Spacer()
                    Button(action: centerToCurrentConfig) {
                        Image(systemName: "location.circle.fill")
                            .font(.title)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    .padding(12)
                }
                Spacer()
            }

            // 坐标信息浮层
            VStack {
                Spacer()
                CoordinateInfoCard(locationVM: locationVM)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("选择位置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateRegion()
        }
    }

    // MARK: - Computed

    private var annotationItems: [MapAnnotationItem] {
        guard let item = annotationItem else { return [] }
        return [item]
    }

    // MARK: - Actions

    private func updateFromRegion() {
        locationVM.setCoordinate(
            lat: region.center.latitude,
            lon: region.center.longitude
        )
        annotationItem = MapAnnotationItem(
            coordinate: region.center
        )
    }

    private func updateRegion() {
        region.center = CLLocationCoordinate2D(
            latitude: locationVM.latitude,
            longitude: locationVM.longitude
        )
        annotationItem = MapAnnotationItem(coordinate: region.center)
    }

    private func centerToCurrentConfig() {
        updateRegion()
    }
}

// MARK: - Map Annotation Item

struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Coordinate Info Card

struct CoordinateInfoCard: View {
    @ObservedObject var locationVM: LocationViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("纬度: \(String(format: "%.6f", locationVM.latitude))")
                    .font(.caption.monospacedDigit())
                Text("经度: \(String(format: "%.6f", locationVM.longitude))")
                    .font(.caption.monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("海拔: \(String(format: "%.1f m", locationVM.altitude))")
                    .font(.caption2)
                Text("精度: \(String(format: "%.0f m", locationVM.horizontalAccuracy))")
                    .font(.caption2)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
}

// MARK: - Preview

struct MapPickerView_Previews: PreviewProvider {
    static var previews: some View {
        MapPickerView(locationVM: LocationViewModel())
    }
}
