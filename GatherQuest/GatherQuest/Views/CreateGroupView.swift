import SwiftUI
import Combine
import GoogleMaps
import CoreLocation

// ② Group creation: name, destination (Google Maps), meet time.
struct CreateGroupView: View {
    @EnvironmentObject var app: AppState
    @State private var name = ""
    @State private var destination: CLLocationCoordinate2D?
    @State private var meetTime = Date().addingTimeInterval(3600)
    @State private var showPicker = false
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button { app.screen = .start } label: {
                Image(systemName: "chevron.left").font(.title3)
            }

            Text("グループ名").font(.headline)
            TextField("例: 渋谷メンバー", text: $name)
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))

            Text("目的地").font(.headline)
            Button { showPicker = true } label: {
                ZStack {
                    if let destination {
                        StaticMapPreview(coordinate: destination)
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5))
                        Text("タッチして地図から目的地を選択")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("集合時間").font(.headline)
            DatePicker("", selection: $meetTime, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ja_JP"))

            Spacer()

            HStack {
                Spacer()
                Button { create() } label: {
                    if isCreating {
                        ProgressView().frame(width: 220, height: 56)
                    } else {
                        Text("グループを作成")
                            .font(.headline).foregroundColor(.white)
                            .frame(width: 220, height: 56)
                            .background(Capsule().fill(canCreate ? Color.blue : Color.gray))
                    }
                }
                .disabled(!canCreate || isCreating)
                Spacer()
            }
        }
        .padding(24)
        // Start GPS early so the picker can open centered on the current location.
        .onAppear { LocationService.shared.start() }
        .sheet(isPresented: $showPicker) {
            DestinationPickerView(selected: $destination)
        }
    }

    private var canCreate: Bool { !name.isEmpty && destination != nil }

    private func create() {
        guard let destination else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let result = try await GroupRepository.shared.createGroup(
                    name: name, destination: destination, meetTime: meetTime)
                app.screen = .inviteCode(groupId: result.groupId, code: result.code)
            } catch {
                app.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Non-interactive map preview

struct StaticMapPreview: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D

    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView(frame: .zero,
                             camera: GMSCameraPosition(target: coordinate, zoom: 15))
        map.isUserInteractionEnabled = false
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        map.clear()
        map.animate(to: GMSCameraPosition(target: coordinate, zoom: 15))
        let marker = GMSMarker(position: coordinate)
        marker.icon = GMSMarker.markerImage(with: .red)
        marker.map = map
    }
}

// MARK: - Full-screen destination picker (tap to drop pin)

struct DestinationPickerView: View {
    @Binding var selected: CLLocationCoordinate2D?
    @Environment(\.dismiss) var dismiss
    @State private var temp: CLLocationCoordinate2D?

    var body: some View {
        ZStack(alignment: .bottom) {
            TapPickerMap(selected: $temp)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Text(temp == nil ? "地図をタップして目的地を設定" : "この場所でよろしいですか？")
                    .font(.subheadline.bold())
                    .padding(8)
                    .background(Capsule().fill(.thinMaterial))
                Button {
                    selected = temp
                    dismiss()
                } label: {
                    Text("目的地に決定")
                        .font(.headline).foregroundColor(.white)
                        .frame(width: 220, height: 52)
                        .background(Capsule().fill(temp == nil ? Color.gray : Color.blue))
                }
                .disabled(temp == nil)
            }
            .padding(.bottom, 32)
        }
    }
}

struct TapPickerMap: UIViewRepresentable {
    @Binding var selected: CLLocationCoordinate2D?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        // Center on the user's current location; fall back to Tokyo until a GPS fix arrives.
        let current = LocationService.shared.current?.coordinate
        let target = current ?? CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
        let map = GMSMapView(frame: .zero,
                             camera: GMSCameraPosition(target: target, zoom: 15))
        map.delegate = context.coordinator
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = true
        context.coordinator.observeLocation(map: map, alreadyCentered: current != nil)
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {}

    final class Coordinator: NSObject, GMSMapViewDelegate {
        let parent: TapPickerMap
        var marker: GMSMarker?
        private var cancellable: AnyCancellable?
        private var centered = false
        init(_ parent: TapPickerMap) { self.parent = parent }

        /// If no GPS fix existed when the map opened, recenter once when the first fix arrives.
        func observeLocation(map: GMSMapView, alreadyCentered: Bool) {
            centered = alreadyCentered
            guard !centered else { return }
            cancellable = LocationService.shared.$current
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak map] loc in
                    guard let self, let map, !self.centered else { return }
                    self.centered = true
                    map.animate(to: GMSCameraPosition(target: loc.coordinate, zoom: 15))
                }
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.selected = coordinate
            marker?.map = nil
            let m = GMSMarker(position: coordinate)
            m.icon = GMSMarker.markerImage(with: .red)
            m.map = mapView
            marker = m
        }
    }
}
